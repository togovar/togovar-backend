# frozen_string_literal: true

module TogoVar
  module API
    module Models
      module Version1
        class VariantConsequence < StrictTerms
          self.key_name = :consequence

          ACCEPTABLE_TERMS = Rails.application
                                  .config
                                  .application
                                  .dig(:query_params, :consequence)
                                  .flat_map { |x| [x[:id], x[:key]] }

          def to_hash
            validate

            terms = @terms.filter_map { |x| QueryParameters::Consequence.find(x)&.id }

            q = Elasticsearch::DSL::Search.search do
              query do
                terms 'vep.consequence': terms
              end
            end

            (@relation == 'ne' ? negate(q) : q).to_hash[:query]
          end

          protected

          def acceptable_terms
            ACCEPTABLE_TERMS
          end
        end
      end
    end
  end
end
