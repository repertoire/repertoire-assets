dir = Pathname(__FILE__).dirname.expand_path + 'repertoire-gem-assets'

require dir + 'asset_resolver'
require dir + 'rack_assets'

# make sure we're running inside Merb
if defined?(Merb::Plugins)

  # Merb gives you a Merb::Plugins.config hash...feel free to put your stuff in your piece of it
  Merb::Plugins.config[:repertoire_gem_assets] = {
    :chickens => false
  }
  
  Merb::BootLoader.before_app_loads do
    # require code that must be loaded before the application
  end
  
  Merb::BootLoader.after_app_loads do
    # code that can be required after the application loads
  end
  
  Merb::Plugins.add_rakefiles "repertoire-gem-assets/merbtasks"
end