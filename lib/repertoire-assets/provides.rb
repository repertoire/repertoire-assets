require 'pathname'
require 'rack/utils'
require 'fileutils'

module Repertoire
  module Assets
    
    # 
    # Rack middleware to serve provided files from gem roots
    #
    class Provides
    
      # serve binary data from gems in blocks of this size
      CHUNK_SIZE = 8192
      
      # pattern for uris to precache
      PRECACHE_EXCLUDE = /\.js$/
    
      def initialize(delegate, processor)
        @delegate  = delegate
        @processor = processor
      
        precache! if @processor.options[:precache]
      end

      def call(env)
        response = unless @processor.options[:precache]
          dup._call(env)
        end

        response || @delegate.call(env)
      end
      
      # copy matching files from their existing locations to the public document root
      def precache!
        root = Pathname.new(@processor.options[:app_asset_root]).realpath.to_s
        @processor.provided.each do |uri, path|
          cache_path = Pathname.new(root + uri)
          next if uri[PRECACHE_EXCLUDE] || cache_path == path
          
          @processor.logger.info "Caching #{uri} to #{cache_path}"
          
          FileUtils.mkdir_p cache_path.dirname  if !cache_path.dirname.directory?
          FileUtils.cp      path, cache_path    if path.file? && !cache_path.file?
        end
      end
    
      def _call(env)
        path_info = Rack::Utils.unescape(env["PATH_INFO"])
        
        if @path = @processor.provided[path_info]

          @processor.logger.debug "Mirroring asset: #{@path} -> #{path_info}"
          
          [200, {
            "Last-Modified"  => @path.mtime.httpdate,
            "Content-Type"   => Rack::Mime.mime_type(@path.extname, 'text/plain'),
            "Content-Length" => @path.size.to_s
          }, self]
          
        else
          @delegate.call(env)
        end
      end
    
      def each
        @path.open("rb") do |file|
          while part = file.read(CHUNK_SIZE)
            yield part
          end
        end
      end
    end
  end
end