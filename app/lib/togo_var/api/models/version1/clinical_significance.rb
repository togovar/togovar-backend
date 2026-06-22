# frozen_string_literal: true

module TogoVar
  module API
    module Models
      module Version1
        class ClinicalSignificance < StrictTerms
          self.key_name = :significance

          ACCEPTABLE_TERMS = Rails.application
                                  .config
                                  .application
                                  .dig(:query_params, :significance)
                                  .flat_map { |x| [x[:id], x[:key]] }

          def initialize(*args)
            super

            arg = @args.first

            @terms = Array(arg[:terms])
            @include_na = QueryParameters::NOT_AVAILABLE_KEYS.any? { |x| @terms.include?(x) }
            @source = Array(arg[:source])

            raise InvalidQuery, 'terms = ["NA"] and source are exclusive when relation = "eq"' if @relation == 'eq' && @include_na && @source.present?
          end

          def to_hash
            validate

            relation = @relation
            include_na = @include_na
            terms = @terms.reject { |x| QueryParameters::NOT_AVAILABLE_KEYS.include?(x) }
                          .filter_map { |x| QueryParameters::ClinicalSignificance.find(x)&.id }
            sources = @source

            if include_na
              Elasticsearch::DSL::Search.search do
                query do
                  bool do
                    if relation == 'eq'
                      must_not do
                        nested do
                          path 'conditions'
                          query do
                            exists field: 'conditions'
                          end
                        end
                      end
                    else
                      must do
                        nested do
                          path 'conditions'
                          query do
                            exists field: 'conditions'
                          end
                        end
                      end
                      if sources.present?
                        must do
                          nested do
                            path 'conditions'
                            query do
                              terms 'conditions.source': sources
                            end
                          end
                        end
                      end
                    end
                  end
                end
              end
            else
              Elasticsearch::DSL::Search.search do
                query do
                  bool do
                    if sources.present?
                      must do
                        nested do
                          path 'conditions'
                          query do
                            terms 'conditions.source': sources
                          end
                        end
                      end
                    end

                    if terms.present?
                      q = Elasticsearch::DSL::Search.search do
                        query do
                          bool do
                            must do
                              nested do
                                path 'conditions.condition'
                                query do
                                  terms 'conditions.condition.classification': terms
                                end
                              end
                            end
                          end
                        end
                      end

                      q = (relation == 'ne' ? negate(q) : q).to_hash[:query]

                      must q
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
