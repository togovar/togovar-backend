class VariantSearchService
  class QueryBuilder
    include Elasticsearch::DSL

    attr_accessor :from
    attr_accessor :size

    def initialize(**options)
      @from = 0
      @size = 100
      @sort = true
      @options = options
    end

    module Regex
      SEP_VARIANT = /[:-]/.freeze
      SEP_RANGE = /-/.freeze
      SEP_ALLELE_CHANGE = /[>-]/.freeze
      CHROMOSOME = /(chr)?(?<chr>[1-9]|1[0-9]|2[0-2]|[XY]|MT?)/.freeze
      POSITION = /(?<pos>\d+)/.freeze
      REGION_FROM = /(?<from>\d+)/.freeze
      REGION_TO = /(?<to>\d+)/.freeze
      REFERENCE = /(?<ref>[a-zA-Z]+)/.freeze
      ALTERNATE = /(?<alt>[a-zA-Z]+)/.freeze

      REGEXP_TOGOVAR_ID = /^tgv\d+$/.freeze
      REGEXP_DBSNP_ID = /^rs\d+$/.freeze
      REGEXP_VARIANT_POSITION = /^#{CHROMOSOME}#{SEP_VARIANT}#{POSITION}(#{SEP_VARIANT}#{REFERENCE}(#{SEP_ALLELE_CHANGE}#{ALTERNATE})?)?$/.freeze
      REGEXP_VARIANT_REGION = /^#{CHROMOSOME}#{SEP_VARIANT}#{REGION_FROM}#{SEP_RANGE}#{REGION_TO}(#{SEP_VARIANT}#{REFERENCE}(#{SEP_ALLELE_CHANGE}#{ALTERNATE})?)?$/.freeze
    end

    def term(term)
      @term_condition = nil

      return self if term.blank?

      inputs = CSV.parse_line(term, col_sep: ' ') || []

      queries = []

      if inputs.any? { |x| x.match?(Regex::REGEXP_TOGOVAR_ID) }
        queries << tgv_condition(inputs.filter { |x| x.match?(Regex::REGEXP_TOGOVAR_ID) })
        inputs.delete_if { |x| x.match?(Regex::REGEXP_TOGOVAR_ID) }
      end

      if inputs.any? { |x| x.match?(Regex::REGEXP_DBSNP_ID) }
        queries << rs_condition(inputs.filter { |x| x.match?(Regex::REGEXP_DBSNP_ID) })
        inputs.delete_if { |x| x.match?(Regex::REGEXP_DBSNP_ID) }
      end

      inputs.each do |x|
        queries << if (m = x.match(Regex::REGEXP_VARIANT_POSITION))
                     region_condition(m[:chr], m[:pos], m[:pos], m[:ref], m[:alt])
                   elsif (m = x.match(Regex::REGEXP_VARIANT_REGION))
                     region_condition(m[:chr], m[:from], m[:to], m[:ref], m[:alt])
                   elsif (gene = Gene.exact_match(x))
                     gene_condition(gene[:hgnc_id])
                   else
                     disease_condition(x)
                   end
      end

      @term_condition = if queries.size > 1
                          {
                            bool: {
                              should: queries
                            }
                          }
                        else
                          queries[0]
                        end

      self
    end

    def dataset(datasets)
      @dataset_condition = nil

      user = @options[:user]
      filter = @options[:filter]

      return self if (datasets & Variant.all_datasets(user)).empty?

      frequency_datasets = datasets & Variant.frequency_datasets(user)
      filter_datasets = Variant.frequency_datasets(user, filter: true)
      non_filter_datasets = Variant.frequency_datasets(user, filter: false)

      q1 = if frequency_datasets.present?
             Elasticsearch::DSL::Search.search do
               query do
                 bool do
                   should do
                     bool do
                       filter do
                         nested do
                           path :frequency
                           query do
                             terms 'frequency.source': frequency_datasets
                           end
                         end
                       end
                       if filter && (filter_datasets.present? || non_filter_datasets.present?)
                         filter do
                           bool do
                             if filter_datasets.present?
                               should do
                                 nested do
                                   path :frequency
                                   query do
                                     bool do
                                       filter do
                                         terms 'frequency.source': Variant.resolve_alias(user, filter_datasets)
                                       end
                                       filter do
                                         term 'frequency.filter': 'PASS'
                                       end
                                     end
                                   end
                                 end
                               end
                             end
                             if non_filter_datasets.present?
                               should do
                                 terms 'frequency.source': Variant.resolve_alias(user, non_filter_datasets)
                               end
                             end
                           end
                         end
                       end
                     end
                   end
                 end
               end
             end.to_hash.dig(:query, :bool, :should, 0)
           end

      q2 = if (v = datasets & Variant.condition_datasets(user)).present?
             Elasticsearch::DSL::Search.search do
               query do
                 bool do
                   should do
                     nested do
                       path :conditions
                       query do
                         terms 'conditions.source': v
                       end
                     end
                   end
                 end
               end
             end.to_hash.dig(:query, :bool, :should, 0)
           end

      @dataset_condition = Elasticsearch::DSL::Search.search do
        query do
          bool do
            should(q1) if q1
            should(q2) if q2
            minimum_should_match 1
          end
        end
      end.to_hash[:query]

      self
    end

    def frequency(datasets, frequency_from, frequency_to, invert = false, all_datasets = false)
      @frequency_condition = nil

      sources = datasets & Variant.frequency_datasets(@options[:user])

      return self if sources.empty?

      @frequency_condition = Elasticsearch::DSL::Search.search do
        query do
          bool do
            sources.each do |source|
              send(all_datasets ? :filter : :should) do
                nested do
                  path :frequency
                  query do
                    bool do
                      filter({ match: { 'frequency.source': source } })
                      if invert
                        filter do
                          bool do
                            must_not do
                              range 'frequency.af' do
                                gte frequency_from.to_f
                                lte frequency_to.to_f
                              end
                            end
                          end
                        end
                      else
                        filter do
                          range 'frequency.af' do
                            gte frequency_from.to_f
                            lte frequency_to.to_f
                          end
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end.to_hash[:query]

      self
    end

    def type(*values)
      @type_condition = nil

      type = values.filter_map { |x| QueryParameters::Type.find_by_key(x)&.id }

      return self if type.empty?

      @type_condition = Elasticsearch::DSL::Search.search do
        query do
          terms type:
        end
      end.to_hash[:query]

      self
    end

    def significance(*values)
      @significance_condition = nil

      interpretations = values.filter_map { |x| QueryParameters::ClinicalSignificance.find_by_key(x)&.id }
      not_available = interpretations.delete('not_available')

      return self if !not_available && interpretations.blank?

      @significance_condition = Elasticsearch::DSL::Search.search do
        query do
          bool do
            if interpretations.present?
              should do
                nested do
                  path 'conditions.condition'
                  query do
                    terms 'conditions.condition.classification': interpretations
                  end
                end
              end
            end
            if not_available
              should do
                bool do
                  must_not do
                    nested do
                      path 'conditions'
                      query do
                        exists field: 'conditions'
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end.to_hash[:query]

      self
    end

    def consequence(*values)
      @consequence_condition = nil

      consequence = values.filter_map { |x| QueryParameters::Consequence.find_by_key(x)&.id }

      return self if consequence.empty?

      @consequence_condition = Elasticsearch::DSL::Search.search do
        query do
          terms 'vep.consequence': consequence
        end
      end.to_hash[:query]

      self
    end

    def sscv_db(*values)
      @sscv_db_condition = nil

      values &= QueryParameters::SscvDb.parameters

      return self if values.empty?

      without_annotation = values.delete(:NA)

      values = values.map { |x| QueryParameters::SscvDb.find_by_key(x)&.id }
                     .compact

      @sscv_db_condition = Elasticsearch::DSL::Search.search do
        query do
          bool do
            if without_annotation
              should do
                bool do
                  must_not do
                    nested do
                      path 'sscv_db'
                      query do
                        exists field: 'sscv_db'
                      end
                    end
                  end
                end
              end
            end
            if values.present?
              should do
                nested do
                  path :sscv_db
                  query do
                    terms 'sscv_db.predicted_splicing_type': values
                  end
                end
              end
            end
          end
        end
      end.to_hash[:query]

      self
    end

    def sift(*values)
      @sift_condition = nil

      values &= QueryParameters::Sift.parameters

      return self if values.empty?

      @sift_condition = Elasticsearch::DSL::Search.search do
        query do
          bool do
            values.each do |x|
              should do
                if x == :NA
                  bool do
                    must_not do
                      exists field: 'sift'
                    end
                  end
                else
                  range 'sift' do
                    if x == :D
                      lt 0.05
                    else
                      gte 0.05
                    end
                  end
                end
              end
            end
          end
        end
      end.to_hash[:query]

      self
    end

    def polyphen(*values)
      @polyphen_condition = nil

      values &= QueryParameters::Polyphen.parameters

      return self if values.empty?

      @polyphen_condition = Elasticsearch::DSL::Search.search do
        query do
          bool do
            values.each do |x|
              should do
                if x == :NA
                  bool do
                    must_not do
                      exists field: 'polyphen'
                    end
                  end
                else
                  range 'polyphen' do
                    case x
                    when :B
                      gte 0
                      lte 0.446
                    when :POSSD
                      gt 0.446
                      lte 0.908
                    when :PROBD
                      gt 0.908
                    else
                      lt 0
                    end
                  end
                end
              end
            end
          end
        end
      end.to_hash[:query]

      self
    end

    def alphamissense(*values)
      @alphamissense_condition = nil

      values &= QueryParameters::AlphaMissense.parameters

      return self if values.empty?

      @alphamissense_condition = Elasticsearch::DSL::Search.search do
        query do
          bool do
            values.each do |x|
              should do
                if x == :NA
                  bool do
                    must_not do
                      exists field: 'alphamissense'
                    end
                  end
                else
                  range 'alphamissense' do
                    case x
                    when :LB
                      gte 0
                      lt 0.34
                    when :A
                      gte 0.34
                      lte 0.564
                    else
                      gt 0.564
                    end
                  end
                end
              end
            end
          end
        end
      end.to_hash[:query]

      self
    end

    def cadd_phred(*values)
      @cadd_phred_condition = nil

      values &= QueryParameters::CaddPhred.parameters

      return self if values.empty?

      @cadd_phred_condition = Elasticsearch::DSL::Search.search do
        query do
          bool do
            values.each do |x|
              should do
                if x == :NA
                  bool do
                    must_not do
                      exists field: 'cadd_phred'
                    end
                  end
                else
                  range 'cadd_phred' do
                    case x
                    when :P0
                      lt 10
                    when :P10
                      gte 10
                      lt 20
                    else
                      gte 20
                    end
                  end
                end
              end
            end
          end
        end
      end.to_hash[:query]

      self
    end

    def limit(size)
      @size = size
      self
    end

    def sort(bool)
      @sort = !!bool
      self
    end

    def stat_query
      query = build

      query[:size] = 0
      query.delete(:from)
      query.delete(:sort)
      query.delete(:search_after)

      query.merge(Variant::QueryHelper.statistics(@options[:user]))
    end

    def build
      conditions = []

      conditions << Variant.default_condition
      conditions << @term_condition
      conditions << @dataset_condition
      conditions << @frequency_condition
      conditions << @type_condition
      conditions << @significance_condition
      conditions << @consequence_condition
      conditions << @sscv_db_condition
      conditions << @sift_condition
      conditions << @polyphen_condition
      conditions << @alphamissense_condition
      conditions << @cadd_phred_condition

      conditions.compact!

      query = if conditions.size == 1
                { query: conditions.first }
              else
                { query: { bool: { filter: conditions } } }
              end

      query[:size] = @size
      if @from.is_a?(Array)
        query[:search_after] = [@from[0].to_i, @from[1].to_i, @from[2].to_s, @from[3].to_s]
      else
        query[:from] = @from unless @from.zero?
      end
      query[:sort] = %w[chromosome_index position_start reference alternate] if @sort

      query
    end

    private

    def tgv_condition(term)
      query = Elasticsearch::DSL::Search.search do
        query do
          terms id: Array(term).map { |x| x.delete_prefix('tgv').to_i }
        end
      end

      query.to_hash[:query]
    end

    def rs_condition(term)
      query = Elasticsearch::DSL::Search.search do
        query do
          nested do
            path :xref
            query do
              bool do
                filter({ match: { 'xref.source': 'dbSNP' } })
                filter do
                  terms 'xref.id': Array(term)
                end
              end
            end
          end
        end
      end

      query.to_hash[:query]
    end

    def region_condition(chr, from, to, ref, alt)
      position = Elasticsearch::DSL::Search.search do
        query do
          bool do
            should do
              bool do
                filter do
                  range(:position_start) do
                    lte from.to_i
                  end
                end
                filter do
                  range(:position_end) do
                    gte to.to_i
                  end
                end
              end
            end
            should do
              bool do
                filter do
                  range(:position_start) { gte from.to_i }
                end
                filter do
                  range(:position_end) { lte to.to_i }
                end
              end
            end
            should do
              bool do
                filter do
                  range(:position_start) { lte from.to_i }
                end
                filter do
                  range(:position_end) do
                    gte from.to_i
                    lte to.to_i
                  end
                end
              end
            end
            should do
              bool do
                filter do
                  range(:position_start) do
                    gte from.to_i
                    lte to.to_i
                  end
                end
                filter do
                  range(:position_end) { gt from.to_i }
                end
              end
            end
          end
        end
      end.to_hash[:query]

      query = Elasticsearch::DSL::Search.search do
        query do
          bool do
            filter({ match: { chromosome: chr } })
            filter(position)
            filter({ match: { reference: ref } }) if ref.present?
            filter({ match: { alternate: alt } }) if alt.present?
          end
        end
      end

      query.to_hash[:query]
    end

    def gene_condition(term)
      query = Elasticsearch::DSL::Search.search do
        query do
          terms 'gene.id': Array(term)
        end
      end

      query.to_hash[:query]
    end

    def disease_condition(term)
      medgen = if (t = Disease.exact_match(term)).present?
                 [t[:id]]
               elsif (ts = Disease.condition_search(term)).present?
                 ts.map(&:id)
               else
                 []
               end

      query = Elasticsearch::DSL::Search.search do
        query do
          nested do
            path 'conditions.condition'
            query do
              terms 'conditions.condition.medgen': medgen
            end
          end
        end
      end

      query.to_hash[:query]
    end
  end
end
