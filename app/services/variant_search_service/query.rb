# frozen_string_literal: true

class VariantSearchService
  # @deprecated This class remains only for backwards compatibility
  class Query
    attr_reader :options
    attr_reader :debug
    attr_reader :error
    attr_reader :warning
    attr_reader :notice

    # @param [Hash] params The request parameters
    # @param [Hash] options
    # @option options [Boolean] :debug
    def initialize(params, **options)
      @params = params
      @options = options

      @debug = {}
      @error = []
      @warning = []
      @notice = []
    end

    # @return [Hash]
    def execute
      gene_order = (gene = Gene.exact_match(param.term)) ? [gene[:hgnc_id]] : []

      ResponseFormatter.new(param, search, @error, @warning, @notice, user: @options[:user], gene_order:).to_hash
    end

    def query
      builder.build.tap { |q| debug[:query] = q if @options[:debug] }
    end

    def validate; end

    def results
      Rails.logger.debug { 'Search variants' }

      Variant.search(query, request_cache: true).records.results
    end

    def filtered_count
      Rails.logger.debug { 'Count filtered variants' }

      Variant.count(body: query.slice(:query))
    end

    private

    def total_count
      Rails.logger.debug { 'Count all variants' }

      Variant::QueryHelper.total(@options[:user])
    end

    def statistics_count
      Rails.logger.debug { 'Count statistics' }

      Variant.search(stat_query, request_cache: true).aggregations.to_hash
    end

    def condition_absence_count
      Rails.logger.debug { 'Count condition absence' }

      Variant::QueryHelper.count_conditions_absence(builder.build)
    end

    def stat_query
      builder.stat_query.tap { |q| debug[:stat_query] = q if @options[:debug] }
    end

    def param
      @param ||= Parameters.new(@params, user: @options[:user])
    end

    BINARY_FILTERS = %i[dataset type significance consequence sscv_db sift polyphen alphamissense cadd_phred].freeze

    def builder
      @builder ||= begin
                     builder = VariantSearchService::QueryBuilder.new(user: @options[:user], filter: param.filter?)

                     builder.term(param.term) if param.term.present?

                     builder.from = param.offset
                     builder.size = param.limit

                     if BINARY_FILTERS.map { |x| param.selected_none?(x) }.any?
                       builder.from = 0
                       builder.size = 0
                     else
                       builder.dataset(param.selected_items(:dataset))

                       unless param.frequency == QueryParameters::Frequency.defaults
                         builder.frequency(param.selected_items(:dataset),
                                           param.frequency[:from],
                                           param.frequency[:to],
                                           param.frequency[:invert] == '1',
                                           param.frequency[:match] == 'all')
                       end

                       %i[type significance consequence sscv_db sift polyphen alphamissense cadd_phred].each do |x|
                         unless param.selected_all?(x)
                           builder.send(x, *param.selected_items(x))
                         end
                       end
                     end

                     builder
                   end
    end

    def empty_result
      {
        total: Variant::QueryHelper.total(@options[:user]),
        filtered: 0,
        hits: [],
        aggs: {},
        count_condition_absence: 0
      }
    end

    def search
      return empty_result if BINARY_FILTERS.map { |x| param.selected_none?(x) }.any?

      param.term = hgvs_notation_to_location(param.term)

      hash = {}

      if param.stat?
        hash.merge!(total: total_count,
                    filtered: filtered_count,
                    aggs: param.stat? ? statistics_count : {},
                    count_condition_absence: condition_absence_count)
      end

      hash.merge!(results:) if param.data?

      hash
    end

    def hgvs_notation_to_location(term)
      return if term.blank?
      return term unless HGVS.match?(term)

      hgvs = HGVS.new(term)
      location = hgvs.extract_location

      Rails.logger.debug('HGVS') { "Translate HGVS representation '#{term}' to '#{location}'" }

      @error << hgvs.translate_error if hgvs.translate_error.present?
      @warning << hgvs.translate_warning if hgvs.translate_warning.present?
      @notice << "Translate HGVS representation '#{term}' to '#{location}'" if location.present?

      location || term
    end

    class Parameters
      attr_writer :term
      attr_reader :dataset
      attr_reader :frequency
      attr_reader :quality
      attr_reader :type
      attr_reader :significance
      attr_reader :consequence
      attr_reader :sscv_db
      attr_reader :sift
      attr_reader :polyphen
      attr_reader :alphamissense
      attr_reader :cadd_phred

      attr_reader :expand_dataset

      attr_reader :offset
      attr_reader :limit

      def initialize(params, **options)
        params = params.to_h.deep_symbolize_keys

        accessible = Variant.all_datasets(options[:user]).map(&:to_sym)

        @term = params.fetch(:term, '')
        @dataset = QueryParameters::Dataset.defaults(params.fetch(:dataset, {}).slice(*accessible))
        @dataset.merge!(QueryParameters::Dataset.defaults.keys.reject { |x| accessible.include?(x) }.to_h { |x| [x, '0'] })

        @frequency = QueryParameters::Frequency.defaults(params.fetch(:frequency, {}))
        @quality = params.fetch(:quality, '1')
        @type = QueryParameters::Type.defaults(params.fetch(:type, {}))
        @significance = QueryParameters::ClinicalSignificance.defaults(params.fetch(:significance, {}))
        @consequence = QueryParameters::Consequence.defaults(params.fetch(:consequence, {}))
        @sscv_db = QueryParameters::SscvDb.defaults(params.fetch(:sscv_db, {}))
        @sift = QueryParameters::Sift.defaults(params.fetch(:sift, {}))
        @polyphen = QueryParameters::Polyphen.defaults(params.fetch(:polyphen, {}))
        @alphamissense = QueryParameters::AlphaMissense.defaults(params.fetch(:alphamissense, {}))
        @cadd_phred = QueryParameters::CaddPhred.defaults(params.fetch(:cadd_phred, {}))

        @expand_dataset = params.key?(:expand_dataset)

        @offset = params[:offset].is_a?(Array) ? params[:offset] : between(params.fetch(:offset, '0').to_i, 0, 10_000)
        @limit = between(params.fetch(:limit, '100').to_i, 0, 100)

        @stat = params.fetch(:stat, '1')
        @data = params.fetch(:data, '1')
        @debug = params.key?(:debug)
        @options = options
      end

      def [](symbol_or_string)
        instance_variable_get("@#{symbol_or_string}")
      end

      def debug?
        @debug
      end

      DISABLE_VALUES = %w[0 f false]
      ENABLE_VALUES = %w[1 t true]

      def stat?
        !DISABLE_VALUES.include?(@stat.to_s)
      end

      def data?
        !DISABLE_VALUES.include?(@data.to_s)
      end

      def filter?
        !DISABLE_VALUES.include?(@quality.to_s)
      end

      def term
        @term&.strip
      end

      def selected_items(attr_name)
        send(attr_name).select { |_, v| ENABLE_VALUES.include?(v) }.keys
      end

      def selected_all?(attr_name)
        send(attr_name).all? { |_, v| ENABLE_VALUES.include?(v) }
      end

      def selected_any?(attr_name)
        send(attr_name).any? { |_, v| ENABLE_VALUES.include?(v) }
      end

      def selected_none?(attr_name)
        !selected_any?(attr_name)
      end

      def to_hash
        %i[term dataset frequency quality type significance consequence sscv_db sift polyphen alphamissense cadd_phred expand_dataset].map do |name|
          [name, ((v = send(name)).respond_to?(:to_h) ? v.to_h : v)]
        end.to_h
      end

      private

      def between(v, min, max)
        [[v, min].max, max].min
      end

      def count_only?
        return true if @dataset.all? { |_, v| v.to_i.zero? }
        return true if @type.all? { |_, v| v.to_i.zero? }
        return true if @significance.all? { |_, v| v.to_i.zero? }
        return true if @consequence.all? { |_, v| v.to_i.zero? }

        false
      end
    end
  end
end
