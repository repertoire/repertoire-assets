require 'logger'

module Repertoire
  module Assets
    class Processor

      attr_accessor :manifest, :provided

      DEFAULT_OPTIONS = {
        :precache_assets     => nil,
        :compress_assets     => nil,
        :disable_rack_assets => nil,

        :path_prefix     => '',                      # prefix to add before all urls
        :js_source_files =>                          # app javascript files to jumpstart dependency processing
                            [ 'public/javascripts/application.js', 'public/javascripts/*.js' ],
        
        :gem_asset_roots => [ '../public' ],         # location under $LOAD_PATHs to use as root for asset uris
        :gem_libraries   =>                          # location under $LOAD_PATHs to search for javascript libraries
                            [ '../public/javascripts/*.js' ],

        :cache_root      => 'public',                # app directory to put cache files & digests in, should be webserver visible
        :digest_basename => 'digest',                # file basename for css & js digests
        :gem_excludes    => [ ]                      # patterns under $LOAD_PATHs to exclude from the manifest
      }


      # Initialize the asset dependency system, configure the rack middleware,
      # and precache assets (if requested).
      #
      # === Parameters
      # :delegate:: 
      #    The rack app to serve assets for
      # :settings:: 
      #    Hash of configuration options (below)
      # :logger:: 
      #    Framework's logger - defaults to STDERR
      #
      # === Exceptions
      #   ConfigurationError
      #
      # Common settings and defaults
      #
      #   :precache_assets [false]                   # copy and bundle assets into host application?
      #   :compress_assets [false]                   # compress bundled javascript & stylesheets? (implies :precache)
      #   :disable_rack_assets [false]               # don't interpolate <script> and <link> tags (implies :precache)
      #   :path_prefix     ['']                      # prefix for all generated urls
      #  
      # For other very rarely used configuration options, see the source.
      #
      # ---
      def initialize(delegate, settings={}, logger=nil)
        @options = DEFAULT_OPTIONS.dup.merge(settings)
        @logger  = logger || Logger.new(STDERR)        
        Processor.verify_options(@options)
        
        # configure rack middleware
        @app        = delegate
        @manifester = Manifest.new(@app, self, @options, @logger)
        @provider   = Provides.new(@manifester, self, @options, @logger)

        # build manifest from required javascripts
        reset!

        # if requested, cache assets in app's public directory at startup
        @provider.precache! && @manifester.precache! if @options[:precache_assets]
      end


      # The core rack call to process an http request. Calls the appropriate middleware
      # to provide assets or interpolate the asset manifest.
      #
      # If asset precaching is turned off, the dependent files are checked to make 
      # sure the asset manifest is still valid before the request is processed.
      #
      # ---
      def call(env)
        delegate = case
          when @options[:disable_rack_assets]  then @app              # ignore all asset middleware
          when @options[:precache_assets] then @manifester       # use manifest middleware only
          else                                 
            reset! if stale?                                     
            @provider                                            # use provider + manifest middleware
        end
        
        delegate.call(env)
      end


      # Rebuild the manifest and provides lists from the javascript source files.
      #
      # ---
      def reset!
        @source_files   = nil
        @libraries      = nil
        @excludes       = nil
        @asset_roots    = nil
        @manifest       = nil
        @manifest_stamp = nil
        @provided       = nil
        
        source_files.each do |path|
          requires(path)
        end
        
        @manifest_timestamp = mtime
        
        @logger.info "Assets processed: %i source files, %i libraries available, %i assets provided, %i required files in manifest" % 
          [ source_files.size, libraries.size, @provided.size, @manifest.size ]
      end


      # Compute the initial javascript source files to scan for dependencies.
      # By default:
      #
      #   <app_root>/public/javascripts/*.js
      #
      # If there is a file 'application.js', it will be processed before all 
      # others.  In a complex application, divide your javascript into files
      # in a directory below and 'require' them in application.js.
      #
      # ==== Returns
      # :Array[Pathname]:: 
      #    The pathnames, in absolute format
      #
      # ---
      def source_files
        @source_files ||= Processor.expand_paths(['.'], @options[:js_source_files])
      end


      # Compute the load path for all potential assets that could be provided by
      # a javascript library.  By default:
      #
      #   <gem_root>/public/
      #
      # For security, the middleware will not serve a file until it or an enclosing
      # directory are explicitly required or provided by a javascript library file.
      #
      # ==== Returns
      # Array[Pathname]:: The pathnames, in absolute format
      #
      # ---
      def asset_roots
        unless @asset_roots
          @asset_roots = Processor.expand_paths($LOAD_PATH, @options[:gem_asset_roots])
          @asset_roots << Processor.realpath(@options[:cache_root])
        end
        
        @asset_roots
      end


      # Compute the list of all available javascript libraries and their paths.
      # By default, javascripts in the following paths will be found:
      #
      #   <gem_root>/public/javascripts/*.js
      #
      # ==== Returns
      # :Hash<String, Pathname>:: 
      #    The library names and their absolute paths.
      #
      # ---
      def libraries
        unless @libraries
          @libraries = {}
          paths = Processor.expand_paths($LOAD_PATH, @options[:gem_libraries])
          paths.each do |path|
            lib = Processor.library_name(path)
            if @libraries[lib]
              @logger.warn "Multiple libraries for <#{lib}>, using #{ Processor.pretty_path @libraries[lib] } (other is #{ Processor.pretty_path path })" 
            end
            @libraries[lib] ||= path
          end
        end
      
        @libraries
      end
      
      
      # Compute the basepaths for all excluded javascript libraries.
      #
      # ==== Returns
      # :Array<String>:: 
      #    The list of base paths
      #
      # ---
      def excludes
        unless @excludes
          @excludes = []
          @options[:gem_excludes].map do |libname|
            libpath = libraries[libname]
            @excludes << libpath.dirname + libname if libpath
          end
        end
         
        @excludes
      end

      
      # Determine if manifest or provided assets lists need to be regenerated
      # because a required file has changed.
      #
      # ==== Parameters
      # :product_times:: An optional list of times from product files that
      # depend on the manifest.
      #
      # ==== Returns
      #   <boolean>
      #
      def stale?(*product_times)
        product_times << @manifest_timestamp
        source_time = mtime
        current     = @manifest && 
                      @provided && 
                      product_times.all? do |time|
                        time >= source_time
                      end
        !current
      end


      # Calculate the most recent modification date among all javascript files
      # available to build the manifest.
      #
      # ==== Returns
      #
      # <Time>:: The most recent time.
      #
      # ---
      def mtime
        paths  = @source_files | @provided.values
        mtimes = paths.map do |f| 
          File.exists?(f) ? File.mtime(f) : Time.now
        end

        mtimes.max
      end
      

      protected

      # Add the required javascript file - and all that it requires in turn -
      # to the manifest.  Javascripts that have already been sourced are
      # omitted.
      #
      # The javascript file will be provided for client http access at a uri
      # relative to the gem asset root.  e.g.
      #
      # <gem>/public/javascripts/my_module/circle.js
      #
      # will apppear at a comparable uri beneath the application root:
      #
      # http://javascripts/my_module/circle.js
      #
      # ==== Parameters
      # :path:: 
      #    The path of the javascript file
      # :indent:: 
      #    The logging indent level (for pretty-printing)
      #
      # ---
      def requires(path, level=0)
        @manifest ||= []
        @provided ||= {}
        uri         = uri(path)
      
        # only expand each source file once
        return if @manifest.include?(uri)
        
        # handle excluded libraries
        if excludes.any? { |excluded| Processor.parent_path?(excluded, path) }
          @logger.debug "Excluding #{'  '*level + uri} (#{Processor.pretty_path(path)})"
          return
        end
        
        @logger.debug "Requiring #{'  '*level + uri} (#{Processor.pretty_path(path)})"
      
        # preprocess directives in the file recursively
        preprocess(path, level+1)
        
        # add file after those it requires and register it as provided for http access
        @manifest << uri
        @provided[uri] = path
      end
      
      
      # Provide a given asset for client http access.  If a directory is passed
      # in, all files beneath it are provided.
      #
      # The assets will be provided for client http access at uris
      # relative to the gem asset root.  e.g.
      #
      # <gem>/public/images/my_module/circle.png
      #
      # will apppear at a comparable uri beneath the application root:
      #
      # http://images/my_module/circle.png
      # 
      # ==== Parameters
      # :path:: 
      #    The path of the asset or directory to provide
      # :indent:: 
      #    The logging indent level (for pretty-printing)
      #
      # ---       
      def provides(path, level=0)
        @provided ||= {}
        uri         = uri(path)
        
        @logger.debug "Providing #{'  '*level + uri} (#{Processor.pretty_path(path)})"
        
        path.find do |sub|
          @provided[ uri(sub) ] = sub if sub.file?
        end
      end
      
      
      protected

    
      # Recursively preprocess require and provide directives in a javascript file.
      #
      # ==== Parameters
      # :path<Pathname>:: the path of the javascript file
      # :level<Integer>:: the recursion level (for pretty-printing & errors)
      #
      # ==== Raises
      # :UnknownAssetError::
      #   No file could be found for the given asset name
      # :UnknownDirectiveError::
      #   An unknown processing directive was given
      #
      # ---
      def preprocess(path, level=0)
        line_num = 1
        path.each_line do |line|
          begin
            # process any directives on line
            directive(path.dirname, line, level)
          rescue Error => e
            @logger.error "Could not process '#{line.chomp}' (%s, line %i)" % [path, line_num]
            error_status
            raise e.message
          end
          line_num += 1
        end
      end
      
      # Preprocess any directive on a single line.  The file spec is progressively 
      # expanded, as follows.
      #
      #   (1) <library> and <library/sublibrary> are dereferenced
      #   (2) "relative/file" is expanded based on the current working directory
      #   (3) globs are expanded (see Ruby Dir[])
      #   (4) the default extension (.js) is checked
      #   (5) finally, 'requires' or 'provides' are called on any resulting files
      #
      # ==== Parameters
      # :cwd::
      #   The current working directory (for relative paths)
      # :line::
      #   The line to process
      # :level::
      #   The recursion level (for pretty-printing)
      #
      # ==== Raises
      # :UnknownAssetError::
      #   The path does not refer to any existing file
      # :UnknownDirectiveError::
      #   The line specified an unknown preprocessing directive
      #
      # ---
      def directive(cwd, line, level=0)
        # extract the preprocessing directive
        return unless line[ %r{^\s*//=\s*(\w+)\s+(".+"|<.+>)\s*$} ]
        directive, pathspec = $1, $2
      
        # progressively expand path specification
        pathlist = pathspec

        # expand library and sublibrary references
        pathlist.gsub!( %r{^<([^/>]*)/?(.*)>} ) do
          libname, sublib = $1, $2
          # determine library path
          unless libpath = libraries[libname]
            raise UnknownAssetError, libname
          end
          # distinguish library and sublibraries
          if sublib.empty?
            libpath.to_s
          else
            libpath.dirname + libname + sublib
          end
        end

        # expand relative references
        pathlist.gsub!( %r{"(.*)"} ) do
          subpath = $1
          cwd + subpath
        end
      
        # expand globs & default extension, match existing files
        pathlist = Dir[ pathlist, pathlist + '.js' ]        
        pathlist.reject! { |p| File.directory?(p) }
      
        # handle missing asset
        raise UnknownAssetError, pathspec if pathlist.empty?
      
        # perform directive over matches
        pathlist.each do |p|
          p = Pathname.new(p)
          case directive
          when 'require' then requires(p, level)
          when 'provide' then provides(p, level)
          else 
            raise UnknownDirectiveError, directive
          end
        end
      end
      
      # Locate the enclosing gem asset root and construct a relative uri to path
      #
      # ==== Parameters
      # :path:: 
      #    The path of the asset
      #
      # --- 
      def uri(path)
        return nil unless path
        root = asset_roots.detect { |root| Processor.parent_path?(root, path) }
        '/' + path.relative_path_from(root).to_s
      end
      
    
      # Check path references a valid set of files and give sensible error 
      # messages to locate the problem if not.  If successful, each path is
      # yielded in turn.
      #
      # ==== Parameters
      # :path::
      #   The pathname to check
      # :identifier::
      #   The reference the user supplied to identify the file
      # :source_file::
      #   The filename the reference occurred in
      # :line_num::
      #   The line number of the occurrence
      # :&block::
      #   Block to run on all successful matches
      #
      # ==== Raises
      # UnknownAssetError::
      #   The path does not refer to an existing file
      #
      # ---
      def path_lint(path, identifier, source_file, line_num, &block)
        matches = if !path
          []
        elsif path.readable?
          [ path ]
        else
          Dir[ path ]
        end
        
        if matches.size > 0
          matches.each { |p| yield p }
        else
          @logger.error "Could not resolve #{identifier} #{ '(%s, line %i)' % [source_file, line_num]  if source_file && line_num }"
          error_status
          raise UnknownAssetError
        end
      end
      
      # Log the processor's status to error
      #
      # ---
      def error_status
        lib_patterns  = @options[:gem_libraries].map { |p| "$LOAD_PATH/#{p}" }
        root_patterns = @options[:gem_asset_roots].map { |p| "$LOAD_PATH/#{p}" }
        
        @logger.error "Known libraries [ %s ]: %s" % 
                      [ lib_patterns.join(", "), libraries.keys.sort.join(", ") ]
        @logger.error "Asset roots     [ %s ]:\n%s" % 
                      [ root_patterns.join(", "), asset_roots.sort.join("\n") ]
      end
      
      
      class << self
      
        # Sanity check for configurations
        #
        # ==== Parameters
        # :options<Hash>:: the configuration options
        #
        # ---
        def verify_options(options)
          # detect cases where rubygems or bundler are misconfigured
          raise Error, "No load paths are available" unless $LOAD_PATH
        
          # precaching must be turned on in order to compress
          if options[:compress_assets]
            raise Error, "Must select asset precaching for compression" if options[:precache_assets] == false
            options[:precache_assets] = true
          end

          # the javascript source files must be located in the public app root to have valid uris        
          #options[:js_source_files].each do |f|
          #  unless parent_path?(options[:cache_root], f)
          #    raise Error, "Invalid configuration: #{f} must be under app asset root"
          #  end
          #end
        
          # the javascript libraries in gems must be located underneath gem asset roots to have valid uris
          options[:gem_libraries].each do |f|
            unless options[:gem_asset_roots].any? { |r| parent_path?(r, f) }
              raise Error, "Invalid configuration: #{f} is not under a valid gem asset root"
            end
          end
        end


        # Expand a list of existing files matching a globs from a set of root paths
        #
        # ==== Parameters
        # :base_paths::
        #   The list of root paths
        # :patterns::
        #   A list of unix glob-style patterns to match
        #
        # ==== Returns
        #   A list of absolute paths to existing files
        #
        # ---
        def expand_paths(base_paths, patterns)
          paths = []

          base_paths.each do |base|
            patterns.each do |pattern|
              paths |= Dir[File.join(base, pattern)].map { |f| realpath(f) }
            end
          end

          paths.compact
        end
      
        # Extract a javascript library name from its complete path.  As for ruby 
        # require this is the file's basename irrespective of directory and with 
        # the extension left off.
        #
        # ==== Returns
        #   A string identifying the library name
        #
        # ---
        def library_name(path)
          base = path.basename.to_s
          base.chomp(path.extname)
        end
        

        # Attempt to give a short name to identify the gem the provided file
        # is from.  If unsuccessful, return the full path again.
        #
        # ---
        def pretty_path(path)
          # default: standard rubygems repository format
          pretty = path.to_s[/.*\/(gems|dirs)\/([^\/]+)\//, 2]
          pretty || path
        end
        
      
        # Utility to check if parent path contains child path
        #
        # ---
        def parent_path?(parent, child)
          child.to_s.index(parent.to_s) == 0
        end
      

        # Utility for resolving full file paths
        #
        # ---
        def realpath(f)
          Pathname.new(f).realpath
        end
      end
    end
  end
end