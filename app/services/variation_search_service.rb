# frozen_string_literal: true

class VariationSearchService
  attr_reader :options
  attr_reader :debug

  # @param [Hash] params The request parameters
  # @param [Hash] options
  # @option options [Hash] :headers The request header
  # @option options [Boolean] :debug
  def initialize(params, **options)
    @params = params
    @options = options

    @debug = {}
    @errors = {}

    if @params[:body] && (offset = @params[:offset]).present?
      @params[:body][:offset] = if offset.respond_to?(:to_i)
                                  offset.to_i
                                else
                                  offset
                                end
    end
  end

  # @return [Hash]
  def execute
    debug.clear

    # remember to validate before obtaining debug information
    validate

    params = @params
    if (body = @params.delete(:body))
      params.merge!(body)
    end

    if params[:formatter] == 'html'
      HtmlFormatter.new(params, search, user: @options[:user]).to_hash
    elsif params[:formatter] == 'jogo'
      ResponseFormatter.new(params, search_all, @errors, user: @options[:user]).to_hash
    else
      ResponseFormatter.new(params, search, @errors, user: @options[:user]).to_hash
    end
  end

  def validate
    valid_spec = spec.validate
    valid_model = model.validate

    debug[:model] = model.nested_debugs if @options[:debug]

    raise Errors::APIValidationError.new('API validation error', errors: spec.errors) unless valid_spec
    raise Errors::QueryParseError.new('Query parse error', errors: model.nested_errors.full_messages) unless valid_model
  end

  def results
    Variation.search(query).records.results
  end

  def filtered_count
    Variation.count(body: query.slice(:query))
  end

  private

  def spec
    @spec ||= TogoVar::API::Spec::Validator.new schema(@params.fetch(:version, '1')),
                                                method: :post,
                                                path: '/search/variant',
                                                parameters: @params,
                                                headers: @options.fetch(:headers, {}),
                                                body: @params[:body]
  end

  def schema(version)
    YAML.safe_load(ERB.new(File.read(spec_path(version).to_s)).result(get_binding))
  end

  def get_binding
    @current_user = @options[:user] || {}

    binding
  end

  def spec_path(version)
    case version
    when '1'
      Rails.root / 'doc' / 'api' / 'v1.yml.erb'
    else
      raise Errors::SpecNotFoundError.new('Spec not found error', errors: ["Undefined version: #{version}"])
    end
  end

  def model
    @model ||= begin
                 search = TogoVar::API::VariationSearch.new(@params[:body])
                 search.options = { user: @options[:user] }

                 search.model
               end
  end

  def search
    hash = {}

    if @params[:stat] != 0
      hash.merge!(total: Variation::QueryHelper.total(@options[:user]),
                  filtered: filtered_count,
                  aggs: paging? ? {} : Variation.search(stat_query, request_cache: true).aggregations,
                  count_condition_absence: Variation::QueryHelper.count_conditions_absence(model.to_hash))
    end

    hash.merge!(results: results) if @params[:data] != 0

    hash
  end

  MINIMAL_FIELDS = %w[
    id
    type
    chromosome.index
    chromosome.label
    start
    stop
    reference
    alternate
    vcf.position
    vcf.reference
    vcf.alternate
    conditions.source
    conditions.id
    conditions.condition.medgen
    conditions.condition.pref_name
    conditions.condition.classification
    conditions.condition.submission_count
  ]

  def search_all
    results = []

    q = query
    q[:size] = 10_000
    q[:fields] = MINIMAL_FIELDS
    q[:_source] = false
    q.delete(:from)

    while (res = Variation.search(q).records.results.results).present?
      res.each do |r|
        fields = r.delete(:fields)

        r[:_source] = {
          id: fields['id']&.first,
          type: fields['type']&.first,
          chromosome: {
            index: fields['chromosome.index']&.first,
            label: fields['chromosome.label']&.first
          },
          start: fields['start']&.first,
          stop: fields['stop']&.first,
          reference: fields['reference']&.first,
          alternate: fields['alternate']&.first,
          vcf: {
            position: fields['vcf.position']&.first,
            reference: fields['vcf.reference']&.first,
            alternate: fields['vcf.alternate']&.first
          },
          conditions: (fields['conditions'] || []).map do |condition|
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

    {
      results: results,
    }
  end

  def query
    @query ||= model.to_hash.tap { |q| debug[:query] = q if @options[:debug] }
  end

  def paging?
    (offset = @params.dig(:offset)).present? && offset != 0
  end

  def stat_query
    @stat_query ||= begin
                      hash = query.dup
                      hash.update size: 0
                      hash.delete :from
                      hash.delete :sort
                      hash.merge!(Variation::QueryHelper.statistics(@options[:user]))

                      hash.tap { |h| debug[:stat_query] = h if @options[:debug] }
                    end
  end
end
