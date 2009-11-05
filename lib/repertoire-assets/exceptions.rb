module Repertoire
  module Assets
    class Error < ::StandardError;        end
    class ConfigurationError < Error;     end
    class UnknownAssetError < Error;      end
    class UnknownDirectiveError < Error;  end
  end
end
