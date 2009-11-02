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
      
      DIGEST_URI          = '/js_digest.js'
      COMPRESSOR_PATH     = Pathname.new(__FILE__).dirname + '../../vendor/yuicompressor-2.4.2.jar'
      COMPRESSOR_CMD      = "java -jar #{COMPRESSOR_PATH} --type js --charset utf-8"
    
      def initialize(delegate, processor)
        @delegate  = delegate
        @processor = processor
      
        precache! if precache_manifest?
      end

      def call(env)
        # get application's respose
        status, headers, body = @delegate.call(env)
        
        if /^text\/html/ === headers["Content-Type"]
          # application returned html: parse and inspect
          dom  = Nokogiri::HTML(body.to_s)
          head = dom.css('head').children
          
          unless head.empty?
            # complete html page: interpolate manifest
            @processor.logger.debug "Interpolating manifest into #{Rack::Utils.unescape(env["PATH_INFO"])}"
                        
            head.before(html_manifest)
            body = dom.to_html
          end
        end
        
        [status, headers, body]
      end
      
      def html_manifest
        html = []
        manifest = @processor.manifest
          
        # output css links first since they load asynchronously
        manifest.grep(/\.css$/).each do |uri|
          html << "<link rel='stylesheet' type='text/css' href='#{path_prefix}#{uri}'/>"
        end
        
        # output script requires in dependency order
        if precache_manifest?
          html << "<script language='javascript' type='text/javascript' src='#{path_prefix}#{DIGEST_URI}'></script>"
        else
          manifest.grep(/\.js$/).each do |uri|
            html << "<script language='javascript' type='text/javascript' src='#{path_prefix}#{uri}'></script>"
          end
        end
        
        html.join("\n")
      end
      
      def precache!
        root = Pathname.new(@processor.options[:app_asset_root]).realpath.to_s
        cache_path = root + DIGEST_URI
        
        File.open(cache_path, 'w') do |f| 
          f.write(javascript_digest)
        end

        @processor.logger.info "Cached javascript digest to #{cache_path}"
      end
      
      def javascript_digest
        manifest = @processor.manifest
        result   = ""
        
        # interpolate javascript files if bundling or compressing
        if precache_manifest?
          javascripts = manifest.grep(/\.js$/)
          javascripts.each do |uri|
            path = @processor.provided[uri]
            result << "\n// #{path}\n"
            result << File.read(path)
          end
          manifest -= javascripts
        end
        
        # use yui compressor if requested
        result = compress(result) if precache_manifest? == :compress
          
        result          
      end

      protected
      
      def path_prefix
        @processor.options[:path_prefix] || ''
      end
      
      def precache_manifest?
        @processor.options[:precache]
      end
            
      def compress(source)
        stream = StringIO.new(source)
        Open3.popen3(COMPRESSOR_CMD) do |stdin, stdout, stderr|
          begin
            while buffer = stream.read(4096)
              stdin.write(buffer)
            end
            stdin.close
            compressed = stdout.read
            raise "No result" if compressed.length == 0
            @processor.logger.info "Javascript digest compression %i%% to (%ik)" % 
                                   [ 100.0 * (source.length - compressed.length) / source.length, compressed.length / 1024 ]
            return compressed
          rescue Exception => e
            @processor.logger.warn("Could not YUI compress: #{e.message} (using #{COMPRESSOR_CMD})")
            @processor.logger.warn(stderr.read)
            @processor.logger.warn("Reverting to uncompressed digest")
            return source
          end            
        end
      end
    end
  end
end