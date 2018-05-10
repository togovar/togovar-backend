namespace :suggest do
  namespace :elastic do
    desc 'create index'
    task create_index: :environment do
      mappings = {}
      mappings.merge! GeneSuggest.mappings.to_hash
      mappings.merge! DiseaseSuggest.mappings.to_hash
      puts Suggest.elasticsearch.create_index! mappings: mappings, force: true
      puts Suggest.elasticsearch.refresh_index!
    end

    desc 'delete index'
    task delete_index: :environment do
      puts Suggest.elasticsearch.delete_index!
    end

    desc 'import index'
    task import_index: :environment do
      puts GeneSuggest.import
      puts DiseaseSuggest.import
    end
  end
end
