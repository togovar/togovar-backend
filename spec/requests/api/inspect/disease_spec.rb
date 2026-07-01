require 'rails_helper'

require 'csv'
require 'json'

RSpec.describe 'API::Inspect::Disease', type: :request do
  describe 'GET /api/inspect/disease' do
    let(:params) do
      {
        node: 'MONDO_0012454'
      }
    end

    it 'returns Alcohol sensitivity, acute' do
      get '/api/inspect/disease', params: params, headers: { Accept: 'application/json' }

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to eq('application/json; charset=utf-8')

      json = JSON.parse(response.body)
      expect(json.keys).to contain_exactly('id', 'cui', 'label', 'leaf', 'parents', 'children')
      expect(json).to a_hash_including('label' => 'Alcohol sensitivity, acute')
    end
  end

  describe 'POST /api/inspect/disease' do
    let(:body) do
      {
        node: 'MONDO_0012454'
      }.to_json
    end

    it 'returns Alcohol sensitivity, acute' do
      post '/api/inspect/disease', params: body, headers: { Accept: 'application/json', 'Content-Type': 'application/json' }

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to eq('application/json; charset=utf-8')

      json = JSON.parse(response.body)
      expect(json.keys).to contain_exactly('id', 'cui', 'label', 'leaf', 'parents', 'children')
      expect(json).to a_hash_including('label' => 'Alcohol sensitivity, acute')
    end
  end
end
