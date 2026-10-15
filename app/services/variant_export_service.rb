# frozen_string_literal: true

class VariantExportService
  def initialize(**options)
    @chromosome = options[:chromosome]&.delete_prefix('chr')

    @chromosome_index = case @chromosome.upcase
                        when 'X'
                          23
                        when 'Y'
                          24
                        when 'M'
                          25
                        when 'MT'
                          26
                        else
                          @chromosome.to_i
                        end

    @search_after = options[:search_after]
  end

  # @return [Hash]
  def execute
    raise ArgumentError, 'Chromosome index is required' if @chromosome.blank?

    VariantSearchService::ResponseFormatter.new({}, search).to_hash
  end

  private

  def search
    { results: Variant.search(query).records.results }
  end

  def query
    chromosome_index = @chromosome_index
    search_after = if @search_after
                     [
                       @search_after['position'].to_i,
                       @search_after['reference'].to_s,
                       @search_after['alternate'].to_s
                     ].compact
                   end

    if search_after && search_after.length != 3
      raise "Invalid search_after value: #{search_after}"
    end

    query = Elasticsearch::DSL::Search.search do
      query do
        match chromosome_index:
      end

      sort do
        by :'position_start'
        by :'reference'
        by :'alternate'
      end

      size 10_000
    end.to_hash

    query.update(search_after:) if search_after

    query
  end
end
