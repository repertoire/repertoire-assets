# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{repertoire-assets}
  s.version = "0.1.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Your Name"]
  s.date = %q{2009-11-01}
  s.description = %q{Merb plugin that provides ...}
  s.email = %q{Your Email}
  s.extra_rdoc_files = ["README", "LICENSE", "TODO"]
  s.files = ["LICENSE", "README", "Rakefile", "TODO", "lib/repertoire-assets", "lib/repertoire-assets/manifest.rb", "lib/repertoire-assets/merb_helpers.rb", "lib/repertoire-assets/merb_middleware.rb", "lib/repertoire-assets/processor.rb", "lib/repertoire-assets/provides.rb", "lib/repertoire-assets.rb", "templates/manifest.js", "vendor/yuicompressor-2.4.2.jar"]
  s.homepage = %q{http://merbivore.com/}
  s.post_install_message = %q{**************************************************

  One of your gems uses Repertoire asset support, which runs as rack middleware in front of a
  Merb or Rails application.
  
  In order to run, make sure your config.ru or config/init.ru files load the middleware, e.g.:

  ...
  use Repertoire::Assets::Middleware::Merb
  ...
    
  Immediately before the final run statement.  Also, you may want to turn on asset bundling and
  compression in your production environment (config/environments/production.rb):
  
  ...  
  c[:precache] = :compress
  ...  
  
  See the package documentation for other application-level configuration options.
  
**************************************************
}
  s.require_paths = ["lib"]
  s.rubyforge_project = %q{merb}
  s.rubygems_version = %q{1.3.5}
  s.summary = %q{Merb plugin that provides ...}

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 3

    if Gem::Version.new(Gem::RubyGemsVersion) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<rack>, [">= 0"])
    else
      s.add_dependency(%q<rack>, [">= 0"])
    end
  else
    s.add_dependency(%q<rack>, [">= 0"])
  end
end
