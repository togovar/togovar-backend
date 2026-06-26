class Disease
  module Searchable
    extend ActiveSupport::Concern
    include ElasticsearchIndex::Base

    included do
      include Elasticsearch::Model

      index_name :disease
    end

    module ClassMethods
      # @param [Integer] id tgv ID
      def find(id)
        query = Elasticsearch::DSL::Search.search do
          query do
            term id:
          end
        end

        super(query)
      end

      # @param [String] keyword
      # @return [Elasticsearch::Model::Response] response
      def suggest(keyword)
        query = ::Elasticsearch::DSL::Search.search do
          query do
            bool do
              should do
                match 'name.search': { query: keyword, boost: 2 }
              end
              should do
                match 'name.suggest': keyword
              end
            end
          end
        end

        __elasticsearch__.search(query)
      end

      # @param [String] keyword
      # @return [Hash]
      def exact_match(keyword)
        query = ::Elasticsearch::DSL::Search.search do
          query do
            match 'name.lowercase': keyword.downcase
          end
        end

        (r = __elasticsearch__.search(query).results.first) ? r['_source'].slice('id', 'name') : {}
      end

      # @param [String] keyword
      # @return [Hash]
      def condition_search(keyword)
        query = ::Elasticsearch::DSL::Search.search do
          query do
            match 'name.search': keyword.downcase
          end
        end

        __elasticsearch__.search(query).results.map { |x| x['_source'].slice('id', 'name') }
      end
    end
  end
end
