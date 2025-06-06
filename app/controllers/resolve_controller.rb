class ResolveController < ApplicationController
  def variant
    respond_to do |format|
      format.html do
        if /^tgv/.match?(params[:id])
          redirect_to '/400.html'
          return
        end

        result = resolve_variant

        if result.size == 1 && result[0].present?
          redirect_to "/variant/#{result[0]}"
        else
          redirect_to "/?#{search_query_parameters}", status: :see_other
        end
      rescue StandardError
        redirect_to '/500.html', status: :internal_server_error
      end

      format.json do
        result = resolve_variant.compact_blank

        status = if result.size.zero?
                   :not_found
                 else
                   :ok
                 end

        render json: { query: params[:id], result: }, status:
      rescue StandardError => e
        render json: { error: e.message }, status: :internal_server_error
      end
    end
  end

  def gene
    respond_to do |format|
      format.html do
        if /^[1-9][0-9]*$/.match?(params[:id])
          redirect_to '/400.html'
          return
        end

        result = resolve_gene

        if result.present?
          redirect_to "/gene/#{result}"
        else
          redirect_to '/404.html'
        end
      rescue StandardError
        redirect_to '/500.html', status: :internal_server_error
      end

      format.json do
        result = resolve_gene
        status = if result.present?
                   :ok
                 else
                   :not_found
                 end

        render json: { query: params[:id], result: }, status:
      rescue StandardError => e
        render json: { error: e.message }, status: :internal_server_error
      end
    end
  end

  def disease
    respond_to do |format|
      format.html do
        if /^[CN]*\d{4,7}$/.match?(params[:id])
          redirect_to '/400.html'
          return
        end

        redirect_to '/404.html'
      rescue StandardError
        redirect_to '/500.html', status: :internal_server_error
      end

      format.json do
        result = resolve_disease
        status = if result.present?
                   :ok
                 else
                   :not_found
                 end

        render json: { query: params[:id], result: }, status:
      rescue StandardError => e
        render json: { error: e.message }, status: :internal_server_error
      end
    end
  end

  private

  def search_query_parameters
    URI.encode_www_form(mode: 'simple', term: params[:id])
  end

  def resolve_variant
    case params[:id]
    when /^tgv/
      [params[:id]]
    when /^rs/
      view_context.search_by_rs(params[:id]).map do |x|
        id = x.dig('_source', 'id')
        "tgv#{id}" if id.present?
      end
    when /^(chr)?(?<chr>[1-9]|1[0-9]|2[0-2]|X|Y|MT?)-(?<pos>\d+)-(?<ref>.+)-(?<alt>.+)/
      chr = $LAST_MATCH_INFO['chr']
      chr = 'MT' if chr == 'M'
      pos = $LAST_MATCH_INFO['pos']
      ref = $LAST_MATCH_INFO['ref']
      alt = $LAST_MATCH_INFO['alt']

      view_context.search_by_vcf_representation(chr, pos, ref, alt).map do |x|
        id = x.dig('_source', 'id')
        "tgv#{id}" if id.present?
      end
    else
      query = request.fullpath.delete_prefix('/variant/')
      hgvs = HGVS.new(query)

      return [] unless hgvs.match?(query)

      result = hgvs.resolve

      raise hgvs.translate_error if hgvs.translate_error.present?

      return [] unless result.first.present?

      chr, pos, ref, alt = result.first.split('-')

      return [] unless [chr, pos, ref, alt].all?

      view_context.search_by_vcf_representation(chr, pos, ref, alt).map do |x|
        id = x.dig('_source', 'id')
        "tgv#{id}" if id.present?
      end
    end
  end

  def resolve_gene
    return if params[:id].blank?

    case params[:id]
    when /^[1-9][0-9]*$/
      params[:id].to_i
    else
      view_context.find_by_symbol(params[:id])&.dig('_source', 'hgnc_id')&.to_i
    end
  end

  def resolve_disease
    return if params[:id].blank?

    if /^CN?[1-9][0-9]*$/.match?(params[:id])
      params[:id]
    end
  end
end
