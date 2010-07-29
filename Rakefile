require __FILE__ + '/../lib/repertoire-assets'

gemspec = eval(File.read("repertoire-assets.gemspec"))

task :build => "#{gemspec.full_name}.gem"

file "#{gemspec.full_name}.gem" => gemspec.files + ["repertoire-assets.gemspec"] do
  system "gem build repertoire-assets.gemspec"
  system "gem install repertoire-assets-#{Repertoire::Assets::VERSION}.gem"
end
