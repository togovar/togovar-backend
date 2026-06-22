# frozen_string_literal: true

module TogoVar
  module API
    module Models
      module Version1
        class CaddPhred < Base
          self.key_name = :cadd_phred

          attr_reader :score

          validates :score, presence: true

          def initialize(*args)
            super

            arg = @args.first

            @score = arg[:score]
          end

          # @return [Array]
          def models
            return @models if @models

            model = {}
            if score.is_a?(Hash)
              model.update(cadd_phred: Range.new(score.merge(field: 'cadd_phred')))
            else
              model.update(cadd_phred: NotExist.new(field: 'cadd_phred')) if score.include?('unassigned')
            end

            @models = [model]
          end

          def to_hash
            validate

            models = self.models.first

            Elasticsearch::DSL::Search.search do
              query models[:cadd_phred]
            end.to_hash[:query]
          end
        end
      end
    end
  end
end
