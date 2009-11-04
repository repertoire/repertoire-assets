require 'pathname'
require 'rack/utils'

require 'nokogiri'
require 'stringio'
require 'open3'

module Repertoire
  module Assets
    
    # 
    # Rack middleware to construct, interpolate, and cache js + css manifests
    #
    class Manifest
      
      DIGEST_URI      = '/digest'            # basename for compressed and bundled asset files
      
      COMPRESSOR_PATH = Pathname.new(__FILE__).dirname + '../../vendor/yuicompressor-2.4.2.jar'
      COMPRESSOR_CMD  = "java -jar #{COMPRESSOR_PATH} --type %s --charset utf-8"
    
    
      # Initialize the rack manifest middleware.
      #
      # === Parameters
      # :delegate:: 
      #    The next rack app in the filter chain
      # :processor::
      #    The Repertoire Assets processor singleton
      # :options:: 
      #    Hash of configuration options
      # :logger:: 
      #    Framework's logger - defaults to STDERR
      #
      # ---
      def initialize(delegate, processor, options, logger=nil)
        @delegate  = delegate
        @processor = processor
        @options   = options
        @logger    = logger || Logger.new(STDERR)
      end


      # The core rack call to filter an http request. If the wrapped application
      # returns an html page, the manifest is converted to <script> and <link>
      # tags and interpolated into the <head>.
      #
      # For the middleware's purposes, an "html page" is
      #
      # (1) mime-type "text/html"
      # (2) contains a <head> element (i.e. not an ajax html fragment)
      #
      # Currently, html manipulation is done by constructing a DOM with nokogiri.
      #
      # In the future, an evented system similar to SAX will be used for greater
      # throughput.  Regexp manipulation is not an option since many html documents
      # contain "<head>" as quoted HTML in the body.
      #
      # ---
      def call(env)
        # get application's response
        status, headers, body = @delegate.call(env)
        
        # only reference manifest in html files
        if /^text\/html/ === headers["Content-Type"]
          uri  = Rack::Utils.unescape(env["PATH_INFO"])
          dom  = Nokogiri::HTML(join(body))
          head = dom.css('head').children

          # do not try to add manifest to html fragments
          unless head.empty?
            @logger.debug "Interpolating manifest into #{Rack::Utils.unescape(env["PATH_INFO"])}"

            head.before(html_manifest)
            body = dom.to_html
          end
        end
        
        [status, headers, body]
      end
      
      
      # Utility to join rack-style returned content
      #
      # ---
      def join(content)
        content.inject("") { |res, c| res << c; res }
      end
      
      
      # Construct an HTML fragment containing <script> and <link> tags corresponding
      # to the asset files in the manifest.
      #
      # To speed loading, css files are listed at the top.  Javascript files are listed
      # in order of their dependency requirements.  Because browsers block javascript
      # execution during the evaluation of a <script> element, the files will load in
      # appropriate order.
      #
      # If the :precache_assets option is selected, javascript and css will already
      # exist in a digest at the application public root.  In this case, we only 
      # generate a single <script> and <link> for each digest file.
      #
      # ---- Returns
      #    A string containing the HTML fragment.
      #
      # ---
      def html_manifest
        html = []
        path_prefix = @options[:path_prefix] || ''

        # reference digest files when caching
        if @options[:precache_assets]
          html << "<link rel='stylesheet' type='text/css' href='#{path_prefix}#{DIGEST_URI}.css'/>"
          html << "<script language='javascript' type='text/javascript' src='#{path_prefix}#{DIGEST_URI}.js'></script>"
        else
          manifest = @processor.manifest
          
          # output css links first since they load asynchronously
          manifest.grep(/\.css$/).each do |uri|
            html << "<link rel='stylesheet' type='text/css' href='#{path_prefix}#{uri}'/>"
          end
          
          # script requires load synchronously, in order of dependencies
          manifest.grep(/\.js$/).each do |uri|
            html << "<script language='javascript' type='text/javascript' src='#{path_prefix}#{uri}'></script>"
          end
        end
        
        html.join("\n")
      end
      
      
      # Collect all of the required js and css files from their current locations
      # in gems and bundle them together into digest files stored at the application
      # public root.  Thereafter, the web server will serve them directly.
      #
      # If the :compress_assets option is on, the YUI compressor is run on the
      # digest files.
      #
      # Urls in CSS files are rewritten to account for the file's new URI.
      # 
      # ---
      def precache!
        root     = Pathname.new( @options[:app_asset_root] ).realpath
        rewrites = {}
        
        precache_by_type(root, 'css') do |uri, code| 
          # rewrite urls in css files from digest's uri at root
          code.gsub(/url\(([^)]*)\)/) do
            (rewrites[uri] ||= []) << $1
            "url(%s)" % (Pathname.new(uri).dirname + $1).cleanpath
          end
        end
        precache_by_type(root, 'js')
        
        rewrites.each { |uri, rewritten| @logger.info "Rewrote #{ rewritten.size } urls in #{ uri }" }
        @logger.info "Cached digests to #{ root }#{DIGEST_URI}.(js|css)"
      end
      
      
      private
      
      def precache_by_type(root, type, &block)
        digest   = Pathname.new("#{root}#{DIGEST_URI}.#{type}")
        uris     = @processor.manifest.grep(/\.#{type}$/)
        provided = @processor.provided
          
        # N.B. application servers often start many processes simultaneously
        #      only first process will write the digests since it keeps files open
        return if digest.exist? && !digest.zero? && !@processor.stale?(digest.mtime)

        File.open(digest, 'w') do |f|
          bundled = Manifest.bundle(uris, provided) do |*args|
            yield(*args) if block_given?
          end
          bundled = Manifest.compress(bundled, type, @logger) if @options[:compress_assets]
          f.write(bundled)
        end
      end    
    
    
      class << self
      
        # Bundle all of the provided files of a given type into a single
        # string.  If a block is given, file contents are yielded to it.
        #
        # In the future, this will return a stream.
        #
        # ==== Parameters
        # ::uris:
        #    The processor's manifest of uris for a given type, in order
        # ::provided:
        #    The processor's hash of provided uri -> path pairs
        #
        # ==== Returns
        #  The bundled files, as a string.
        # ---
        def bundle(uris, provided, &block)
          result = ""
          uris.map do |uri|
            path     = provided[uri]
            contents = File.read(path)
            contents = yield(uri, contents) || contents if block_given?
            
            result << "/* File: #{path} */\n"
            result << contents
            result << "\n\n"
          end
        
          result
        end
      
    
        # Utility compress files using YUI compressor.
        #
        # ==== Parameters
        # ::source:
        #    The code to be compressed
        # ::type:
        #    The type - js or css
        #
        # ==== Returns
        #  The compressed code, or source if compression failed
        # ---
        def compress(source, type, logger)
          stream = StringIO.new(source)
          Open3.popen3(COMPRESSOR_CMD % type) do |stdin, stdout, stderr|
            begin
              while buffer = stream.read(4096)
                stdin.write(buffer)
              end
              stdin.close
              compressed = stdout.read
              raise "No result" if compressed.length == 0
              logger.info "Digest #{type} compression %i%% to (%ik)" % 
                                     [ 100.0 * (source.length - compressed.length) / source.length, compressed.length / 1024 ]
              return compressed
            rescue Exception => e
              logger.warn("Could not compress: #{e.message} (using #{COMPRESSOR_CMD})")
              logger.warn(stderr.read)
              logger.warn("Reverting to uncompressed digest")
              return source
            end            
          end
        end
      end
    end
  end
end