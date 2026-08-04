# frozen_string_literal: true

module TogoVar
  module API
    module Models
      module Version1
        class Variant < Base
          include TogoVar::Helper

          attr_reader :chromosome
          attr_reader :position
          attr_reader :reference
          attr_reader :alternate

          validates :position, numericality: true
          validate do
            next if reference.match?(/^[ATCGN]+$/)

            errors.add(:reference, "must consist of 'A', 'T', 'C', 'G' and 'N'")
          end
          validate do
            next if alternate.match?(/^[ATCGN]+$/)

            errors.add(:alternate, "must consist of 'A', 'T', 'C', 'G' and 'N'")
          end

          def initialize(*args)
            super

            arg = @args.first.dup

            @chromosome = arg[:chromosome]
            @position = arg[:position] # Integer
            @reference = arg[:reference]
            @alternate = arg[:alternate]
          end

          # @return [Array]
          def models
            return @models if @models

            model = {}
            model.update(chromosome: Chromosome.new(@chromosome))

            @models = [model]
          end

          def to_hash
            validate

            model = self.models.first
            position_start = @position
            reference = @reference
            alternate = @alternate

            Elasticsearch::DSL::Search.search do
              query do
                bool do
                  filter model[:chromosome]
                  filter({ match: { position_start: } })
                  if reference.length > 50
                    filter({ match: { reference_hash: hashing(reference) } })
                  else
                    filter({ match: { reference: } })
                  end
                  if alternate.length > 50
                    filter({ match: { alternate_hash: hashing(alternate) } })
                  else
                    filter({ match: { alternate: } })
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
