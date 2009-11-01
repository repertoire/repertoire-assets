module Repertoire
  module Assets
    class MerbMiddleware
      
      def hmm
        processor = Repertoire::Assets::Processor.new(Merb::Config, Merb.logger)
        use Repertoire::Assets::Manifest, processor, Merb::Config, Merb.logger
        use Repertoire::Assets::Provides, processor, Merb::Config, Merb.logger
      end
      
    end
  end
end