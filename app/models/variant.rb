class Variant
  include Variant::Searchable

  class << self
    def all_datasets(user, groups: false, filter: nil, resolve_alias: false)
      frequency_datasets(user, groups:, filter:, resolve_alias:).concat(condition_datasets(user))
    end

    def frequency_datasets(user, groups: false, filter: nil, resolve_alias: false)
      datasets = accessible_datasets(user)[:frequency]

      datasets.flat_map do |dataset|
        g = if groups
              Array(dataset[:groups]).map do |x|
                if x.is_a?(Hash)
                  x[resolve_alias && x[:alias].present? ? :alias : :id]
                else
                  x
                end.to_sym
              end
            else
              []
            end

        [dataset[resolve_alias && dataset[:alias].present? ? :alias : :id].to_sym].concat(g) if filter.nil? || dataset[:filter].presence == filter.presence
      end.compact
    end

    def condition_datasets(user)
      datasets = accessible_datasets(user)[:condition]

      datasets.map { |x| x[:id].to_sym }
    end

    def accessible_datasets(user)
      authorized_datasets = Array((user || {})[:datasets]&.keys&.map(&:to_s))

      filter_hash(Rails.application.config.application[:datasets], authorized_datasets)
    end

    def aliases(user, groups: false)
      aliases = {}

      datasets = accessible_datasets(user)

      datasets[:frequency].each do |dataset|
        if dataset[:alias].present?
          aliases[dataset[:id]] = dataset[:alias]
        end

        if groups && dataset[:groups].present?
          Array(dataset[:groups]).each do |x|
            next unless x.is_a?(Hash)

            if x[:alias].present?
              aliases[x[:id]] = x[:alias]
            end
          end
        end
      end

      aliases.group_by { |_, v| v }
             .map { |k, v| [k, v.map(&:first)] }
             .to_h
    end

    def resolve_alias(user, datasets)
      accessible = accessible_datasets(user)[:frequency]

      datasets.filter_map do |dataset|
        next unless (conf = accessible.find { |x| x[:id] == dataset.to_s })

        (conf[:alias].present? ? conf[:alias] : dataset).to_sym
      end
    end

    private

    def filter_hash(hash, values)
      return hash unless hash.is_a?(Hash)
      return if hash.key?(:authorization) && !values.include?(hash.dig(:authorization, :id))

      hash.each_with_object({}) do |(k, v), result|
        if v.is_a?(Array)
          arr = v.map { |x| filter_hash(x, values) }.compact
          result[k] = arr unless arr.blank?
        elsif v.is_a?(Hash)
          nested = filter_hash(v, values)
          result[k] = nested unless nested.blank?
        else
          result[k] = v
        end
      end
    end
  end

  module QueryHelper
    def total(user = {})
      body = Elasticsearch::DSL::Search.search do
        query do
          bool do
            filter({ match: { active: true } })
            filter do
              bool do
                should do
                  nested do
                    path :frequency
                    query do
                      terms 'frequency.source': Variant.frequency_datasets(user, resolve_alias: true)
                    end
                  end
                end
                should do
                  nested do
                    path :conditions
                    query do
                      terms 'conditions.source': Variant.condition_datasets(user)
                    end
                  end
                end
              end
            end
          end
        end
      end

      Variant.count(body:)
    end

    def statistics(user = {})
      cardinality = Variant.cardinality

      Elasticsearch::DSL::Search.search do
        aggregation :type do
          terms field: :type,
                size: cardinality[:types]
        end

        aggregation :consequence do
          terms field: 'facet_consequence',
                size: cardinality[:vep_consequences]
        end

        aggregation :condition_source do
          terms field: 'facet_condition_source',
                size: cardinality[:condition_sources]
        end

        aggregation :condition_classification do
          terms field: 'facet_condition_classification',
                size: cardinality[:condition_classifications]
        end

        aggregation :frequency_source do
          terms field: 'facet_frequency_source',
                size: cardinality[:frequency_sources],
                include: Variant.frequency_datasets(user, resolve_alias: true)
        end
      end
    end

    def count_conditions_absence(query)
      q = {
        nested: {
          path: 'conditions',
          query: {
            exists: {
              field: 'conditions'
            }
          }
        }
      }

      body = if query[:query].key?(:bool)
               must_not = (query.dig(:query, :bool, :must_not) || []).concat([q])

               {
                 query: {
                   bool: query[:query][:bool].merge(must_not:)
                 }
               }
             else
               {
                 query: {
                   bool: {
                     must_not: [q],
                     filter: [query[:query]]
                   }
                 }
               }
             end

      Variant.count(body:)
    end

    module_function :total, :statistics, :count_conditions_absence
  end
end
