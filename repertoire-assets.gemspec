require File.expand_path("../lib/repertoire-assets/version", __FILE__)

Gem::Specification.new do |s|
  s.name        = "repertoire-assets"
  s.version     = Repertoire::Assets::VERSION
  s.authors     = ["Christopher York"]
  s.email       = "yorkc@mit.edu"
  s.date        = "2010-07-28"
  s.summary     = "Hyperstudio Asset framework"
  s.description = "Repertoire Assets javascript and css distribution framework"
  s.homepage    = "http://github.com/repertoire/repertoire-assets"
  
  s.files = [
    ".gitignore",
     "FAQ",
     "INSTALL",
     "LICENSE",
     "README",
     "Rakefile",
     "lib/repertoire-assets.rb",
     "lib/repertoire-assets/exceptions.rb",
     "lib/repertoire-assets/manifest.rb",
     "lib/repertoire-assets/processor.rb",
     "lib/repertoire-assets/provides.rb",
     "lib/repertoire-assets/railtie.rb",
     "lib/repertoire-assets/version.rb",
     "lib/repertoire-assets/tasks.rake",
     "repertoire-assets.gemspec",
     "vendor/yuicompressor-2.4.2.jar"
  ]
  s.extra_rdoc_files = [
       "LICENSE",
       "README",
       "TODO"
  ]
     
  s.post_install_message = %q{  ********************************************************************************
    One of your gems uses Repertoire asset support, which provides access to
    javascript, stylesheets and other assets distributed via Rubygems.

    You should turn on precaching and compression in your production environment,
    so gem assets are served by your web server. e.g. for Rails 3.0:

        <app>/config/environments/production.rb:

    *        config.repertoire_assets.compress = true

    See the repertoire-assets README for other frameworks or details.
  ********************************************************************************
}

  s.require_paths    = ["lib"]
  s.rubygems_version = '1.3.7'

  s.add_dependency('rack', '>= 1.0.1')
end