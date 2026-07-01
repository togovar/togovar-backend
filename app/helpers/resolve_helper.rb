module ResolveHelper
  def search_by_vcf_representation(chr, pos, ref, alt)
    query = Elasticsearch::DSL::Search.search do
      query do
        bool do
          filter({ match: { chromosome: chr.to_s } })
          filter({ match: { position_start: pos.to_i } })
          filter({ match: { reference: ref.to_s } })
          filter({ match: { alternate: alt.to_s } })
        end
      end
    end

    Variant.search(query).results
  end

  def search_by_rs(id)
    query = Elasticsearch::DSL::Search.search do
      query do
        nested do
          path :xref
          query do
            bool do
              filter({ match: { 'xref.source': 'dbSNP' } })
              filter({ match: { 'xref.id': id } })
            end
          end
        end
      end
    end

    Variant.search(query).results
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
