# frozen_string_literal: true

module TogoVar
  module API
    module Models
      module Version1
        class SscvDb < StrictTerms
          self.key_name = :sscv_db

          ACCEPTABLE_TERMS = Rails.application
                                  .config
                                  .application
                                  .dig(:query_params, :sscv_db)
                                  .flat_map { |x| [x[:id], x[:key]] }

          def to_hash
            validate

            relation = @relation
            terms = @terms.filter_map { |x| QueryParameters::SscvDb.find(x)&.id }

            Elasticsearch::DSL::Search.search do
              query do
                if relation == 'eq'
                  nested do
                    path 'sscv_db'
                    query do
                      terms 'sscv_db.predicted_splicing_type': terms
                    end
                  end
                else
                  bool do
                    must_not do
                      nested do
                        path 'sscv_db'
                        query do
                          terms 'sscv_db.predicted_splicing_type': terms
                        end
                      end
                    end
                  end
                end
              end
            end.to_hash[:query]
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
