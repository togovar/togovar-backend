# frozen_string_literal: true

module API
  class DownloadController < ApplicationController
    include ActionController::Live
    include AuthHelper

    before_action :authenticate_user, only: %i[variant]

    MAX_DOWNLOAD_RECORDS_LIMIT = 100_000

    class QueryError < StandardError; end

    # GET /api/download/variant(.:format)
    # POST /api/download/variant(.:format)
    def variant
      respond_to do |format|
        format.html do
          errors = ["Add an accept header 'application/json', 'text/csv' or 'text/plain' to the request."]
          render json: { errors: errors }, status: :not_implemented
        end

        format.json do
          errors, status = validate_query
          render(json: { errors: errors }, status: status) and return if errors.present?

          set_header('application/json; charset=utf-8')
          output_json
        end

        format.csv do
          errors, status = validate_query
          render(plain: errors.join("\n"), status: status) and return if errors.present?

          set_header('text/csv; charset=utf-8')
          output_csv
        end

        format.text do
          errors, status = validate_query
          render(plain: errors.join("\n"), status: status) and return if errors.present?

          set_header('text/tab-separated-values; charset=utf-8')
          output_csv("\t")
        end
      end

      response.stream.close
    rescue ActionController::Live::ClientDisconnected => e
      Rails.logger.info(self.class) { e.message }
    end

    private

    def search_params
      return @search_params if @search_params

      query = if request.get?
                params.permit :term, :quality, :limit, :offset, :debug, column: {},
                              dataset: {}, frequency: {}, type: {}, significance: {}, consequence: {},
                              sscv_db: {}, sift: {}, polyphen: {}, alphamissense: {}, cadd_phred: {}
              else
                if params.key?(:query)
                  params.permit query: {}, column: []
                else
                  body = request.body.tap(&:rewind).read
                  JSON.parse(body).with_indifferent_access
                end
              end.to_h

      query.delete(:offset)
      query.delete(:limit)

      @search_params = query.merge(body: query)
    end

    def output_columns
      columns = %i[id rs position ref_alt type gene frequency consequence sift polyphen alphamissense condition]

      if request.get?
        columns - (search_params[:column].presence || {}).select { |_, v| v == '0' }.keys.map(&:to_sym)
      else
        search_params[:column].present? ? Array(search_params[:column]).map(&:to_sym) : columns
      end
    end

    def validate_query
      service = if request.get?
                  VariantSearchService::Query.new(search_params, user: current_user)
                else
                  VariantSearchService.new(search_params, user: current_user)
                end

      service.validate

      if (total = service.filtered_count) > MAX_DOWNLOAD_RECORDS_LIMIT
        msg = 'Limit your search to less than %{limit} results. Current query returns %{total} results.' % {
          limit: ActiveSupport::NumberHelper.number_to_delimited(MAX_DOWNLOAD_RECORDS_LIMIT),
          total: ActiveSupport::NumberHelper.number_to_delimited(total)
        }

        raise QueryError, msg
      end

      []
    rescue Errors::ServiceError => e
      [e.errors, e.status]
    rescue QueryError => e
      [[e.message], :bad_request]
    rescue => e
      [[e.message], :internal_server_error]
    end

    def set_header(content_type)
      response.headers['X-Accel-Buffering'] = 'no'
      response.headers['Cache-Control'] = 'no-cache'
      response.headers['Content-Disposition'] = 'attachment'
      response.headers['Content-Type'] = content_type if content_type.present?
      response.headers['Last-Modified'] = Time.now.httpdate.to_s
      response.headers.delete('Content-Length')
    end

    def results
      offset = nil
      total = 0

      Enumerator.new do |yielder|
        loop do
          params = search_params
          params[:offset] = params[:body][:offset] = offset if offset.present?

          service = if request.get?
                      VariantSearchService::Query.new(params, user: current_user)
                    else
                      VariantSearchService.new(params, user: current_user)
                    end

          break if (res = service.results.to_a).blank?

          yielder << res

          break if (total += res.size) > MAX_DOWNLOAD_RECORDS_LIMIT

          last = res.last

          offset = [
            last&.dig(:_source, :chromosome)&.to_i,
            last&.dig(:_source, :position_start)&.to_i,
            last&.dig(:_source, :reference)&.to_s,
            last&.dig(:_source, :alternate)&.to_s
          ].compact

          break if offset.size != 4
        end
      end
    end

    def output_json
      response.stream.write %Q({\n  "data": [)

      first = true
      results.each do |page|
        page.each do |result|
          begin
            json = JSON.pretty_generate(transform(result)).indent(4)
            response.stream.write ',' unless first
            response.stream.write "\n"
            response.stream.write json
            first = false
          rescue ActionController::Live::ClientDisconnected => e
            raise e
          rescue => e
            Rails.logger.error(self.class) { e }
          end
        end
      end
    ensure
      response.stream.write "\n  ]\n}"
    end

    def output_csv(delimiter = ',')
      write_header = false
      results.each do |page|
        page.each do |result|
          begin
            result = transform(result, :csv)
            unless write_header
              response.stream.write CSV.generate_line(result.keys, col_sep: delimiter)
              write_header = true
            end

            response.stream.write CSV.generate_line(result.values, col_sep: delimiter)
          rescue ActionController::Live::ClientDisconnected => e
            raise e
          rescue => e
            Rails.logger.error(self.class) { e }
          end
        end
      end
    end

    def synonyms
      @synonyms ||= Hash.new { |hash, key| hash[key] = Gene.synonyms(key) }
    end

    def transform(result, type = :json)
      result = result[:_source].with_indifferent_access

      molecular_annotations(result, type).merge(frequencies(result, type))
    end

    ITEMS_SEPARATOR = ';'

    def molecular_annotations(result, type = :json)
      id = result[:id].present? ? "tgv#{result[:id]}" : nil
      dbsnp = Array(result[:xref])
                .filter { |x| x[:source] = 'dbSNP' }
                .map { |x| x[:id] }
      dbsnp = dbsnp.join(ITEMS_SEPARATOR) if type == :csv

      vep = Array(result[:vep])
      symbols = if type == :csv
                  vep.filter_map { |x| { name: x.dig(:symbol, :label), id: x[:hgnc_id] } if x.dig(:symbol, :source) == 'HGNC' && x[:hgnc_id] }
                     .uniq
                     .map { |x| x[:name] }
                     .join(ITEMS_SEPARATOR)
                else
                  vep.filter_map { |x| { name: x.dig(:symbol, :label), id: x[:hgnc_id] } if x.dig(:symbol, :source) == 'HGNC' && x[:hgnc_id] }
                     .uniq
                     .map { |x| { name: x[:name], id: x[:id], synonyms: synonyms[x[:id]] }.compact }
                end

      consequences = vep.flat_map { |x| x[:consequence] }
                        .uniq
                        .map { |x| QueryParameters::Consequence.find_by_id(x) }
      consequences = (QueryParameters::Consequence::ALL & consequences).map { |x| x.id }
      consequences = consequences.join(ITEMS_SEPARATOR) if type == :csv

      sift = vep.map { |x| x[:sift] }.compact.min
      polyphen = vep.map { |x| x[:polyphen] }.compact.max
      alphamissense = vep.map { |x| x[:alphamissense] }.compact.max

      conditions = Hash.new { |hash, key| hash[key] = Disease.find(key)&.[](:name) }
      condition = Array(result.dig(:conditions)).map do |x|
        {
          source: x[:source],
          id: x[:id],
          condition: Array(x[:condition]).map do |y|
            {
              medgen: Array(y[:medgen]).map { |v| { name: conditions[v] || QueryParameters::ClinicalSignificance::LABEL_NOT_PROVIDED, medgen: v } },
              pref_name: y[:pref_name],
              classification: Array(y[:classification]).filter_map { |v| QueryParameters::ClinicalSignificance.find_by_id(v)&.label },
              submission_count: y[:submission_count]
            }.compact
          end
        }
      end
      if type == :csv
        condition = condition.flat_map do |x|
          x[:condition].map do |y|
            "#{x[:source]}:#{y[:medgen].filter_map { |v| v[:name].presence }.flatten.uniq.join('|')}=#{Array(y[:classification]).join('|').presence || '-'}"
          end
        end.join(ITEMS_SEPARATOR)
      end

      columns = output_columns
      data = {}
      data[:tgv_id] = id if columns.include?(:id)
      data[:rs] = dbsnp.presence if columns.include?(:rs)
      if columns.include?(:position)
        data[:chromosome] = result[:chromosome]
        suffix = ENV.fetch('TOGOVAR_REFERENCE', nil)
        data["position#{"_#{suffix.downcase}" if suffix}"] = result[:position_start]
      end
      if columns.include?(:ref_alt)
        data[:reference] = result[:reference]
        data[:alternate] = result[:alternate]
      end
      data[:type] = result[:type] if columns.include?(:type)
      data[:gene] = symbols.presence if columns.include?(:gene)
      data[:consequence] = consequences.presence if columns.include?(:consequence)
      data[:condition] = condition.presence if columns.include?(:condition)
      if columns.include?(:sift)
        data[:sift_qualitative_prediction] = sift ? QueryParameters::Sift.find_by_value(sift)&.label : nil
        data[:sift_score] = sift
      end
      if columns.include?(:polyphen)
        data[:polyphen2_qualitative_prediction] = polyphen ? QueryParameters::Polyphen.find_by_value(polyphen).label : nil
        data[:polyphen2_score] = polyphen
      end
      if columns.include?(:alphamissense)
        data[:alphamissense_pathogenicity] = alphamissense ? QueryParameters::AlphaMissense.find_by_value(alphamissense)&.label : nil
        data[:alphamissense_score] = alphamissense
      end

      data
    end

    def frequencies(result, type = :json)
      return {} unless output_columns.include?(:frequency)

      frequencies = Array(result[:frequency]).map(&:compact)

      frequencies.each do |x|
        if x[:ac].present? && x[:an].present? && x[:af].blank?
          x[:af] = Float(x[:ac]) / Float(x[:an])
        end
      end

      frequencies = Variant.frequency_datasets(current_user).map do |source|
        data = frequencies.find { |x| x[:source] == source.to_s } || {}

        filters = Array(data[:filter])
        filters = filters.join(ITEMS_SEPARATOR) if type == :csv

        hash = if (config = Rails.application.config.application.dig(:datasets, :frequency).find { |x| x[:id] == source.to_s })
                 config[:download].to_h { |k, v| ["#{source}_#{v}", data[k]] }.merge("#{source}_qc_status": filters.presence)
               else
                 {
                   "#{source}_allele_alt": data[:ac],
                   "#{source}_allele_total": data[:an],
                   "#{source}_alt_allele_freq": data[:af],
                   "#{source}_qc_status": filters.presence
                 }
               end

        hash.compact! if type == :json

        hash
      end

      frequencies.reject!(&:blank?) if type == :json

      frequencies.inject({}) { |memo, x| memo.merge(x) }
    end
  end
end
