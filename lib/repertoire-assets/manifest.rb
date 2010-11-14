require 'pathname'
require 'logger'
require 'rack/utils'

require 'stringio'
require 'open3'

# require 'nokogiri'

module Repertoire
  module Assets
    
    # 
    # Rack middleware to construct, interpolate, and cache js + css manifests
    #
    class Manifest

      COMPRESSOR_PATH = Pathname.new(__FILE__).dirname + '../../vendor/yuicompressor-2.4.2.jar'
      COMPRESSOR_CMD  = "java -jar #{COMPRESSOR_PATH} --type %s --charset utf-8"
    
      # regular expression for HTML 4.0 DTD through the HTML & HEAD elements
      HTML_HEAD       = %r{^(\s*<\s*!DOCTYPE[^>]*>)?\s*<\s*HTML[^>]*>\s*<\s*HEAD[^>]*>.*?(?=</\s*HEAD[^>]*>)}im
      HEADER_BUFFER   = 1000                  # upper length limit for HTML_HEAD
    
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
      # Currently, html manipulation is done using a basic HTML 4.0-compliant
      # filter parser.  It is simple and quite efficient.
      #
      # ---
      def call(env)
        dup._call(env)
      end
      
      def _call(env)
        # get application's response
        status, headers, body = @delegate.call(env)
        
        # only reference manifest in html files
        if /^text\/html/ === headers["Content-Type"]
          # for html & html fragments, attempt to interpolate manifest
          @path_info = Rack::Utils.unescape(env["PATH_INFO"])
          @body, body = body, self
        end
        
        [status, headers, body]
      end


      # Apply a simple stream-based html 'filter parser' that conforms to the 
      # HTML 4.0 DTD to the client application's output, interpolating the html 
      # manifest into ^<doctype...>?<html...><head> (if it occurs within the first 
      # HEADER_BUFFER characters).
      #
      # HTML fragments are passed through unchanged.
      #
      # ---
      def each(&block)
        #
        # N.B. Processing HTML using regular expressions is notoriously error-prone.
        #      However, after much consideration I decided that conforming to the 
        #      HTML 4.0 DTD through <html><head> was sufficiently simple, and the 
        #      alternatives of SAX and DOM too heavy weight for use server-side on
        #      every outgoing HTML page.  For posterity, however, here is the code
        #      written in nokogiri and DOM:
        #        
        #      dom  = Nokogiri::HTML(body.to_s)
        #      head = dom.css('head').children
        #      unless head.empty?
        #        head.before(html_manifest)
        #        body = dom.to_html
        #      end
        #      
        prefix = ""
        @body.each do |chunk|
          if prefix == nil                       # already interpolated manifest
            yield chunk
          elsif prefix.size < HEADER_BUFFER      # collecting enough data to interpolate manifest
            prefix << chunk
          else                                   # attempt to interpolate one time only
            # regular expression will match only "complete" html 4.0 documents
            # fragments and all others will pass through unchanged
            prefix << chunk
            yield interpolate(prefix)
            prefix = nil                         # done interpolating
          end
        end
        
        # process single chunks
        yield interpolate(prefix) unless prefix == nil
      end


      # If the manifest can be interpolated, then do so
      #
      def interpolate(text)
        text.gsub(HTML_HEAD) do |head|
          @logger.debug "Interpolating manifest into #{@path_info}"
          "#{head}#{html_manifest}"
        end
      end

      
      # Construct an HTML fragment containing <script> and <link> tags corresponding
      # to the asset files in the manifest.
      #
      # To speed loading, css files are listed at the top.  Javascript files are listed
      # in order of their dependency requirements.  Because browsers block javascript
      # execution during the evaluation of a <script> element, the files will load in
      # appropriate order.
      #
      # If the :precache option is selected, javascript and css will already
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
        if @options[:precache]
          digest_uri = "#{path_prefix}/#{@options[:digest_basename]}"
          html << "<link rel='stylesheet' type='text/css' href='#{digest_uri}.css'/>"
          html << "<script language='javascript' type='text/javascript' src='#{digest_uri}.js'></script>"
        else
          manifest = @processor.manifest
          
          # output css links first since they load asynchronously
          manifest.grep(/\.css$/).each do |uri|
            html << "<link rel='stylesheet' type='text/css' href='#{path_prefix}#{cache_bust uri}'/>"
          end
          
          # script requires load synchronously, in order of dependencies
          manifest.grep(/\.js$/).each do |uri|
            html << "<script language='javascript' type='text/javascript' src='#{path_prefix}#{cache_bust uri}'></script>"
          end
        end
        
        html.join("\n")
      end
      
      
      # Generate a URL with the file's modification time appended.  This makes browsers reload when a
      # static asset changes.
      #
      # ---- Returns
      #    A string containing the complete uri
      #
      # ---      
      def cache_bust(uri)
        mtime = @processor.provided[uri].mtime.to_i
        "#{uri}?#{mtime}"
      end
      
      # Collect all of the required js and css files from their current locations
      # in gems and bundle them together into digest files stored at the application
      # public root.  Thereafter, the web server will serve them directly.
      #
      # If the :compress option is on, the YUI compressor is run on the
      # digest files.
      #
      # Urls in CSS files are rewritten to account for the file's new URI.
      # 
      # ---
      def precache!
        root     = Pathname.new( @options[:cache_root] ).realpath
        rewrites = {}
        
        precache_by_type(root, 'css') do |uri, code| 
          # rewrite urls in css files from digest's uri at root
          # see http://www.w3.org/TR/CSS21/syndata.html#uri
          code.gsub(/url\(\s*['"]?(.*?)['"]?\s*\)/) do
            (rewrites[uri] ||= []) << $1
            "url(%s%s)" % [ @options[:path_prefix], (Pathname.new(uri).dirname + $1).cleanpath ]
          end
        end
        precache_by_type(root, 'js')
        
        rewrites.each { |uri, rewritten| @logger.info "Rewrote #{ rewritten.size } urls in #{ uri }" }
      end
      
      
      private
      
      def precache_by_type(root, type, &block)
        digest   = Pathname.new(root) + "#{@options[:digest_basename]}.#{type}"
        uris     = @processor.manifest.grep(/\.#{type}$/)
        provided = @processor.provided
          
        # N.B. application servers often start many processes simultaneously
        #      only first process will write the digests since it keeps files open
        return if digest.exist? && !digest.zero? && !@processor.stale?(digest.mtime)

        File.open(digest, 'w') do |f|
          bundled = Manifest.bundle(uris, provided) do |*args|
            yield(*args) if block_given?
          end
          bundled = Manifest.compress(bundled, type, @logger) if @options[:compress]
          f.write(bundled)
          @logger.info "Cached #{digest}"
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
              
              if !source.empty?
                raise "No result" if compressed.empty?
                ratio = 100.0 * (source.length - compressed.length) / source.length
              end
              logger.info "Digest #{type} compression %i%% to (%ik)" % 
                                     [ratio || 0, compressed.length / 1024 ]

              return compressed
            rescue Exception => e
              logger.warn("Could not compress: #{e.message} (using #{COMPRESSOR_CMD % type})")
# CWY 13/11/2010.  Obscure errors with OS X new Java install hanging here...
#              logger.warn(stderr.read)
              logger.warn("Reverting to uncompressed digest")
              return source
            end            
          end
        end
      end
    end
  end
end