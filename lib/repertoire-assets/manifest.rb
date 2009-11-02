require 'pathname'
require 'rack/utils'

require 'erb'
require 'stringio'
require 'open3'

module Repertoire
  module Assets
    
    # 
    # Rack middleware to construct, serve, and cache js + css manifest files
    #
    class Manifest
      
      MANIFEST_URI        = '/manifest.js'
      TEMPLATE_PATH       = Pathname.new(__FILE__).dirname + '../../templates/manifest.js'
      COMPRESSOR_PATH     = Pathname.new(__FILE__).dirname + '../../vendor/yuicompressor-2.4.2.jar'
      COMPRESSOR_CMD      = "java -jar #{COMPRESSOR_PATH} --type js --charset utf-8"
    
      def initialize(delegate, processor)
        @delegate  = delegate
        @processor = processor
        
        manifest_erb = File.read(TEMPLATE_PATH)
        @template    = ERB.new(manifest_erb, nil, '-')
      
        precache! if @processor.options[:precache]
      end

      def call(env)
        response = nil
        
        unless @processor.options[:precache]
          path = Rack::Utils.unescape(env["PATH_INFO"])
          if path == MANIFEST_URI
            path = Pathname.new(path)
            content  = self.render
            response = [200, {
              "Last-Modified"  => @processor.mtime.httpdate,
              "Content-Type"   => Rack::Mime.mime_type(path.extname, 'text/plain'),
              "Content-Length" => content.size.to_s
            }, content]
          end
        end

        response || @delegate.call(env)
      end
      
      def precache!
        root = Pathname.new(@processor.options[:app_asset_root]).realpath.to_s
        cache_path = root + MANIFEST_URI
        
        File.open(cache_path, 'w') do |f| 
          f.write(self.render)
        end

        @processor.logger.info "Cached manifest to #{cache_path}"
      end
      
      def render
        manifest = @processor.manifest
        result   = ""

        @processor.logger.debug "Digesting manifest of #{manifest.size} files"
        
        # interpolate javascript files if bundling or compressing
        if @processor.options[:precache]
          javascripts = manifest.grep(/\.js$/)
          javascripts.each do |uri|
            path = @processor.provided[uri]
            result << "\n// #{path}\n"
            result << File.read(path)
          end
          manifest -= javascripts
        end
        
        # render standard manifest template
        result << @template.result(binding)
        
        # use yui compressor if requested
        if @processor.options[:precache] == :compress
          begin
            compressed = compress(result)
            @processor.logger.info "Manifest compression (%ik to %ik)" % [ result.length / 1024, compressed.length / 1024 ]
            result = compressed
          rescue Exception => e
            @processor.logger.warn("Reverting to uncompressed manifest")
          end
        end
          
        result          
      end
      
      protected
            
      def compress(js)
        stream = StringIO.new(js)
        Open3.popen3(COMPRESSOR_CMD) do |stdin, stdout, stderr|
          begin
            while buffer = stream.read(4096)
              stdin.write(buffer)
            end
            stdin.close
            result = stdout.read
            raise "No result" if result.length == 0
            result
          rescue Exception => e
            @processor.logger.warn("Could not YUI compress: #{e.message} (using #{COMPRESSOR_CMD})")
            @processor.logger.warn("YUI Compressor errors: #{stderr.read}")
            raise e
          end            
        end
      end
    end
  end
end