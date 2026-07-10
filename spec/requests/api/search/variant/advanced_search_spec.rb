require 'rails_helper'

RSpec.describe 'API::Search::Variant', type: :request do
  describe 'POST /api/search/variant' do
    let :headers do
      {
        'Content-Type': 'application/json',
        Accept: 'application/json'
      }
    end

    context 'without parameters' do
      subject { post '/api/search/variant', headers: }

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns expected keys' do
        expect(json.keys).to contain_exactly('data', 'scroll')
      end

      it 'returns scroll' do
        expect(json['scroll']).to_not be_empty
      end

      it 'returns data' do
        expect(json['data']).to_not be_empty
      end
    end

    context 'enable statistics' do
      subject { post '/api/search/variant?stat=1&data=0', headers: }

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns expected keys' do
        expect(json.keys).to contain_exactly('scroll', 'statistics')
        expect(json['scroll'].keys).to contain_exactly('limit', 'offset', 'max_rows')
        expect(json['statistics'].keys).to contain_exactly('total', 'filtered', 'dataset', 'type', 'significance', 'consequence')
      end

      it 'returns number that is greater than 0' do
        expect(json.dig('statistics', 'total')).to be > 0
        expect(json.dig('statistics', 'filtered')).to be > 0
      end
    end

    context 'ALDH2' do
      subject { post '/api/search/variant', params:, headers: }

      let :params do
        {
          query: {
            gene: {
              relation: 'eq',
              terms: [
                404
              ]
            }
          }
        }.to_json
      end

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'contains a result with gene symbol ALDH2' do
        expect(json['data'][0].dig('genes', 0, 'name')).to eq('ALDH2')
      end
    end

    context 'rs671' do
      subject { post '/api/search/variant', params:, headers: }

      let :params do
        {
          query: {
            id: [
              'rs671'
            ]
          }
        }.to_json
      end

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns a result for rs671' do
        expect(json['data'][0]['existing_variations']).to include('rs671')
      end
    end

    context 'tgv47264307' do
      subject { post '/api/search/variant', params:, headers: }

      let :params do
        {
          query: {
            id: [
              'tgv47264307'
            ]
          }
        }.to_json
      end

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns a result for tgv47264307' do
        expect(json['data'][0]['id']).to include('tgv47264307')
      end
    end

    context '12:111803962:G>A' do
      subject { post '/api/search/variant', params:, headers: }

      let :params do
        {
          query: {
            variant: {
              chromosome: '12',
              position: 111803962,
              reference: 'G',
              alternate: 'A'
            }
          }
        }.to_json
      end

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns a result for 12:111803962:G>A' do
        expect(json['data'][0]['chromosome']).to eq('12')
        expect(json['data'][0]['position']).to eq(111803962)
        expect(json['data'][0]['reference']).to eq('G')
        expect(json['data'][0]['alternate']).to eq('A')
      end
    end

    context '12:111803962' do
      subject { post '/api/search/variant?stat=1', params:, headers: }

      let :params do
        {
          query: {
            location: {
              chromosome: '12',
              position: 111803962
            }
          }
        }.to_json
      end

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns results at 111803962 in chr12' do
        expect(json.dig('statistics', 'total')).to be > 0
        expect(json.dig('statistics', 'filtered')).to be > 0

        json['data'].each do |variant|
          expect(variant['chromosome']).to eq('12')
          expect(variant['position']).to eq(111803962)
        end
      end
    end

    context '12:111803962-111803972' do
      subject { post '/api/search/variant?stat=1', params:, headers: }

      let :params do
        {
          query: {
            location: {
              chromosome: '12',
              position: {
                gte: 111803962,
                lte: 111803972
              }
            }
          }
        }.to_json
      end

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns results between 111803962 and 111803972 in chr12' do
        expect(json.dig('statistics', 'total')).to be > 0
        expect(json.dig('statistics', 'filtered')).to be > 0

        json['data'].each do |variant|
          expect(variant['chromosome']).to eq('12')
          expect(variant['position']).to be_between(111803962, 111803972).inclusive
        end
      end
    end

    context 'Alcohol sensitivity, acute' do
      subject { post '/api/search/variant?stat=1', params:, headers: }

      let :params do
        {
          query: {
            disease: {
              relation: 'eq',
              terms: [
                'C2674838'
              ]
            }
          }
        }.to_json
      end

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns variants that have condition annotation "Alcohol sensitivity, acute"' do
        expect(json.dig('statistics', 'total')).to be > 0
        expect(json.dig('statistics', 'filtered')).to be > 0

        json['data'].each do |variant|
          conditions = variant['significance'].flat_map { |x| x['conditions'] }
          expect(conditions).to include(a_hash_including('name' => 'Alcohol sensitivity, acute'))
        end
      end
    end

    context 'JGA-WES dataset' do
      subject { post '/api/search/variant?stat=1', params:, headers: }

      let :params do
        {
          query: {
            frequency: {
              dataset: {
                name: 'jga_wes'
              },
              frequency: {
                gt: 0,
                lte: 1
              }
            }
          }
        }.to_json
      end

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns variants that have JGA-WES frequency' do
        expect(json.dig('statistics', 'total')).to be > 0
        expect(json.dig('statistics', 'filtered')).to be > 0
        expect(json.dig('statistics', 'dataset', 'jga_wes')).to be > 0

        json['data'].each do |variant|
          expect(variant['frequencies']).to include(a_hash_including('source' => 'jga_wes'))
        end
      end
    end

    context 'BBJ 1K dataset' do
      subject { post '/api/search/variant?stat=1', params:, headers: }

      let :params do
        {
          query: {
            frequency: {
              dataset: {
                name: 'bbj1k'
              },
              frequency: {
                gt: 0,
                lte: 1
              }
            }
          }
        }.to_json
      end

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns variants that have BBJ 1K frequency' do
        expect(json.dig('statistics', 'total')).to be > 0
        expect(json.dig('statistics', 'filtered')).to be > 0
        expect(json.dig('statistics', 'dataset', 'bbj1k')).to be > 0

        json['data'].each do |variant|
          expect(variant['frequencies']).to include(a_hash_including('source' => 'bbj1k'))
        end
      end
    end

    context 'BBJ 2K dataset' do
      subject { post '/api/search/variant?stat=1', params:, headers: }

      let :params do
        {
          query: {
            frequency: {
              dataset: {
                name: 'bbj2k'
              },
              frequency: {
                gt: 0,
                lte: 1
              }
            }
          }
        }.to_json
      end

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns variants that have BBJ 2K frequency' do
        expect(json.dig('statistics', 'total')).to be > 0
        expect(json.dig('statistics', 'filtered')).to be > 0
        expect(json.dig('statistics', 'dataset', 'bbj2k')).to be > 0

        json['data'].each do |variant|
          expect(variant['frequencies']).to include(a_hash_including('source' => 'bbj2k'))
        end
      end
    end

    context 'ClinVar dataset' do
      subject { post '/api/search/variant?stat=1', params:, headers: }

      let :params do
        {
          query: {
            significance: {
              relation: 'ne',
              terms: ['NA'],
              source: ['clinvar']
            }
          }
        }.to_json
      end

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns variants that have ClinVar condition' do
        expect(json.dig('statistics', 'total')).to be > 0
        expect(json.dig('statistics', 'filtered')).to be > 0
        expect(json.dig('statistics', 'dataset', 'clinvar')).to be > 0

        json['data'].each do |variant|
          expect(variant['significance']).to include(a_hash_including('source' => 'clinvar'))
        end
      end
    end

    context 'MGeND dataset' do
      subject { post '/api/search/variant?stat=1', params:, headers: }

      let :params do
        {
          query: {
            significance: {
              relation: 'ne',
              terms: ['NA'],
              source: ['mgend']
            }
          }
        }.to_json
      end

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns variants that have MGeND condition' do
        expect(json.dig('statistics', 'total')).to be > 0
        expect(json.dig('statistics', 'filtered')).to be > 0
        expect(json.dig('statistics', 'dataset', 'mgend')).to be > 0

        json['data'].each do |variant|
          expect(variant['significance']).to include(a_hash_including('source' => 'mgend'))
        end
      end
    end

    context 'Type' do
      subject { post '/api/search/variant?stat=1', params:, headers: }

      let :params do
        {
          query: {
            type: {
              relation: 'eq',
              terms: ['SO_1000032']
            }
          }
        }.to_json
      end

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns variants whose type is SO_1000032' do
        expect(json.dig('statistics', 'total')).to be > 0
        expect(json.dig('statistics', 'filtered')).to be > 0
        expect(json.dig('statistics', 'type', 'SO_1000032')).to be > 0

        json['data'].each do |variant|
          expect(variant['type']).to eq('SO_1000032')
        end
      end
    end

    context 'Consequence' do
      subject { post '/api/search/variant?stat=1', params:, headers: }

      let :params do
        {
          query: {
            consequence: {
              relation: 'eq',
              terms: ['SO_0001583']
            }
          }
        }.to_json
      end

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns variants that have SO_0001583 in transcripts.consequence' do
        expect(json.dig('statistics', 'total')).to be > 0
        expect(json.dig('statistics', 'filtered')).to be > 0
        expect(json.dig('statistics', 'consequence', 'SO_0001583')).to be > 0

        json['data'].each do |variant|
          expect(variant['transcripts']).to include(a_hash_including('consequence' => include('SO_0001583')))
        end
      end
    end

    context 'Significance' do
      subject { post '/api/search/variant?stat=1', params:, headers: }

      let :params do
        {
          query: {
            significance: {
              relation: 'eq',
              terms: ['P']
            }
          }
        }.to_json
      end

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns variants that have SO_0001583 in transcripts.consequence' do
        expect(json.dig('statistics', 'total')).to be > 0
        expect(json.dig('statistics', 'filtered')).to be > 0
        expect(json.dig('statistics', 'significance', 'P')).to be > 0

        json['data'].each do |variant|
          expect(variant['significance']).to include(a_hash_including('interpretations' => include('P')))
        end
      end
    end

    context 'SSCV DB' do
      subject { post '/api/search/variant?stat=1', params:, headers: }

      let :params do
        {
          query: {
            sscv_db: {
              relation: 'eq',
              terms: ['PEL']
            }
          }
        }.to_json
      end

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns variants that have predicted_splicing_type "Partial exon loss" in sscv_db' do
        expect(json.dig('statistics', 'total')).to be > 0
        expect(json.dig('statistics', 'filtered')).to be > 0

        json['data'].each do |variant|
          expect(variant['sscv_db']).to include(a_hash_including('predicted_splicing_type' => 'Partial exon loss'))
        end
      end
    end

    context 'AlphaMissense' do
      subject { post '/api/search/variant?stat=1', params:, headers: }

      let :params do
        {
          query: {
            alphamissense: {
              score: {
                gt: 0.564
              }
            }
          }
        }.to_json
      end

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns variants that have a value great than 0.564 for alphamissense' do
        expect(json.dig('statistics', 'total')).to be > 0
        expect(json.dig('statistics', 'filtered')).to be > 0

        json['data'].each do |variant|
          expect(variant['alphamissense']).to be > 0.564
        end
      end
    end

    context 'Without AlphaMissense' do
      subject { post '/api/search/variant?stat=1', params:, headers: }

      let :params do
        {
          query: {
            alphamissense: {
              score: ['unassigned']
            }
          }
        }.to_json
      end

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns variants without alphamissense' do
        expect(json.dig('statistics', 'total')).to be > 0
        expect(json.dig('statistics', 'filtered')).to be > 0

        json['data'].each do |variant|
          expect(variant).not_to include(:alphamissense)
        end
      end
    end

    context 'SIFT' do
      subject { post '/api/search/variant?stat=1', params:, headers: }

      let :params do
        {
          query: {
            sift: {
              score: {
                lt: 0.05
              }
            }
          }
        }.to_json
      end

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns variants that have a value less than 0.05 for sift' do
        expect(json.dig('statistics', 'total')).to be > 0
        expect(json.dig('statistics', 'filtered')).to be > 0

        json['data'].each do |variant|
          expect(variant['sift']).to be < 0.05
        end
      end
    end

    context 'Without SIFT' do
      subject { post '/api/search/variant?stat=1', params:, headers: }

      let :params do
        {
          query: {
            sift: {
              score: ['unassigned']
            }
          }
        }.to_json
      end

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns variants without sift' do
        expect(json.dig('statistics', 'total')).to be > 0
        expect(json.dig('statistics', 'filtered')).to be > 0

        json['data'].each do |variant|
          expect(variant).not_to include(:sift)
        end
      end
    end

    context 'PolyPhen' do
      subject { post '/api/search/variant?stat=1', params:, headers: }

      let :params do
        {
          query: {
            polyphen: {
              score: {
                gt: 0.908
              }
            }
          }
        }.to_json
      end

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns variants that have a value greater than 0.908 for polyphen' do
        expect(json.dig('statistics', 'total')).to be > 0
        expect(json.dig('statistics', 'filtered')).to be > 0

        json['data'].each do |variant|
          expect(variant['polyphen']).to be > 0.908
        end
      end
    end

    context 'Without PolyPhen' do
      subject { post '/api/search/variant?stat=1', params:, headers: }

      let :params do
        {
          query: {
            polyphen: {
              score: ['unassigned']
            }
          }
        }.to_json
      end

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns variants without polyphen' do
        expect(json.dig('statistics', 'total')).to be > 0
        expect(json.dig('statistics', 'filtered')).to be > 0

        json['data'].each do |variant|
          expect(variant).not_to include(:polyphen)
        end
      end
    end

    context 'CADD Phred' do
      subject { post '/api/search/variant?stat=1', params:, headers: }

      let :params do
        {
          query: {
            cadd_phred: {
              score: {
                gte: 20
              }
            }
          }
        }.to_json
      end

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns variants that have a value greater than and equal to 20 for cadd_phred' do
        expect(json.dig('statistics', 'total')).to be > 0
        expect(json.dig('statistics', 'filtered')).to be > 0

        json['data'].each do |variant|
          expect(variant['cadd_phred']).to be >= 20
        end
      end
    end

    context 'Without CADD Phred' do
      subject { post '/api/search/variant?stat=1', params:, headers: }

      let :params do
        {
          query: {
            cadd_phred: {
              score: ['unassigned']
            }
          }
        }.to_json
      end

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns variants without cadd_phred' do
        expect(json.dig('statistics', 'total')).to be > 0
        expect(json.dig('statistics', 'filtered')).to be > 0

        json['data'].each do |variant|
          expect(variant).not_to include(:cadd_phred)
        end
      end
    end
  end
end
