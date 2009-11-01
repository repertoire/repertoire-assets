module Repertoire
  module Assets
    class MerbHelpers
      # generate html reference to the manifest
      def manifest
        "<script language='javascript' src='#{Merb::Config[:path_prefix]}/manifest.js'></script>"
      end
    end
  end
end