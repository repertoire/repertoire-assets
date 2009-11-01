module Repertoire
  module Assets
    class Processor

      DEFAULT_OPTIONS = {
        :load_path => $LOAD_PATH,
        :precache  => false,                   # :bundle, :compress
        
        :app_asset_root => 'public',
        :source_files   => [ 'public/javascripts/application.js', 'public/javascripts/*.js' ],
        
        :gem_asset_roots => [ '../public' ],
        :gem_libraries   => [ '../public/javascripts/*.js' ]
      }
      
      DEFAULT_EXT = '.js'

      attr_reader :options, :logger

      def initialize(settings={}, logger=nil)
        @options = DEFAULT_OPTIONS.dup.merge(settings)
        @logger  = logger || Logger.new(STDERR)
        
        verify_options
        reset!
      end

      def reset!
        @source_files   = nil
        @libraries      = nil
        @asset_roots    = nil
        @manifest       = nil
        @manifest_stamp = nil
        @provided       = nil
        
        source_files.each do |path|
          requires(path)
        end
        
        @manifest_timestamp = mtime
        
        @logger.info "Assets processed: %i source files, %i libraries available, %i assets provided, %i files in manifest" % 
          [ source_files.size, libraries.size, @provided.size, @manifest.size ]
      end

      def source_files
        @source_files ||= expand_paths(['.'], options[:source_files])
      end

      def asset_roots
        unless @asset_roots
          @asset_roots = expand_paths(@options[:load_path], options[:gem_asset_roots])
          @asset_roots << realpath(options[:app_asset_root])
        end
        
        @asset_roots
      end

      def libraries
        unless @libraries
          @libraries = {}
          paths = expand_paths(@options[:load_path], options[:gem_libraries])
          paths.each do |path|
            lib = library_name(path)
            @logger.warn "Multiple libraries for <#{lib}>, using #{@load_paths[lib]}" if @libraries[lib]
            @libraries[lib] ||= path
          end
        end
      
        @libraries
      end
      
      # return an up-to-date manifest of required uris, in order
      def manifest
        reset! if stale?
        @manifest
      end
      
      # return the map of provided uris and pathnames
      def provided
        reset! if stale?
        @provided
      end
      
      # determine if manifest and provided need to be regenerated
      def stale?
        current = @source_files && 
                  @manifest && 
                  @provided && 
                  @manifest_timestamp &&
                  @manifest_timestamp >= mtime                  
        !current
      end

      # return most recent modification date for all files
      def mtime
        paths  = @source_files | @provided.values
        mtimes = paths.map { |f| File.mtime(f) }
      
        mtimes.max
      end
      
      protected

      # add the required file and all it requires to the manifest, in order
      def requires(path)
        @manifest ||= []
        @provided ||= {}
        uri         = uri(path)
        
        @logger.debug "Requiring #{path} -> #{uri}"
      
        # only expand each source file once
        return if @manifest.include?(uri)
      
        # preprocess directives in the file recursively
        preprocess(path)
        
        # add file after those it requires and register it as provided for http access
        @manifest << uri
        @provided[uri] = path
      end
      
      # provide resource and any it contains to client http access
      def provides(path, context=nil)
        @provided ||= {}
        uri         = uri(path)
        
        @logger.debug "Providing #{path} -> #{uri}"
        
        # provide all files indicated by path
        uri = Pathname.new(uri)
        path.find do |sub|
          @provided[ uri(sub) ] = sub
        end
      end
    
      # recursively preprocess directives in file
      def preprocess(path)
        line_num = 1
        path.each_line do |line|
          # //= require <foo>
          if lib = line[/^\s*\/\/=\s+require\s+<(.*?)>\s*$/, 1]
            path_lint(libraries[lib], lib, path, line_num) do |p| 
              requires(p)
            end
          # //= require "foo" or //= require "foo.css"
          elsif subpath = line[/^\s*\/\/=\s+require\s+\"(.*?)\"\s*$/, 1]
            subpath += DEFAULT_EXT unless subpath[/\.\w+$/]
            path_lint(path.dirname + subpath, subpath, path, line_num) do |p|
              requires(p)
            end
          # //= provide "../assets"
          elsif subpath = line[/^\s*\/\/=\s+provide\s+\"(.*?)\"\s*$/, 1]
            path_lint(path.dirname + subpath, subpath, path, line_num) do |p|
              provides(p)
            end
          end
          line_num += 1
        end
      end
      
      # return a list of file paths matching a globs from a set of root paths
      def expand_paths(base_paths, patterns)
        paths = []
      
        base_paths.each do |base|
          patterns.each do |pattern|
            paths |= Dir[File.join(base, pattern)].map { |f| realpath(f) }
          end
        end
      
        paths.compact
      end
    
      private
      
      # sanity check for options
      def verify_options
        raise "No load paths are available" unless @options[:load_path]
        
        @options[:source_files].each do |f|
          unless parent_path?(@options[:app_asset_root], f)
            raise "Invalid configuration: #{f} must be under app asset root"
          end
        end
        
        @options[:gem_libraries].each do |f|
          unless @options[:gem_asset_roots].any? { |r| parent_path?(r, f) }
            raise "Invalid configuration: #{f} is not under a valid gem asset root"
          end
        end
      end
      
      def path_lint(path, reference, source_file, line_num)
        if path && path.readable?
          yield path
        else
          raise "Could not resolve '#{reference}' #{ ("(%s, line %i)" % [source_file, line_num]) if source_file && line_num }"
        end
      end
      
      # extract library name from a complete path
      def library_name(path)
        base = path.basename.to_s
        base.chomp(path.extname)
      end
      
      # locate the enclosing gem asset root and construct a uri to path
      def uri(path)
        return nil unless path
        root = asset_roots.detect { |root| parent_path?(root, path) }
        '/' + path.relative_path_from(root).to_s
      end
      
      # check if parent path contains child path
      def parent_path?(parent, child)
        child.to_s.index(parent.to_s) == 0
      end
      
      # give absolute path
      def realpath(f)
        Pathname.new(f).realpath
      end
    end
  end
end