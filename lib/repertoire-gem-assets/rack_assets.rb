require 'pathname'
require 'rack/utils'

# TODO.  caching off: attempt to resolve only current request
#        caching on:  aggressively resolve all files, then always pass requests on directly
module Repertoire
  class RackAssets
    
    CHUNK_SIZE = 8192
    
    attr_accessor :resolver
    
    def initialize(app, settings={})
      @app         = app
      @settings    = settings
      @resolver    = AssetResolver.new(settings)
      
      # when precaching is on, copy and interpolate all of the provided assets once,
      # then cease operation
      if @settings[:precache]
        @resolver.precache
      end
    end

    def call(env)
      response = unless @settings[:precache]
        dup._call(env)
      end

      response || @app.call(env)
    end
    
    def _call(env)
      # determine path to serve
      path_info = Rack::Utils.unescape(env["PATH_INFO"])[1..-1]
      path_info = Pathname.new(path_info)
      
      # resolve each http request in isolation
      # TODO.  (is this threadsafe?)
      @resolver.reset!
      
      # if file exists, serve it
      if @path = @resolver.resolve(path_info)
        
        # TODO.  call require if this is a file of the appropriate type
        if @path.extname == '.js'
          content = @resolver.require(@path)
          mtimes  = @resolver.source_files.map { |f| File.mtime(f) }
          
          [200, {
            "Last-Modified"  => mtimes.max.httpdate,
            "Content-Type"   => 'text/javascript',
            "Content-Length" => content.size.to_s
          }, content]
          
        else
          [200, {
            "Last-Modified"  => @path.mtime.httpdate,
            "Content-Type"   => Rack::Mime.mime_type(@path.extname, 'text/plain'),
            "Content-Length" => @path.size.to_s
          }, self]
        end
        
      else
        nil
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