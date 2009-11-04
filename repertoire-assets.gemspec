# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{repertoire-assets}
  s.version = "0.1.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Your Name"]
  s.date = %q{2009-11-03}
  s.description = %q{Merb plugin that provides ...}
  s.email = %q{Your Email}
  s.extra_rdoc_files = ["README", "LICENSE", "TODO"]
  s.files = ["LICENSE", "README", "Rakefile", "TODO", "lib/repertoire-assets", "lib/repertoire-assets/exceptions.rb", "lib/repertoire-assets/manifest.rb", "lib/repertoire-assets/processor.rb", "lib/repertoire-assets/provides.rb", "lib/repertoire-assets.rb", "vendor/yuicompressor-2.4.2.jar"]
  s.homepage = %q{http://merbivore.com/}
  s.post_install_message = %q{********************************************************************************
  One of your gems uses Repertoire asset support, which provides access to
  javascript, stylesheets and or others assets distributed via Rubygems.
  
  Rack middleware serves assets in front of your Merb or Rails application,
  and includes <script> and <link> tags in the header automatically.
  
  (1) Make sure your application loads the middleware. e.g. for Merb:

      <app>/config/init.ru (Mongrel)
      <app>/config.ru      (Passenger) 
    
      require 'repertoire-assets'
      use Repertoire::Assets::Processor, Merb::Config, Merb.logger
      run Merb::Rack::Application.new

  (2) Turn on precaching and compression in your production environment
      so gem assets are served by your web server. e.g. for Merb:
    
      <app>/config/environments/production.rb:
    
      c[:compress_assets] = true
  
  See the repertoire-assets README for details.
********************************************************************************
}
  s.require_paths = ["lib"]
  s.rubyforge_project = %q{merb}
  s.rubygems_version = %q{1.3.5}
  s.summary = %q{Merb plugin that provides ...}

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 3

    if Gem::Version.new(Gem::RubyGemsVersion) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<rack>, ["~> 1.0.1"])
      s.add_runtime_dependency(%q<nokogiri>, ["~> 1.4.0"])
    else
      s.add_dependency(%q<rack>, ["~> 1.0.1"])
      s.add_dependency(%q<nokogiri>, ["~> 1.4.0"])
    end
  else
    s.add_dependency(%q<rack>, ["~> 1.0.1"])
    s.add_dependency(%q<nokogiri>, ["~> 1.4.0"])
  end
end
