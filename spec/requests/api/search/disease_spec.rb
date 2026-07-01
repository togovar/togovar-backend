require 'rails_helper'

require 'csv'
require 'json'

RSpec.describe 'API::Search::Disease', type: :request do
  describe 'GET /api/search/disease' do
    let(:params) do
      {
        term: 'Alcohol sensitivity'
      }
    end

    it 'returns Alcohol sensitivity, acute' do
      get '/api/search/disease', params: params, headers: { Accept: 'application/json' }

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to eq('application/json; charset=utf-8')

      json = JSON.parse(response.body)
      expect(json).to be_a(Array)
      expect(json.size).to be > 0
      expect(json[0].keys).to contain_exactly('id', 'cui', 'label', 'highlight')
      expect(json).to include(a_hash_including('label' => 'Alcohol sensitivity, acute'))
    end
  end

  describe 'POST /api/search/disease' do
    let(:body) do
      {
        term: 'Alcohol sensitivity'
      }.to_json
    end

    it 'returns Alcohol sensitivity, acute' do
      post '/api/search/disease', params: body, headers: { Accept: 'application/json', 'Content-Type': 'application/json' }

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to eq('application/json; charset=utf-8')

      json = JSON.parse(response.body)
      expect(json).to be_a(Array)
      expect(json.size).to be > 0
      expect(json[0].keys).to contain_exactly('id', 'cui', 'label', 'highlight')
      expect(json).to include(a_hash_including('label' => 'Alcohol sensitivity, acute'))
    end
  end
end
