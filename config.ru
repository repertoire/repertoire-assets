# infinity.ru

require 'pathname'
require 'lib/repertoire-gem-assets'
require 'merb-core'

begin
  require File.join(File.dirname(__FILE__), "gems/environment")
rescue LoadError
  begin 
    require 'minigems'
  rescue LoadError 
    require 'rubygems'
  end
end


infinity = Proc.new {|env| [200, {"Content-Type" => "text/html"}, env.inspect]}

use Merb::Rack::PathPrefix, '/facets'

use Repertoire::RackAssets

run infinity
