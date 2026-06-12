class Gene
  module Searchable
    extend ActiveSupport::Concern
    include ElasticsearchIndex::Base

    included do
      include Elasticsearch::Model

      index_name :gene
    end

    # mappings:
    #   dynamic: strict
    #   properties:
    #     alias_of:
    #       type: keyword
    #     approved:
    #       type: boolean
    #     family:
    #       type: nested
    #       properties:
    #         id:
    #           type: integer
    #         name:
    #           type: keyword
    #     hgnc_id:
    #       type: integer
    #     location:
    #       type: keyword
    #     name:
    #       type: keyword
    #     symbol:
    #       type: keyword
    #       fields:
    #         lowercase:
    #           type: keyword
    #           normalizer: lowercase
    #         ngram_search:
    #           type: text
    #           analyzer: symbol_ngram_analyzer
    #         search:
    #           type: text
    #           analyzer: symbol_search_analyzer
    #         suggest:
    #           type: text
    #           analyzer: symbol_suggest_analyzer

    module ClassMethods
      # @param [Integer] id HGNC ID
      def find(id)
        query = Elasticsearch::DSL::Search.search do
          query do
            term(hgnc_id: id)
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
        unless Rails.cache.read('Gene.synonym')
          gen_synonyms_cache
          Rails.cache.write('Gene.synonym', true)
        end

        Rails.cache.read("Gene.synonym[#{hgnc_id}]")
      end

      def gen_synonyms_cache
        query = {
          sort: [:hgnc_id, :symbol],
          size: 10000,
        }

        current_id = nil
        synonyms = []

        t = Benchmark.realtime do
          while (rs = search(query).results).present?
            search_after = nil

            rs.each do |r|
              id, symbol = r[:_source]&.values_at(:hgnc_id, :symbol)

              if current_id && current_id != id && synonyms.present?
                Rails.cache.write("Gene.synonym[#{current_id}]", synonyms)
                synonyms = []
              end

              current_id = id

              next if r.dig(:_source, :approved)

              synonyms << r.dig(:_source, :symbol)

              search_after = [id, symbol].compact
            end

            break if search_after.blank?

            query.update(search_after:)
          end
        end

        Rails.logger.debug('Generate synonyms_cache') { "#{t} s" }
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
