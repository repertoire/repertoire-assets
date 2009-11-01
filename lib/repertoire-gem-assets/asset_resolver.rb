require 'logger'

module Repertoire
  class AssetResolver
    
    include FileUtils

    attr_reader :options, :source_files

    DEFAULT_OPTIONS = {
      :precache     => false,
      :precache_roots => [ './app/javascripts/application.js', './app/javascripts/*.js' ],
      
      :path_prefix    => '',
      :asset_root     => 'public'
      :asset_paths    => [ '../public' ],
      :search_paths   => [ './app/javascripts/*.js', '../public/javascripts/*.js' ]
      
      :require_template => <<-JAVASCRIPT
        function(url) {
          var link = document.createElement("link");
          link.type = "text/css"; 
          link.rel = "stylesheet"; 
          link.href = url;
          document.getElementsByTagName("head")[0].appendChild(link);
        }("%s");
JAVASCRIPT
    }

    def initialize(settings={})
      @logger  = settings[:logger] || Logger.new(STDERR)
      @options = DEFAULT_OPTIONS.merge(settings)
      reset!
    end
    
    def reset!
      @source_files = []
    end

    def asset_paths
      unless @asset_paths
        @asset_paths = calculate_load_paths(options[:asset_paths])
        @logger.info("Serving assets from: #{@asset_paths.join(', ')}")
      end
      
      @asset_paths
    end
    
    def search_paths
      unless @search_paths
        @search_paths = {}
        calculate_load_paths(options[:search_paths]).each do |path|
          base = path.basename.to_s
          base.chomp!(path.extname)
          @search_paths[base] = path
        end
        @logger.info("Asset libraries: @search_paths.keys.join(', ')")
      end
      
      @search_paths
    end

    # attempt to resolve a path into a readable file
    # if the path is relative, look under all load paths
    # if it is absolute, see if the file exists and process has read permissions
    def resolve(path)
      # attempt to find file underneath load paths
      load_path = asset_paths.detect do |load_path|
        resolved_path = load_path + path

        # prohibit access to system files, directories, files unreadable by web process
        # or outside of asset load path        
        resolved_path.file? && resolved_path.readable? && contains_path?(load_path, resolved_path)
      end
      
      load_path + path if load_path
    end

    def precache
      dest = options[:asset_root]
      
      # (1) copy all gem asset paths to host application's asset root
      asset_paths.each do |path|
        cp_r("#{path}/.", dest)
      end
      
      # (2) resolve all files in precache_roots, copying to destination
      calculate_load_paths(options[:precache_roots])
      
      
      precache_roots.each do |path|
        
        
        
        Dir[File.join(path, suffix)].map { |f| Pathname.new(f).realpath }
      end
    end

    # return the interpolated content of the specified path, or nil if already processed
    def require(path, context=nil)
      # signal user error if file cannot be sourced
      unless path && path.file? && path.readable?
        raise "Unable to resolve #{path} #{ ("(%s, line %i)" % context) if context }"
      end
      
      # only expand each source file once
      return if source_files.include?(path)
      source_files << path
      
      # process file
      preprocess(path)
    end

    # return the require template for a fully-specified asset, converted to an absolute url
    def require(path, context=nil)
      # signal user error if file cannot be sourced
      unless path && path.file? && path.readable?
        raise "Unable to provide #{path} #{ ("(%s, line %i)" % context) if context }"
      end
      
      load_path = asset_paths.detect do |load_path|
        contains_path?(load_path, path)
      end
      
      template    = options[:require_template]
      path_prefix = options[:path_prefix]
      url         = path.relative_path_from(load_path)
      
      template % "#{path_prefix}/#{url}"
    end

    protected
    
    def preprocess(path)
      result   = ""
      line_num = 0
      path.each_line do |line|
        line_num += 1
        # //= require "foo"
        if    subpath = line[/^\s*\/\/=\s+require\s+\"(.*?)\"\s*$/, 1]
          result << require(path.dirname + (subpath + path.extname), [path, line_num])
        # //= require <foo>
        elsif library = line[/^\s*\/\/=\s+require\s+<(.*?)>\s*$/, 1]
          result << require(search_paths[library], [path, line_num])
        # //= provide "foo.css"
        elsif subpath = line[/^\s*\/\/=\s+provide\s+\"(.*?)\"\s*$/, 1]
          result << require(path.dirname + subpath, [path, line_num])
        # default: pass through
        else 
          result << line
        end
      end
      result
    end
      
    def calculate_load_paths(search_paths)
      # determine valid gem-based asset paths
      load_paths = []
      
      $LOAD_PATH.each do |path|
        search_paths.each do |suffix|
          load_paths |= Dir[File.join(path, suffix)].map { |f| Pathname.new(f).realpath }
        end
      end
      
      load_paths
    end
    
    private
    
    def contains_path?(parent, child)
      !child.relative_path_from(parent).to_s.include?('..')
    end  
  end
end