require 'rails_helper'

require 'csv'
require 'json'

RSpec.describe 'API::Download::Variant', type: :request do
  module Headers
    GRCH37 = %w[tgv_id rs chromosome position_grch37 reference alternate type gene consequence condition
                sift_qualitative_prediction sift_score polyphen2_qualitative_prediction polyphen2_score
                alphamissense_pathogenicity alphamissense_score]
    GRCH38 = %w[tgv_id rs chromosome position_grch38 reference alternate type gene consequence condition
                sift_qualitative_prediction sift_score polyphen2_qualitative_prediction polyphen2_score
                alphamissense_pathogenicity alphamissense_score]
  end

  let :expected_headers do
    case ENV['TOGOVAR_REFERENCE']
    when 'GRCh37'
      Headers::GRCH37
    when 'GRCh38'
      Headers::GRCH38
    else
      pending("TOGOVAR_REFERENCE is not set.")
    end
  end

  describe 'GET /api/download/variant' do
    let(:params) do
      { term: 'tgv671' }
    end

    it 'download json' do
      get '/api/download/variant', params: params, headers: { Accept: 'application/json' }

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to eq('application/json; charset=utf-8')

      json = JSON.parse(response.body)
      expect(json.keys).to contain_exactly('data')
      expect(json['data'][0]).to a_hash_including('tgv_id' => 'tgv671')
      expect(json['data'][0].keys).to include(*expected_headers)
    end

    it 'download csv' do
      get '/api/download/variant', params: params, headers: { Accept: 'text/csv' }

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to eq('text/csv; charset=utf-8')

      csv = CSV.new(response.body, headers: true)
      expect(csv.first.to_h).to a_hash_including('tgv_id' => 'tgv671')
      expect(csv.headers).to include(*expected_headers)
    end

    it 'download tsv' do
      get '/api/download/variant', params: params, headers: { Accept: 'text/plain' }

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to eq('text/tab-separated-values; charset=utf-8')

      tsv = CSV.new(response.body, headers: true, col_sep: "\t")
      expect(tsv.first.to_h).to a_hash_including('tgv_id' => 'tgv671')
      expect(tsv.headers).to include(*expected_headers)
    end
  end

  describe 'POST /api/download/variant' do
    let(:body) do
      { query: { id: ["tgv671"] } }.to_json
    end

    it 'download json' do
      post '/api/download/variant', params: body, headers: { Accept: 'application/json', 'Content-Type': 'application/json' }

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to eq('application/json; charset=utf-8')

      json = JSON.parse(response.body)
      expect(json.keys).to contain_exactly('data')
      expect(json['data'][0]).to a_hash_including('tgv_id' => 'tgv671')
      expect(json['data'][0].keys).to include(*expected_headers)
    end

    it 'download csv' do
      post '/api/download/variant', params: body, headers: { Accept: 'text/csv', 'Content-Type': 'application/json' }

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to eq('text/csv; charset=utf-8')

      csv = CSV.new(response.body, headers: true)
      expect(csv.first.to_h).to a_hash_including('tgv_id' => 'tgv671')
      expect(csv.headers).to include(*expected_headers)
    end

    it 'download tsv' do
      post '/api/download/variant', params: body, headers: { Accept: 'text/plain', 'Content-Type': 'application/json' }

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to eq('text/tab-separated-values; charset=utf-8')

      tsv = CSV.new(response.body, headers: true, col_sep: "\t")
      expect(tsv.first.to_h).to a_hash_including('tgv_id' => 'tgv671')
      expect(tsv.headers).to include(*expected_headers)
    end
  end
end
