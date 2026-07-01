# frozen_string_literal: true

module TogoVar
  module API
    module Models
      module Version1
        class Location < Base
          attr_reader :chromosome
          attr_reader :position

          def initialize(*args)
            super

            arg = @args.first.dup

            @chromosome = arg[:chromosome]
            @position = arg[:position] # Integer or Range
          end

          # @return [Array]
          def models
            return @models if @models

            model = {}
            model.update(chromosome: Chromosome.new(@chromosome))

            @position = case @position
                        when Integer
                          { gte: @position, lte: @position }
                        when Hash
                          @position.with_indifferent_access
                        else
                          raise InvalidQuery, "Invalid value #{@position}:#{@position.class}"
                        end
            model.update(position: Range.new({ field: 'position' }.merge(position))) # just for validation

            @models = [model]
          end

          def to_hash
            validate

            model = self.models.first

            gt_or_gte, from = @position.slice(:gt, :gte).first
            lt_or_lte, to = @position.slice(:lt, :lte).first

            Elasticsearch::DSL::Search.search do
              query do
                bool do
                  filter model[:chromosome] if model[:chromosome]
                  if gt_or_gte && lt_or_lte
                    filter(closed_range(gt_or_gte, from, lt_or_lte, to))
                  elsif lt_or_lte
                    filter(left_open_range(lt_or_lte, to))
                  elsif gt_or_gte
                    filter(right_open_range(gt_or_gte, from))
                  end
                end
              end
            end.to_hash[:query]
          end

          private

          def closed_range(gt_or_gte, from, lt_or_lte, to)
            Elasticsearch::DSL::Search.search do
              query do
                bool do
                  should do
                    # both start and stop is in range
                    bool do
                      filter do
                        range :position_start do
                          send(gt_or_gte.to_sym, from)
                        end
                      end
                      filter do
                        range :position_end do
                          send(lt_or_lte.to_sym, to)
                        end
                      end
                    end
                  end
                  should do
                    # either start or stop is in range
                    bool do
                      should do
                        range :position_start do
                          send(gt_or_gte.to_sym, from)
                          send(lt_or_lte.to_sym, to)
                        end
                      end
                      should do
                        range :position_end do
                          send(gt_or_gte.to_sym, from)
                          send(lt_or_lte.to_sym, to)
                        end
                      end
                    end
                  end
                  should do
                    # both start and stop is out of range (i.e. overlapping)
                    bool do
                      filter do
                        range :position_start do
                          lte from
                        end
                      end
                      filter do
                        range :position_end do
                          gte to
                        end
                      end
                    end
                  end
                end
              end
            end.to_hash[:query]
          end

          def left_open_range(lt_or_lte, to)
            Elasticsearch::DSL::Search.search do
              query do
                range :position_start do
                  send(lt_or_lte.to_sym, to)
                end
              end
            end.to_hash[:query]
          end

          def right_open_range(gt_or_gte, from)
            Elasticsearch::DSL::Search.search do
              query do
                range :position_end do
                  send(gt_or_gte.to_sym, from)
                end
              end
            end.to_hash[:query]
          end
        end
      end
    end
  end
end
