# frozen_string_literal: true

require 'benchmark'
require 'open3'

module API
  class SearchController < ApplicationController
    include ActionController::Live
    include AuthHelper
    include Executable

    before_action :authenticate_user, only: %i[variant search_variant]

    wrap_parameters name: :body, format: :json

    def variant
      respond_to do |format|
        format.html { render plain: 'Add an accept header "application/json" to the request.', content_type: 'text/plain', status: :bad_request }
        format.json do
          @result, status = search_variant

          if status == :ok && current_user.present? && !authorized?
            status = :forbidden
          end

          renderer = variant_params.key?(:pretty) ? :pretty_json : :json
          render renderer => @result, status: status
        end
      end
    end

    def gene
      search_action gene_params.to_h, SearchGene
    end

    def disease
      search_action disease_params.to_h, SearchDisease
    end

    def gene_annotation
      params = gene_annotation_params
      query = params[:query] || params[:q]
      return render plain: 'Query parameter is required', status: :bad_request unless query.present?

      chr, region = query.split(':')
      chr.delete_prefix!('chr')
      start, stop = region&.split('-')
      return render plain: 'Invalid query format', status: :bad_request unless chr.present? && start.present? && stop.present?

      response.headers['Content-Type'] = 'text/tab-separated-values; charset=utf-8'
      response.headers["Cache-Control"] = "no-cache"
      response.headers["X-Accel-Buffering"] = "no"
      response.headers["Last-Modified"] = Time.now.httpdate

      base = ENV.fetch('TOGOVAR_GENE_ANNOTATION_BASE')
      file = "chr#{chr}_molecular_annotation.tsv.gz"
      command = %W[tabix #{base}/#{file} #{chr}:#{start}-#{stop}]

      Open3.popen3(*command) do |stdin, stdout, stderr, wait_thr|
        stdin.close

        stderr_thread = Thread.new do
          stderr.each_line do |line|
            Rails.logger.error(line.chomp)
          end
        end

        stdout.each_line do |line|
          response.stream.write(line)
        end

        stderr_thread.join

        status = wait_thr.value

        Rails.logger.warn("Command failed: #{status.exitstatus}") unless status.success?
      end
    rescue ActionController::Live::ClientDisconnected, IOError
      Rails.logger.info("Client disconnected")
    ensure
      response.stream.close
    end

    def export
      chromosome = params[:chromosome] || raise('Missing chromosome parameter')

      response.headers['Content-Type'] = 'text/plain; charset=utf-8'

      all = Variant.count(body: { query: { match: { chromosome: } } })
      processed = 0

      search_after = nil

      loop do
        t = Benchmark.realtime do
          service = VariantExportService.new(chromosome:, search_after:)

          result, status = execute(service)

          raise "Variant export failed" unless status == :ok

          if result['data'].empty?
            Rails.logger.debug { "Variant search returned empty result." }
            break
          end

          result['data'].each do |variant|
            response.stream.write("chr#{variant['chromosome']}\t#{variant['position']}\t#{variant.to_json}\n")
          end

          search_after = result['data'].last

          processed += result['data'].size
        end

        break if t.nil?

        Rails.logger.debug do
          "Processed #{ActiveSupport::NumberHelper.number_to_delimited(processed)}/"\
            "#{ActiveSupport::NumberHelper.number_to_delimited(all)} "\
            "(#{ActiveSupport::Duration.build(t.round(2)).inspect})"
        end
      end
    ensure
      response.stream.close
    end

    private

    module BackwardCompatibility
      def variant_params
        return super unless request.get?

        return @variant_params if @variant_params

        @variant_params = params.permit :term, :quality, :limit, :offset, :stat, :data, :debug, :expand_dataset,
                                        dataset: {}, frequency: {}, type: {}, significance: {}, consequence: {},
                                        sscv_db: {}, sift: {}, polyphen: {}, alphamissense: {}, cadd_phred: {}

        if (position_offset = params.permit(offset: [])).present?
          @variant_params.merge!(position_offset)
        end

        @variant_params
      end

      # @return [Array] [result, status]
      def search_variant
        return super unless request.get?

        params = variant_params

        service = VariantSearchService::Query.new(params.to_h, debug: params.key?(:debug), user: current_user)

        execute(service).tap { |r, _| r.update(debug: service.debug) if params.key?(:debug) }
      end
    end
    prepend BackwardCompatibility

    def variant_params
      return @variant_params if @variant_params

      hash = params.permit(:data, :debug, :formatter, :limit, :offset, :pretty, :stat, :version, body: {}, query: {})
      if (offset = params.permit(offset: [])[:offset]).present?
        hash.merge!(offset: offset)
      end
      hash[:stat] = Integer(hash[:stat]) if hash[:stat].present?
      hash[:data] = Integer(hash[:data]) if hash[:data].present?

      hash
    end

    # @return [Array] [result, status]
    def search_variant
      params = variant_params

      service = VariantSearchService.new(params.to_h, headers: request_headers, debug: params.key?(:debug), user: current_user)

      execute(service).tap { |r, _| r.update(debug: service.debug) if params.key?(:debug) }
    end

    def gene_params
      params.permit(:pretty, :term, body: {})
    end

    def disease_params
      params.permit(:pretty, :term, body: {})
    end

    def gene_annotation_params
      params.permit(:query, :q)
    end

    def search_action(params, action)
      respond_to do |format|
        format.html { render plain: 'Add an accept header "application/json" to the request.', content_type: 'text/plain', status: :bad_request }
        format.json do
          renderer = params.key?(:pretty) ? :pretty_json : :json

          action = action.run(params)
          if action.valid?
            render renderer => action.result
          else
            render renderer => { errors: action.errors.full_messages }, status: :bad_request
          end
        end
      end
    rescue StandardError => e
      Rails.logger.error(self.class) { e }
      render json: { errors: ['Internal server error'] }, status: :internal_server_error
    end
  end
end
