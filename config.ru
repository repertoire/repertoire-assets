# infinity.ru

require "gems/environment"

require 'pathname'
require 'merb-core'

infinity = lambda {|env| [200, {"Content-Type" => "text/html"}, env.inspect]}

use Merb::Rack::PathPrefix, '/facets'

require 'lib/repertoire-assets'

options = { :precache => :compress }
processor = Repertoire::Assets::Processor.new options
use Repertoire::Assets::Manifest, processor
use Repertoire::Assets::Provides, processor

run infinity
