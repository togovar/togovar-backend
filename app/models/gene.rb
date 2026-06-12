class Gene
  include Gene::Searchable

  class << self
    def id_comparator(*prior)
      proc do |a, b|
        if [a[:id], b[:id]].all? { |x| prior.include?(x) }
          prior.find_index(a[:id]) <=> prior.find_index(b[:id])
        elsif prior.include?(a[:id])
          -1
        elsif prior.include?(b[:id])
          1
        else
          a[:name] <=> b[:name]
        end
      end
    end
  end
end
