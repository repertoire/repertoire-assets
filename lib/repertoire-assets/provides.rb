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
      
      # pattern for uris to precache (because they will appear in the manifests)
      PRECACHE_EXCLUDE = /\.(js|css)$/
      
      # Initialize the asset provider middleware.
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


      # The core rack call to process an http request. If the asset has been 
      # required or provided by a javascript file, it is served.  Otherwise
      # the request is forwarded to the next rack app in the chain.
      #
      # ---
      def call(env)
        dup._call(env) || @delegate.call(env)
      end
    
      def _call(env)
        uri = Rack::Utils.unescape(env["PATH_INFO"])        
        if @path = @processor.provided[uri]
          @logger.debug "Mirroring #{uri} (#{Processor.pretty_path(@path)})"
          
          [200, {
            "Last-Modified"  => @path.mtime.httpdate,
            "Content-Type"   => Rack::Mime.mime_type(@path.extname, 'text/plain'),
            "Content-Length" => @path.size.to_s
          }, self]
        end
      end
    
      def each
        @path.open("rb") do |file|
          while part = file.read(CHUNK_SIZE)
            yield part
          end
        end
      end
      
      
      # Copy all provided assets from their current locations in gems to the
      # public application root.  Thereafter, the web server will serve them
      # directly.  
      #
      # Javascript and css files are ignored, since they are bundled together
      # by the manifest middleware.
      #
      # ---
      def precache!
        root = Pathname.new( @options[:app_asset_root] ).realpath

        @processor.provided.each do |uri, path|
          next if uri[PRECACHE_EXCLUDE]
          cache_path = Pathname.new("#{root}#{uri}")

          FileUtils.mkdir_p cache_path.dirname  if !cache_path.dirname.directory?
          FileUtils.cp      path, cache_path    if newer?(path, cache_path)

          @logger.info "Cached #{uri} (#{Processor.pretty_path(path)})"
        end
      end
      
      def newer?(path1, path2)
        path1.exist? && path2.exist? && path1.mtime > path2.mtime
      end
        
    end
  end
end