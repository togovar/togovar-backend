module ElasticsearchIndex
  module Base
    extend ActiveSupport::Concern

    module ClassMethods
      def find(query)
        search(query).first&.[]('_source')&.with_indifferent_access
      end

      # @option arguments [List] :body A query to restrict the results specified with the Query DSL
      # @return [Integer] the number of the total records
      def count(arguments = {})
        arguments.merge!(index: index_name)

        client.count(arguments)&.[]('count')
      end

      def search(query_or_payload, options={})
        __elasticsearch__.search(query_or_payload, **options)
      end

      # @return [Elasticsearch::Transport::Client] elasticsearch client
      def client
        __elasticsearch__.client
      end
    end
  end
end
