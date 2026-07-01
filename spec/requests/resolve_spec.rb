require 'rails_helper'

RSpec.describe 'Resolves', type: :request do
  describe 'Variant resolver' do
    it 'suggests BRCA2' do
      get '/suggest', params: { term: 'BRCA2' }, headers: { Accept: 'application/json' }

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to eq('application/json; charset=utf-8')

      json = JSON.parse(response.body)
      expect(json.keys).to match_array(%w[gene disease])
      expect(json['gene']).to include('term' => 'BRCA2', 'alias_of' => nil)
    end

    it 'suggests FAD' do
      get '/suggest', params: { term: 'FAD' }, headers: { Accept: 'application/json' }

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to eq('application/json; charset=utf-8')

      json = JSON.parse(response.body)
      expect(json.keys).to match_array(%w[gene disease])
      expect(json['gene']).to include('term' => 'FAD', 'alias_of' => 'BRCA2')
    end
  end

  describe 'Disease suggester' do
    it 'suggests Breast-ovarian cancer, familial' do
      get '/suggest', params: { term: 'breast ovarian cancer' }, headers: { Accept: 'application/json' }

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to eq('application/json; charset=utf-8')

      json = JSON.parse(response.body)
      expect(json.keys).to match_array(%w[gene disease])
      expect(json['disease']).to include('term' => 'Breast-ovarian cancer, familial')
    end

    it 'suggests Alcohol sensitivity' do
      get '/suggest', params: { term: 'Alcohol sensitivity' }, headers: { Accept: 'application/json' }

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to eq('application/json; charset=utf-8')

      json = JSON.parse(response.body)
      expect(json.keys).to match_array(%w[gene disease])
      expect(json['disease']).to include('term' => 'Alcohol sensitivity, acute')
    end
  end
end
