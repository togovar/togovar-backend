require 'oj'
require 'multi_json'

Oj.default_options = {
  mode: :compat
}

MultiJson.use(:oj)

if Rails.application.config.respond_to?(:elasticsearch) && (config = Rails.application.config.elasticsearch).present?
  if config[:log]
    logger = Logger.new(STDERR)
    logger.progname = 'elasticsearch'
    logger.formatter = ::Logger::Formatter.new

    class << logger
      def add(severity, message = nil, progname = nil)
        return true if (message && message.start_with?('<')) || (progname && progname.start_with?('<'))

        super
      end
    end

    config.merge!(logger: logger)
  end

  Elasticsearch::Model.client = Elasticsearch::Client.new(config)
end
