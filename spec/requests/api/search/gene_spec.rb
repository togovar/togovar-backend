require 'rails_helper'

require 'csv'
require 'json'

RSpec.describe 'API::Search::Gene', type: :request do
  describe 'GET /api/search/gene' do
    let(:params) do
      {
        term: 'ALDH2'
      }
    end

    it 'returns ALDH2' do
      get '/api/search/gene', params: params, headers: { Accept: 'application/json' }

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to eq('application/json; charset=utf-8')

      json = JSON.parse(response.body)
      expect(json).to be_a(Array)
      expect(json.size).to be > 0
      expect(json[0].keys).to contain_exactly('id', 'symbol', 'name', 'alias_of', 'highlight')
      expect(json).to include(a_hash_including('symbol' => 'ALDH2'))
    end
  end

  describe 'POST /api/search/gene' do
    let(:body) do
      {
        term: 'ALDH2'
      }.to_json
    end

    it 'returns ALDH2' do
      post '/api/search/gene', params: body, headers: { Accept: 'application/json', 'Content-Type': 'application/json' }

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to eq('application/json; charset=utf-8')

      json = JSON.parse(response.body)
      expect(json).to be_a(Array)
      expect(json.size).to be > 0
      expect(json[0].keys).to contain_exactly('id', 'symbol', 'name', 'alias_of', 'highlight')
      expect(json).to include(a_hash_including('symbol' => 'ALDH2'))
    end
  end
end
