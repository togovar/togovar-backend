class Gene
  module Searchable
    extend ActiveSupport::Concern
    include ElasticsearchIndex::Base

    included do
      include Elasticsearch::Model

      index_name :gene

      settings = {
        index: {
          number_of_shards: ENV.fetch('TOGOVAR_INDEX_GENE_NUMBER_OF_SHARDS') { 1 },
          number_of_replicas: ENV.fetch('TOGOVAR_INDEX_GENE_NUMBER_OF_REPLICAS') { 0 }
        },
        analysis: {
          analyzer: {
            symbol_search_analyzer: {
              type: :custom,
              tokenizer: :whitespace,
              filter: :lowercase
            },
            symbol_suggest_analyzer: {
              type: :custom,
              tokenizer: :whitespace,
              filter: %i[lowercase edge_ngram_filter]
            },
            symbol_ngram_analyzer: {
              filter: %i[lowercase],
              tokenizer: :symbol_ngram_tokenizer
            }
          },
          tokenizer: {
            symbol_ngram_tokenizer: {
              type: :edge_ngram,
              min_gram: 3,
              max_gram: 10
            }
          },
          filter: {
            edge_ngram_filter: {
              type: :edge_ngram,
              min_gram: 3,
              max_gram: 20
            }
          },
          normalizer: {
            lowercase: {
              type: :custom,
              filter: :lowercase
            }
          }
        }
      }

      settings settings do
        mapping dynamic: :strict do
          indexes :hgnc_id, type: :integer
          indexes :symbol,
                  type: :keyword,
                  fields: {
                    search: {
                      type: :text,
                      analyzer: :symbol_search_analyzer
                    },
                    suggest: {
                      type: :text,
                      analyzer: :symbol_suggest_analyzer
                    },
                    lowercase: {
                      type: :keyword,
                      normalizer: :lowercase
                    },
                    ngram_search: {
                      type: :text,
                      analyzer: :symbol_ngram_analyzer
                    },
                  }
          indexes :approved, type: :boolean
          indexes :alias_of, type: :keyword
          indexes :name, type: :keyword
          indexes :location, type: :keyword
          indexes :family, type: :nested do
            indexes :id, type: :integer
            indexes :name, type: :keyword
          end
        end
      end
    end

    module ClassMethods
      def find(_id)
        raise NotImplementedError
      end

      # @param [String] keyword
      # @return [Elasticsearch::Model::Response] response
      def suggest(keyword)
        query = ::Elasticsearch::DSL::Search.search do
          query do
            bool do
              should do
                match 'symbol.lowercase': { query: keyword.downcase, boost: 3 }
              end
              should do
                match 'symbol.search': { query: keyword, boost: 2 }
              end
              should do
                match 'symbol.suggest': { query: keyword }
              end
            end
          end
        end

        __elasticsearch__.search(query)
      end

      # @return [Hash]
      def synonyms(hgnc_id)
        return unless hgnc_id

        query = Elasticsearch::DSL::Search.search do
          query do
            match hgnc_id: hgnc_id
          end
        end

        __elasticsearch__.search(query).results
                         .reject { |x| x.dig('_source', 'approved') }
                         .map { |x| x.dig('_source', 'symbol') }
                         .compact
      end

      # @param [String] keyword
      # @return [Elasticsearch::Model::HashWrapper, nil] response
      # {
      #   "hgnc_id"=>404,
      #   "symbol"=>"ALDH2",
      #   "approved"=>true,
      #   "name"=>"aldehyde dehydrogenase 2 family member",
      #   "location"=>"12q24.12",
      #   "family"=>[
      #     {
      #       "id"=>398,
      #       "name"=>"Aldehyde dehydrogenases"
      #     },
      #     {
      #       "id"=>1691,
      #       "name"=>"MicroRNA protein coding host genes"
      #     }
      #   ]
      # }
      def exact_match(keyword)
        query = ::Elasticsearch::DSL::Search.search do
          query do
            match 'symbol.lowercase': keyword.downcase
          end
        end

        res = __elasticsearch__.search(query).results

        return unless res.total.positive?

        res.map { |x| x[:_source] }.first
      end
    end
  end
end
