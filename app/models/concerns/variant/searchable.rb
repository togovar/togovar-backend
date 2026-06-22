class Variant
  module Searchable
    extend ActiveSupport::Concern
    include ElasticsearchIndex::Base

    included do
      include Elasticsearch::Model

      index_name :variant
    end

    # mappings:
    #   dynamic: strict
    #   properties:
    #     active:
    #       type: boolean
    #     alphamissense:
    #       type: double
    #     alternate:
    #       type: keyword
    #       ignore_above: 8191
    #     alternate_hash:
    #       type: keyword
    #     cadd_phred:
    #       type: double
    #     chromosome:
    #       type: keyword
    #     chromosome_index:
    #       type: byte
    #     conditions:
    #       type: nested
    #       properties:
    #         condition:
    #           type: nested
    #           properties:
    #             classification:
    #               type: keyword
    #               eager_global_ordinals: true
    #             medgen:
    #               type: keyword
    #             origin:
    #               type: keyword
    #               eager_global_ordinals: true
    #             pref_name:
    #               type: keyword
    #             submission_count:
    #               type: unsigned_long
    #         id:
    #           type: keyword
    #         source:
    #           type: keyword
    #     frequency:
    #       type: nested
    #       properties:
    #         aac:
    #           type: unsigned_long
    #         ac:
    #           type: unsigned_long
    #         af:
    #           type: double
    #         an:
    #           type: unsigned_long
    #         aoc:
    #           type: unsigned_long
    #         arc:
    #           type: unsigned_long
    #         filter:
    #           type: keyword
    #           eager_global_ordinals: true
    #         hac:
    #           type: unsigned_long
    #         hoc:
    #           type: unsigned_long
    #         hrc:
    #           type: unsigned_long
    #         id:
    #           type: keyword
    #         ooc:
    #           type: unsigned_long
    #         quality:
    #           type: double
    #         roc:
    #           type: unsigned_long
    #         rrc:
    #           type: unsigned_long
    #         source:
    #           type: keyword
    #           eager_global_ordinals: true
    #     gene:
    #       properties:
    #         id:
    #           type: unsigned_long
    #         label:
    #           type: keyword
    #     id:
    #       type: unsigned_long
    #     most_severe_consequence:
    #       type: keyword
    #       eager_global_ordinals: true
    #     polyphen:
    #       type: double
    #     position_end:
    #       type: unsigned_long
    #     position_start:
    #       type: unsigned_long
    #     reference:
    #       type: keyword
    #       ignore_above: 8191
    #     reference_hash:
    #       type: keyword
    #     sift:
    #       type: double
    #     sscv_db:
    #       type: nested
    #       properties:
    #         gene_id:
    #           type: keyword
    #         predicted_splicing_type:
    #           type: keyword
    #           eager_global_ordinals: true
    #         variant_id:
    #           type: keyword
    #     sv:
    #       type: boolean
    #     type:
    #       type: keyword
    #       eager_global_ordinals: true
    #     vep:
    #       properties:
    #         alphamissense:
    #           type: double
    #         bp_overlap:
    #           type: unsigned_long
    #         cadd_phred:
    #           type: double
    #         consequence:
    #           type: keyword
    #         consequence_type:
    #           type: keyword
    #         gene_id:
    #           type: keyword
    #         hgnc_id:
    #           type: unsigned_long
    #         hgvs_c:
    #           type: keyword
    #           ignore_above: 8191
    #         hgvs_g:
    #           type: keyword
    #           ignore_above: 8191
    #         hgvs_p:
    #           type: keyword
    #           ignore_above: 8191
    #         mane_select:
    #           type: boolean
    #         percentage_overlap:
    #           type: double
    #         polyphen:
    #           type: double
    #         regulatory_feature_id:
    #           type: keyword
    #         sift:
    #           type: double
    #         symbol:
    #           properties:
    #             label:
    #               type: keyword
    #             source:
    #               type: keyword
    #         transcript_id:
    #           type: keyword
    #     xref:
    #       type: nested
    #       properties:
    #         id:
    #           type: keyword
    #         source:
    #           type: keyword

    module ClassMethods
      # @return [Hash]
      def cardinality
        Rails.cache.fetch('Variant::Searchable.cardinality') do
          query = Elasticsearch::DSL::Search.search do
            size 0

            aggregation :types do
              cardinality do
                field :type
              end
            end

            aggregation :conditions do
              nested do
                path 'conditions.condition'
                aggregation :classification do
                  cardinality do
                    field :'conditions.condition.classification'
                  end
                end
              end
            end

            aggregation :vep_consequences do
              cardinality do
                field :'most_severe_consequence'
              end
            end
          end

          aggs = search(query, request_cache: true).aggregations

          {
            vep_consequences: aggs.dig(:vep_consequences, :value),
            types: aggs.dig(:types, :value),
            condition_classifications: aggs.dig(:conditions, :classification, :value),
            condition_sources: Rails.application.config.application.dig(:datasets, :condition)&.size,
            frequency_sources: Rails.application.config.application.dig(:datasets, :frequency)&.size
          }
        end
      end

      # @param [Integer] id tgv ID
      def find(id)
        query = Elasticsearch::DSL::Search.search do
          query do
            term id:
          end
        end

        super(query)
      end

      def default_condition
        Elasticsearch::DSL::Search.search do
          query do
            match active: true
          end
        end.to_hash[:query]
      end

      MINIMAL_FIELDS = %w[
        id
        sv
        type
        chromosome_index
        chromosome
        position_start
        position_end
        reference
        alternate
        xref.source
        xref.id
        conditions.source
        conditions.id
        conditions.condition.medgen
        conditions.condition.pref_name
        conditions.condition.classification
        conditions.condition.submission_count
      ]

      def search_for_jogo(query)
        results = []

        unless gene_id_terms_exists?(query)
          raise Errors::APIValidationError.new('Invalid query',
                                               errors: ['must contain gene query with jogo formatter'])
        end

        q = query
        q[:size] = 10_000
        q[:fields] = MINIMAL_FIELDS
        q[:_source] = false
        q.delete(:from)

        while (res = search(q).records.results.results).present?
          res.each do |r|
            fields = r.delete(:fields)

            r[:_source] = {
              id: fields['id']&.first,
              sv: fields['sv']&.first,
              type: fields['type']&.first,
              chromosome_index: fields['chromosome_index']&.first,
              chromosome: fields['chromosome']&.first,
              position_start: fields['position_start']&.first,
              position_end: fields['position_end']&.first,
              reference: fields['reference']&.first,
              alternate: fields['alternate']&.first,
              xref: Array(fields['xref']).map do |xref|
                {
                  id: xref['id'].first,
                  source: xref['source'].first
                }
              end,
              conditions: Array(fields['conditions']).map do |condition|
                {
                  source: condition['source']&.first,
                  id: condition['id']&.first,
                  condition: (condition['condition'] || []).map do |x|
                    {
                      medgen: x['medgen'],
                      pref_name: x['pref_name'],
                      classification: x['classification'],
                      submission_count: x['submission_count']&.first
                    }
                  end
                }
              end
            }
          end

          results.concat(res)

          break if (last = res.last[:sort]).blank?

          q[:search_after] = last
        end

        results
      end

      private

      def gene_id_terms_exists?(obj)
        case obj
        when Hash
          return true if obj[:terms].is_a?(Hash) && obj[:terms].key?(:"gene.id")

          obj.any? { |_, v| gene_id_terms_exists?(v) }
        when Array
          obj.any? { |v| gene_id_terms_exists?(v) }
        else
          false
        end
      end
    end
  end
end
