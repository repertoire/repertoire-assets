require 'pathname'

namespace :assets do
  
  # Load module and application configuration
  config = Repertoire::Assets::Processor::DEFAULT_OPTIONS.dup
  config.merge!(Rails.application.config.repertoire_assets)  if defined?(Rails)
  
  # directory for build products
  directory config[:cache_root]
  
  desc "Clean products from assets:build"
  task :clean do
    dir = Pathname(config[:cache_root]).expand_path
    files = Pathname.glob(dir + "#{config[:digest_basename]}.*")
    rm files unless files.empty?
  end
  
  desc "List summary of javascript, css, and other assets"
  task :list do
    Repertoire::Assets::Processor.new(nil, config, Rails.logger)
  end

  desc "Package all assets for release [ 'config.repertoire_assets.compress = true' ]"
  task :build => [:clean, config[:cache_root]] do
    config[:compress] = true
    Repertoire::Assets::Processor.new(nil, config, Rails.logger)
  end
end