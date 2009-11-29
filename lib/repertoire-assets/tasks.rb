require 'rake/tasklib'

module Repertoire
  module Assets
    class Tasks < ::Rake::TaskLib

      DEFAULT_OPTIONS = {
        :cache_root      => './build',
        :precache_assets => true,
        :compress_assets => true
      }
      
      def initialize(config)
        config    = DEFAULT_OPTIONS.merge(config)
        logger    = Logger.new(STDERR)
        build_dir = config[:cache_root]
        
        namespace :assets do
          # directory for build products
          directory build_dir
          
          desc "Clean products from assets:build"
          task :clean do
            rm_rf build_dir
          end
        
          desc "Package javascript, css, and assets for release outside rubygems"
          task :build => [:clean, :gemspec, build_dir] do
            # Find and load all gemspecs in package root
            gemspecs = Dir['*.gemspec'].map do |file|
              eval( File.read(file) )
            end
          
            # Require all rubygem dependencies
            gemspecs.each do |spec|
              # treat gem we're building as an asset source
              spec.require_paths.each do |path|
                path = Pathname.new(path).realpath
                $LOAD_PATH.unshift(path)
              end

              # load all of gem's dependencies            
              spec.dependencies.each do |library|
                logger.info "Loading #{library}"
                # TODO.  are there ever more than one version requirement string?
                gem library.name, library.requirements_list.first
              end
            end
          
            # Generate digest files and assets
            config[:digest_basename] ||= gemspecs.first.name
            Processor.new(nil, config, logger)
          end
        end
      end
    end
  end
end