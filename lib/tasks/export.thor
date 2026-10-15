require_relative '../../config/application'
require 'thor'
require 'zlib'

Rails.application.initialize! unless Rails.application.initialized?

module Tasks
  class Export < Thor
    namespace :export

    desc 'variant', 'Export variant data as tabix index JSONL'
    option :output_dir, type: :string, default: 'variant.jsonl.gz'

    def variant(*chromosomes)
      disable_logging

      chromosomes = ('1'..'22').to_a.concat(%w[X Y M MT]) if chromosomes.empty?

      chromosomes.each do |chr|
        if ::Variant.count(body: { query: { match: { chromosome: chr } } }).zero?
          warn "No variants found for chromosome #{chr}"
          next
        end

        env = Rack::MockRequest.env_for(
          "/variants/export.json?chromosome=#{chr}",
          method: 'GET',
          'HTTP_HOST' => 'localhost'
        )

        env['action_dispatch.request.path_parameters'] = {
          controller: 'variants',
          action: 'export'
        }

        status, _headers, body = API::SearchController.action(:export).call(env)

        begin
          output = File.join(options[:output_dir], "chr#{chr}_variant.jsonl.tsv.gz")
          tmp = "#{output}.part"

          raise "HTTP Error: #{status}" unless status.between?(200, 299)

          Zlib::GzipWriter.open(tmp, Zlib::BEST_COMPRESSION) do |gzip|
            body.each do |chunk|
              gzip.write(chunk)
            end
          end

          File.rename(tmp, output)
        ensure
          body.close if body.respond_to?(:close)
          File.delete(tmp) if File.exist?(tmp)
        end
      end
    end

    private

    def disable_logging
      return unless defined?(Rails) &&
        Rails.configuration.respond_to?(:elasticsearch) &&
        (config = Rails.configuration.elasticsearch).present?

      ::Elasticsearch::Model.client = ::Elasticsearch::Client.new(config.merge(log: false, logger: nil))
    end
  end
end
