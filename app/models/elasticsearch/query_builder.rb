module Elasticsearch
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

    def dataset(names, filter: true)
      @dataset_condition = nil

      return self if (names & Variation.all_datasets(@options[:user])).empty?

      query = Elasticsearch::DSL::Search.search do
        query do
          bool do
            if filter
              if (v = names & Variation.frequency_datasets(@options[:user], filter: true)).present?
                should do
                  nested do
                    path :frequency
                    query do
                      bool do
                        must do
                          terms 'frequency.source': v.map { |x| x == :jga_wes ? :jga_ngs : x } # TODO: remove if dataset renamed
                        end
                        must do
                          match 'frequency.filter': 'PASS'
                        end
                      end
                    end
                  end
                end
              end
              if (v = names & Variation.frequency_datasets(@options[:user], filter: false)).present?
                should do
                  nested do
                    path :frequency
                    query do
                      terms 'frequency.source': v.map { |x| x == :jga_wes ? :jga_ngs : x } # TODO: remove if dataset renamed
                    end
                  end
                end
              end
            else
              if (v = names & Variation.frequency_datasets(@options[:user])).present?
                should do
                  nested do
                    path :frequency
                    query do
                      terms 'frequency.source': v.map { |x| x == :jga_wes ? :jga_ngs : x } # TODO: remove if dataset renamed
                    end
                  end
                end
              end
            end

            if (v = names & Variation.condition_datasets(@options[:user])).present?
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
        end
      end.to_hash[:query]

      @dataset_condition = if query[:bool][:should].size == 1
                             query[:bool][:should].first
                           else
                             query
                           end

      self
    end

    def frequency(datasets, frequency_from, frequency_to, invert = false, all_datasets = false)
      @frequency_condition = nil

      sources = datasets & Variation.frequency_datasets(@options[:user])

      return self if sources.empty?

      @frequency_condition = Elasticsearch::DSL::Search.search do
        query do
          bool do
            sources.each do |source|
              # TODO: remove if dataset renamed
              source = :jga_ngs if source == :jga_wes

              send(all_datasets ? :must : :should) do
                nested do
                  path :frequency
                  query do
                    bool do
                      must { match 'frequency.source': source }
                      if invert
                        must do
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
                        must do
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

    def type(*keys)
      @type_condition = nil

      return self if keys.empty?

      @type_condition = Elasticsearch::DSL::Search.search do
        query do
          terms type: keys.map { |x| SequenceOntology.find(x)&.label }.compact
        end
      end.to_hash[:query]

      self
    end

    def significance(*values)
      @significance_condition = nil

      interpretations = values.filter_map { |x| ClinicalSignificance.find_by_key(x)&.label&.downcase.gsub(' ', '_') }

      return self if !values.include?(:NC) && interpretations.blank?

      @significance_condition = Elasticsearch::DSL::Search.search do
        query do
          bool do
            if values.include?(:NC)
              should do
                bool do
                  must_not do
                    exists field: :conditions
                  end
                end
              end
            end

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
          end
        end
      end.to_hash[:query]

      self
    end

    def consequence(*values)
      @consequence_condition = nil

      consequence = values.filter_map { |x| SequenceOntology.find(x)&.key }

      return self if consequence.empty?

      @consequence_condition = Elasticsearch::DSL::Search.search do
        query do
          nested do
            path :vep
            query do
              terms 'vep.consequence': consequence
            end
          end
        end
      end.to_hash[:query]

      self
    end

    def sift(*values)
      @sift_condition = nil

      values &= [:N, :D, :T]

      return self if values.empty?

      @sift_condition = Elasticsearch::DSL::Search.search do
        query do
          bool do
            values.each do |x|
              should do
                if x == :N
                  bool do
                    must_not do
                      exists do
                        field 'sift'
                      end
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

      values &= [:N, :PROBD, :POSSD, :B, :U]

      return self if values.empty?

      @polyphen_condition = Elasticsearch::DSL::Search.search do
        query do
          bool do
            values.each do |x|
              should do
                if x == :N
                  bool do
                    must_not do
                      exists do
                        field 'polyphen'
                      end
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

      values &= [:N, :LP, :A, :LB]

      return self if values.empty?

      @alphamissense_condition = Elasticsearch::DSL::Search.search do
        query do
          bool do
            values.each do |x|
              should do
                if x == :N
                  bool do
                    must_not do
                      exists do
                        field 'alphamissense'
                      end
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

      query.merge(Variation::QueryHelper.statistics(@options[:user]))
    end

    def build
      conditions = []

      conditions << default_condition
      conditions << @term_condition
      conditions << @dataset_condition
      conditions << @frequency_condition
      conditions << @type_condition
      conditions << @significance_condition
      conditions << @consequence_condition
      conditions << @sift_condition
      conditions << @polyphen_condition
      conditions << @alphamissense_condition

      conditions.compact!

      query = if conditions.size == 1
                { query: conditions.first }
              else
                { query: { bool: { must: conditions } } }
              end

      query[:size] = @size
      if @from.is_a?(Array)
        query[:search_after] = [@from[0].to_i, @from[1].to_i, @from[2].to_s, @from[3].to_s]
      else
        query[:from] = @from unless @from.zero?
      end
      query[:sort] = %w[chromosome.index vcf.position vcf.reference vcf.alternate] if @sort

      query
    end

    private

    def default_condition
      Variation.default_condition
    end

    def aggregations
      Elasticsearch::DSL::Search.search do
        aggregation :type do
          terms field: :type, size: Variation.cardinality[:types]
        end

        aggregation :vep do
          nested do
            path :vep
            aggregation :consequence do
              terms field: 'vep.consequence', size: Variation.cardinality[:vep_consequences]
            end
          end
        end

        aggregation :conditions_condition do
          nested do
            path 'conditions.condition'
            aggregation :classification do
              terms field: 'conditions.condition.classification',
                    size: Variation.cardinality[:condition_classifications]
            end
          end
        end

        aggregation :frequency do
          nested do
            path :frequency
            aggregation :source do
              terms field: 'frequency.source', size: Variation.cardinality[:frequency_sources]
            end
          end
        end

        aggregation :condition do
          nested do
            path :condition
            aggregation :source do
              terms field: 'conditions.source', size: Variation.cardinality[:condition_sources]
            end
          end
        end
      end
    end

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
                must do
                  match 'xref.source': 'dbSNP'
                end
                must do
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
      query = Elasticsearch::DSL::Search.search do
        query do
          bool do
            must { match 'chromosome.label': chr }
            must do
              bool do
                # TODO: use position.left and position.right
                should do
                  bool do
                    must { range(:start) { lte from.to_i } }
                    must { range(:stop) { gte to.to_i } }
                  end
                end
                should do
                  bool do
                    must { range(:start) { gte from.to_i } }
                    must { range(:stop) { lte to.to_i } }
                  end
                end
                should do
                  bool do
                    must { range(:start) { lte from.to_i } }
                    must do
                      range(:stop) do
                        gte from.to_i
                        lte to.to_i
                      end
                    end
                  end
                end
                should do
                  bool do
                    must do
                      range(:start) do
                        gte from.to_i
                        lte to.to_i
                      end
                    end
                    must { range(:stop) { gt from.to_i } }
                  end
                end
              end
            end
            must { match reference: ref } if ref.present?
            must { match alternate: alt } if alt.present?
          end
        end
      end

      query.to_hash[:query]
    end

    def gene_condition(term)
      query = Elasticsearch::DSL::Search.search do
        query do
          bool do
            must do
              nested do
                path 'vep'
                query do
                  terms 'vep.hgnc_id': Array(term)
                end
              end
            end
            must do
              nested do
                path :'vep.symbol'
                query do
                  terms 'vep.symbol.source': %w[HGNC EntrezGene]
                end
              end
            end
          end
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
