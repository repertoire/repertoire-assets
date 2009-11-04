module Repertoire
  module Assets
    class Error < ::StandardError;        end
    class ConfigurationError < Error;     end
    class UnknownAssetError < Error;      end
  end
end
