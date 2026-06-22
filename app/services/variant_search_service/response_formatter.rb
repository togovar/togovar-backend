class VariantSearchService
  class ResponseFormatter
    XREF_TEMPLATE = Rails.application.config.application[:xref]

    MAX_GENES_SIZE = 5

    def initialize(param, result, error = [], warning = [], notice = [], **options)
      @param = param
      @result = result.deep_symbolize_keys
      @error = error
      @warning = warning
      @notice = notice
      @options = options.dup
    end

    def to_hash
      JSON.parse(to_json.target!)
    end

    def to_json(*)
      Jbuilder.new do |json|
        unless @param[:formatter] == 'jogo'
          scroll(json)
          statistics(json) if @result.key?(:aggs)
        end
        data(json) if @result.key?(:results)

        json.error @error if @error.present?
        json.warning @warning if @warning.present?
        json.notice @notice if @notice.present?
      end
    end

    private

    def accessible_datasets
      @accessible_datasets ||= Variant.all_datasets(@options[:user], groups: @param[:expand_dataset], resolve_alias: true)
    end

    def datasets_aliases
      @datasets_aliases ||= Variant.aliases(@options[:user], groups: @param[:expand_dataset])
    end

    def scroll(json)
      json.scroll do
        json.offset @param[:offset] || 0
        json.limit @param[:limit] || 100
        json.max_rows 10_000
      end
    end

    def statistics(json)
      json.statistics do
        json.total @result[:total]
        json.filtered @result[:filtered]

        if @result[:aggs].present?
          dataset(json)
          type(json)
          significance(json)
          consequence(json)
        end
      end
    end

    def dataset(json)
      aggs = @result[:aggs]
      datasets = Array(aggs.dig(:frequency, :source, :buckets)).concat(Array(aggs.dig(:conditions, :source, :buckets)))

      # Ensure dataset key
      (all = Variant.all_datasets(@options[:user])).each do |x|
        key = x.to_s
        datasets << { key:, doc_count: 0 } unless datasets.find { |dataset| dataset[:key] == key }
      end

      datasets.each do |dataset|
        if (aliases = datasets_aliases[dataset[:key]])
          aliases.each do |target|
            datasets.find { |x| x[:key] == target }&.update(doc_count: dataset[:doc_count])
          end
        end
      end

      json.dataset do
        datasets.each do |dataset|
          json.set! dataset[:key], dataset[:doc_count] if all.include?(dataset[:key].to_sym)
        end
      end
    end

    def type(json)
      types = Array(@result[:aggs].dig(:type, :buckets))

      # Ensure type key
      SequenceOntology::VariantClass.constants.each do |sym|
        next unless (label = SequenceOntology::VariantClass.const_get(sym)&.label)
        types << { key: label.to_s, doc_count: 0 } unless types.find { |type| type[:key] == label.to_s }
      end

      json.type do
        types.each do |x|
          json.set! SequenceOntology.find_by_label(x[:key])&.id, x[:doc_count]
        end
      end
    end

    def significance(json)
      significances = Array(@result[:aggs].dig(:conditions, :condition, :classification, :buckets))

      # Ensure significance key
      QueryParameters::ClinicalSignificance.all.each do |c|
        significances << { key: c.id.to_s, doc_count: 0 } unless significances.find { |x| x[:key] == c.id.to_s }
      end

      json.significance do
        significances.each do |x|
          if (s = QueryParameters::ClinicalSignificance.find_by_id(x[:key]))
            json.set! s.key, x[:doc_count]
          end
        end

        json.set! 'NA', (c = @result[:count_condition_absence])&.positive? ? c : 0
      end
    end

    def consequence(json)
      consequences = Array(@result[:aggs].dig(:consequence, :buckets))

      # Ensure consequence key
      SequenceOntology::CONSEQUENCES_IN_ORDER.map(&:key).each do |key|
        consequences << { key: key.to_s, doc_count: 0 } unless consequences.find { |x| x[:key] == key.to_s }
      end

      json.consequence do
        consequences.each do |x|
          if (c = SequenceOntology.find_by_key(x[:key]))
            json.set! c.id, x[:doc_count]
          end
        end
      end
    end

    def data(json)
      # use raw_response for performance
      results = if @param[:formatter] == 'jogo'
                  @result[:results]
                else
                  @result[:results].response.raw_response['hits']['hits']
                end

      json.data results do |result|
        variant = result['_source'].deep_symbolize_keys

        if (tgv = variant[:id]).present?
          json.id "tgv#{tgv}"
        end

        json.sv variant[:sv]
        json.type SequenceOntology.find_by_label(variant[:type])&.id
        json.chromosome variant[:chromosome]
        json.position variant[:position_start]
        json.reference variant[:reference]
        json.alternate variant[:alternate]

        if (dbsnp = Array(variant[:xref]).filter { |x| x[:source] = 'dbSNP' }.map { |x| x[:id] }).present?
          json.existing_variations dbsnp
        end

        if (external_link = cross_references(variant, dbsnp)).present?
          json.external_links external_link
        end

        if variant.key?(:pubmed)
          json.pubmed variant[:pubmed]
        end

        json.genes gene_symbols(variant)

        if variant.key?(:conditions)
          json.conditions conditions(variant)
        end

        json.most_severe_consequence SequenceOntology.find_by_key(variant[:most_severe_consequence])&.id
        json.sift variant[:sift] if variant[:sift]
        json.polyphen(variant[:polyphen].negative? ? 'Unknown' : variant[:polyphen]) if variant[:polyphen]
        json.alphamissense variant[:alphamissense] if variant[:alphamissense]
        json.cadd_phred variant[:cadd_phred] if variant[:cadd_phred]

        if variant[:sscv_db]
          json.sscv_db sscv_db(variant)
        end

        if variant.key?(:vep) && variant[:gene].present? && variant[:gene].size <= MAX_GENES_SIZE
          json.transcripts vep(variant)
        end

        if variant.key?(:frequency)
          json.frequencies frequencies(variant)
        end
      end
    end

    MEDGEN_IGNORE = %w[C3661900 CN169374]

    MEDGEN_COMPARATOR = proc do |a, b|
      next MEDGEN_IGNORE.find_index(a) <=> MEDGEN_IGNORE.find_index(b) if [a, b].all? { |x| MEDGEN_IGNORE.include?(x) }
      next 1 if MEDGEN_IGNORE.include?(a)
      next -1 if MEDGEN_IGNORE.include?(b)
      0
    end

    CONDITIONS_COMPARATOR = proc do |a, b|
      if (r = QueryParameters::ClinicalSignificance.index_of(a.dig(:interpretations, 0)) <=>
              QueryParameters::ClinicalSignificance.index_of(b.dig(:interpretations, 0))) && !r.zero?
        next r
      end

      if (r = b[:submission_count] <=> a[:submission_count]) && !r.zero?
        next r
      end

      m1 = a.dig(:conditions, 0, :medgen)
      m2 = b.dig(:conditions, 0, :medgen)
      next MEDGEN_IGNORE.find_index(m1) <=> MEDGEN_IGNORE.find_index(m2) if [m1, m2].all? { |x| MEDGEN_IGNORE.include?(x) }
      next 1 if m1.present? && MEDGEN_IGNORE.include?(m1)
      next -1 if m2.present? && MEDGEN_IGNORE.include?(m2)

      b[:conditions]&.filter_map { |x| x[:medgen] }&.flatten&.size <=> a[:conditions]&.filter_map { |x| x[:medgen] }&.flatten&.size || 0
    end

    private

    def cross_references(variant, dbsnp)
      chromosome = variant[:chromosome]
      position = variant[:position_start]
      reference = variant[:reference]
      alternate = variant[:alternate]

      external_link = {}

      if dbsnp.present?
        external_link[:dbsnp] = dbsnp.map { |x| { title: x, xref: format(XREF_TEMPLATE[:dbsnp], id: x) } }
      end

      if (id = variant[:conditions]&.find { |x| x[:source] == 'clinvar' }&.dig(:id)).present?
        external_link[:clinvar] = [{ title: 'VCV%09d' % id, xref: format(XREF_TEMPLATE[:clinvar], id: id) }]
      end

      if (id = variant[:conditions]&.find { |x| x[:source] == 'mgend' }&.dig(:id)).present?
        external_link[:mgend] = [{ title: id, xref: format(XREF_TEMPLATE[:mgend], id: id) }]
      end

      if variant[:frequency]&.find { |x| x[:source] == 'tommo' }
        query = "#{chromosome}:#{position}"
        xref = "#{XREF_TEMPLATE[:tommo]}?#{URI.encode_www_form(query: query)}"
        external_link[:tommo] = [{ title: query, xref: }]
      end

      if variant[:frequency]&.find { |x| x[:source] =~ /^gnomad_(genomes|exomes)$/ }
        id = "#{chromosome}-#{position}-#{reference}-#{alternate}"
        external_link[:gnomad] = [{ title: id, xref: format(XREF_TEMPLATE[:gnomad], id:) }]
      end

      if (v = variant[:frequency]&.find { |x| x[:source] == 'jogo' })
        chr, start, stop = v[:id].split(':', 3)
        if chr && start && stop
          external_link[:jogo] = [{ title: "#{chr}:#{start}-#{stop}", xref: format(XREF_TEMPLATE[:jogo], chr:, start:, stop:) }]
        end
      end

      if (v = variant[:frequency]&.find { |x| x[:source] == 'gnomad_sv' })
        if (id = v[:id])
          external_link[:gnomad_sv] = [{ title: id, xref: format(XREF_TEMPLATE[:gnomad_sv], id:) }]
        end
      end

      if variant[:sscv_db].present?
        Array(variant[:sscv_db]).each do |x|
          next if x[:variant_id].blank? || x[:gene_id].blank?

          id = "#{x[:variant_id]}@#{x[:gene_id]}"
          external_link[:sscv_db] = [{ title: id, xref: format(XREF_TEMPLATE[:sscv_db], id:) }]
        end
      end

      external_link
    end

    def gene_symbols(variant)
      items = if variant[:gene].present?
                if variant[:gene].size <= MAX_GENES_SIZE
                  gene_comparator = Gene.id_comparator(@options[:gene_order])

                  Array(variant[:gene]).map { |x| { name: x[:label], id: x[:id], synonyms: Gene.synonyms(x[:id]) }.compact }
                                       .sort(&gene_comparator)
                else
                  if @options[:gene_order].present?
                    query_gene_symbol
                  else
                    []
                  end
                end
              else
                []
              end

      {
        total: variant[:gene]&.size || 0,
        items: items.presence
      }.compact
    end

    def query_gene_symbol
      @query_gene_symbol ||= begin
                               @options[:gene_order].map do |id|
                                 gene = Gene.find(id)
                                 synonyms = Gene.synonyms(id)

                                 { name: gene[:symbol], id: gene[:hgnc_id], synonyms: }.compact
                               end
                             end
    end

    def sscv_db(variant)
      Array(variant[:sscv_db]).filter_map do |x|
        next if x[:variant_id].blank? || x[:gene_id].blank? || x[:predicted_splicing_type].blank?

        {
          variant: "#{x[:variant_id]}@#{x[:gene_id]}",
          predicted_splicing_type: x[:predicted_splicing_type].gsub('_', ' ')
        }
      end
    end

    def conditions(variant)
      @conditions ||= Hash.new { |hash, key| hash[key] = Disease.find(key)&.[](:name) }

      Array(variant[:conditions]).flat_map do |condition|
        (condition[:condition].presence || [{}]).map do |x|
          {
            conditions: if x[:medgen].present?
                          Array(x[:medgen]).sort(&MEDGEN_COMPARATOR)
                                           .map { |v| { name: @conditions[v] || QueryParameters::ClinicalSignificance::LABEL_NOT_PROVIDED, medgen: v } }
                        elsif x[:pref_name].present?
                          Array(x[:pref_name]).map { |v| { name: v } }
                        else
                          []
                        end,
            interpretations: Array(x[:classification]).filter_map { |y| QueryParameters::ClinicalSignificance.find_by_id(y)&.key },
            submission_count: x[:submission_count],
            source: condition[:source]
          }.compact
        end
      end.sort(&CONDITIONS_COMPARATOR)
    end

    def vep(variant)
      vep = Array(variant[:vep]).reject { |x| x[:consequence_type] == 'regulatory_feature_consequence' }
                                .map(&:compact)

      vep.each do |x|
        consequences = x[:consequence].map { |key| SequenceOntology.find_by_key(key) }
        x[:consequence] = (SequenceOntology::CONSEQUENCES_IN_ORDER & consequences).map { |y| y.id }
      end

      vep
    end

    def frequencies(variant)
      frequencies = []

      Array(variant[:frequency]).each do |x|
        x.delete(:id)

        if (m = x[:source].match(/^(bbj_riken\.mpheno\d+)\.all$/))
          x[:source] = m[1]
        end

        next unless accessible_datasets.include?(x[:source].to_sym)

        if x[:af].blank? && x[:ac].present? && x[:an].present?
          x[:af] = Float(x[:ac]) / Float(x[:an])
        end

        x = x.compact.sort.to_h

        frequencies << x

        if (aliases = datasets_aliases[x[:source]])
          aliases.each do |target|
            frequencies << x.merge(source: target)
          end
        end
      end

      frequencies
    end
  end
end
