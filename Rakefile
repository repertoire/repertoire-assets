begin
  require 'jeweler'
  Jeweler::Tasks.new do |s|
    s.name = "repertoire-assets"
    s.summary = "Repertoire Assets javascript and css distribution framework"
    s.description = "Repertoire Assets javascript and css distribution framework"
    s.email = "yorkc@mit.edu"
    s.homepage = "http://github.com/repertoire/repertoire-assets"
    s.authors = ["Christopher York"]
    s.add_dependency('rack', '>=1.0.1')
    s.post_install_message = <<-POST_INSTALL_MESSAGE
  #{'*'*80}
    One of your gems uses Repertoire asset support, which provides access to
    javascript, stylesheets and or others assets distributed via Rubygems.

    Rack middleware serves assets in front of your Merb or Rails application,
    and includes <script> and <link> tags in the header automatically.

    (1) Make sure your application loads the middleware. e.g. for Merb:

        <app>/config/rack.rb (Mongrel)
        <app>/config.ru      (Passenger) 

        require 'repertoire-assets'
        use Repertoire::Assets::Processor, Merb::Config, Merb.logger
        run Merb::Rack::Application.new

    (2) Turn on precaching and compression in your production environment,
        so gem assets are served by your web server. e.g. for Merb:

        <app>/config/environments/production.rb:

        c[:compress_assets] = true

    See the repertoire-assets README for details.
  #{'*'*80}
  POST_INSTALL_MESSAGE
  end
  Jeweler::RubyforgeTasks.new do |rubyforge|
    rubyforge.doc_task = "yardoc"
  end
 
  Jeweler::GemcutterTasks.new
rescue LoadError
  puts "Jeweler not available. Install it with: sudo gem install jeweler"
end


begin
  require 'yard'
  YARD::Rake::YardocTask.new(:yardoc)
rescue LoadError
  task :yardoc do
    abort "YARD is not available. In order to run yard, you must: sudo gem install yard"
  end
end