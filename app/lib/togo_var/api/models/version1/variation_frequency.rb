# frozen_string_literal: true

module TogoVar
  module API
    module Models
      module Version1
        class VariationFrequency < Base
          self.key_name = :frequency

          attr_reader :dataset
          attr_reader :frequency
          attr_reader :count
          attr_reader :genotype
          attr_reader :filtered

          validate do
            unless [frequency, count, genotype].one?
              errors.add(:base, "Use either of 'frequency', 'count' or 'genotype'")
            end
          end

          def initialize(*args)
            super

            arg = @args.first.dup

            @dataset = arg[:dataset]
            @frequency = arg[:frequency]
            @count = arg[:count]
            @genotype = arg[:genotype]&.deep_symbolize_keys
            @filtered = arg[:filtered]
          end

          # @return [Array]
          def models
            return @models if @models

            model = {}
            model.update(dataset: Dataset.new(@dataset)) if @dataset
            if @frequency
              model.update(frequency: Range.new(@frequency.merge(field: 'frequency.af')))
            elsif @count
              model.update(count: Range.new(@count.merge(field: 'frequency.ac')))
            elsif @genotype
              model.update(genotype: Range.new(@genotype[:count].merge(field: "frequency.#{@genotype[:key]}")))
            end

            @models = [model]
          end

          def to_hash
            validate

            models = self.models.first
            filtered = cast_boolean(@filtered)

            Elasticsearch::DSL::Search.search do
              query do
                nested do
                  path :frequency
                  query do
                    bool do
                      must models[:dataset] if models[:dataset]
                      must models[:frequency] if models[:frequency]
                      must models[:count] if models[:count]
                      must models[:genotype] if models[:genotype]
                      must { match 'frequency.filter': 'PASS' } if filtered.present?
                    end
                  end
                end
              end
            end.to_hash[:query]
          end
        end
      end
    end
  end
end
