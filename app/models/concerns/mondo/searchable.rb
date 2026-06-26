class Mondo
  module Searchable
    extend ActiveSupport::Concern
    include ElasticsearchIndex::Base

    included do
      include Elasticsearch::Model

      index_name :mondo
    end
  end
end
