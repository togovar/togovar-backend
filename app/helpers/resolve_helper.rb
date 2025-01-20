module ResolveHelper
  def search_by_vcf_representation(chr, pos, ref, alt)
    query = Elasticsearch::DSL::Search.search do
      query do
        bool do
          must do
            match 'chromosome.label': chr.to_s
          end
          must do
            match 'vcf.position': pos.to_i
          end
          must do
            match 'vcf.reference': ref.to_s
          end
          must do
            match 'vcf.alternate': alt.to_s
          end
        end
      end
    end

    Variation.search(query).results
  end

  def search_by_rs(id)
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
                match 'xref.id': id
              end
            end
          end
        end
      end
    end

    Variation.search(query).results
  end

  def find_by_symbol(symbol)
    query = Elasticsearch::DSL::Search.search do
      query do
        match symbol: symbol
      end
    end

    Gene.search(query).results.first
  end
end
