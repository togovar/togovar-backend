require 'rails_helper'

RSpec.describe 'API::Search::Variant', type: :request do
  describe 'GET /search' do
    context 'without parameters' do
      subject { get '/search', headers: { Accept: 'application/json' } }

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns expected keys' do
        expect(json.keys).to contain_exactly('data', 'scroll', 'statistics')
      end

      it 'returns scroll' do
        expect(json['scroll']).to_not be_empty
      end

      it 'returns statistics' do
        expect(json['statistics']).to_not be_empty
      end

      it 'returns data' do
        expect(json['data']).to_not be_empty
      end
    end

    context 'statistics' do
      subject { get '/search?stat=1&data=0', headers: { Accept: 'application/json' } }

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
    end

    context 'ALDH2' do
      subject { get '/search?term=ALDH2', headers: { Accept: 'application/json' } }

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
      subject { get '/search?term=rs671', headers: { Accept: 'application/json' } }

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
      subject { get '/search?term=tgv47264307', headers: { Accept: 'application/json' } }

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
      subject { get '/search?term=12:111803962:G>A', headers: { Accept: 'application/json' } }

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

    context '12-111803962-G-A' do
      subject { get '/search?term=12-111803962-G-A', headers: { Accept: 'application/json' } }

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns a result for 12-111803962-G-A' do
        expect(json['data'][0]['chromosome']).to eq('12')
        expect(json['data'][0]['position']).to eq(111803962)
        expect(json['data'][0]['reference']).to eq('G')
        expect(json['data'][0]['alternate']).to eq('A')
      end
    end

    context '12:111803962' do
      subject { get '/search?term=12:111803962', headers: { Accept: 'application/json' } }

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns results at 111803962 in chr12' do
        json['data'].each do |variant|
          expect(variant['chromosome']).to eq('12')
          expect(variant['position']).to eq(111803962)
        end
      end
    end

    context '12:111803962-111803972' do
      subject { get '/search?term=12:111803962-111803972', headers: { Accept: 'application/json' } }

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns results between 111803962 and 111803972 in chr12' do
        json['data'].each do |variant|
          expect(variant['chromosome']).to eq('12')
          expect(variant['position']).to be_between(111803962, 111803972).inclusive
        end
      end
    end

    context 'Alcohol sensitivity, acute' do
      subject { get '/search?term="Alcohol sensitivity, acute"', headers: { Accept: 'application/json' } }

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns variants that have condition annotation "Alcohol sensitivity, acute"' do
        json['data'].each do |variant|
          conditions = variant['significance'].flat_map { |x| x['conditions'] }
          expect(conditions).to include(a_hash_including('name' => 'Alcohol sensitivity, acute'))
        end
      end
    end

    context 'JGA-WES dataset' do
      let :params do
        {
          dataset: {
            bbj1k: 0,
            bbj2k: 0,
            gem_j_wga: 0,
            jga_wes: 1,
            jga_wgs: 0,
            jga_snp: 0,
            tommo: 0,
            ncbn: 0,
            gnomad_genomes: 0,
            gnomad_exomes: 0,
            clinvar: 0,
            mgend: 0,
            jogo: 0,
            tommo_jsv1: 0
          }
        }
      end

      subject { get "/search?#{params.to_param}", headers: { Accept: 'application/json' } }

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns variants that have JGA-WES frequency' do
        expect(json.dig('statistics', 'dataset', 'jga_wes')).to be > 0

        json['data'].each do |variant|
          expect(variant['frequencies']).to include(a_hash_including('source' => 'jga_wes'))
        end
      end
    end

    context 'ClinVar dataset' do
      let :params do
        {
          dataset: {
            bbj1k: 0,
            bbj2k: 0,
            gem_j_wga: 0,
            jga_wes: 0,
            jga_wgs: 0,
            jga_snp: 0,
            tommo: 0,
            ncbn: 0,
            gnomad_genomes: 0,
            gnomad_exomes: 0,
            clinvar: 1,
            mgend: 0,
            jogo: 0,
            tommo_jsv1: 0
          }
        }
      end

      subject { get "/search?#{params.to_param}", headers: { Accept: 'application/json' } }

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns variants that have ClinVar condition' do
        expect(json.dig('statistics', 'dataset', 'clinvar')).to be > 0

        json['data'].each do |variant|
          expect(variant['significance']).to include(a_hash_including('source' => 'clinvar'))
        end
      end
    end

    context 'MGeND dataset' do
      let :params do
        {
          dataset: {
            bbj1k: 0,
            bbj2k: 0,
            gem_j_wga: 0,
            jga_wes: 0,
            jga_wgs: 0,
            jga_snp: 0,
            tommo: 0,
            ncbn: 0,
            gnomad_genomes: 0,
            gnomad_exomes: 0,
            clinvar: 0,
            mgend: 1,
            jogo: 0,
            tommo_jsv1: 0
          }
        }
      end

      subject { get "/search?#{params.to_param}", headers: { Accept: 'application/json' } }

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns variants that have MGeND condition' do
        expect(json.dig('statistics', 'dataset', 'mgend')).to be > 0

        json['data'].each do |variant|
          expect(variant['significance']).to include(a_hash_including('source' => 'mgend'))
        end
      end
    end

    context 'Type' do
      let :params do
        {
          type: {
            SO_0001483: 0,
            SO_0000667: 0,
            SO_0000159: 0,
            SO_1000032: 1,
            SO_1000002: 0
          }
        }
      end

      subject { get "/search?#{params.to_param}", headers: { Accept: 'application/json' } }

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns variants whose type is SO_1000032' do
        expect(json.dig('statistics', 'type', 'SO_1000032')).to be > 0

        json['data'].each do |variant|
          expect(variant['type']).to eq('SO_1000032')
        end
      end
    end

    context 'Consequence' do
      let :params do
        {
          consequence: {
            SO_0001893: 0,
            SO_0001574: 0,
            SO_0001575: 0,
            SO_0001587: 0,
            SO_0001589: 0,
            SO_0001578: 0,
            SO_0002012: 0,
            SO_0001889: 0,
            SO_0001907: 0,
            SO_0001906: 0,
            SO_0001821: 0,
            SO_0001822: 0,
            SO_0001583: 1,
            SO_0001818: 0,
            SO_0001787: 0,
            SO_0001630: 0,
            SO_0002170: 0,
            SO_0002169: 0,
            SO_0001626: 0,
            SO_0002019: 0,
            SO_0001567: 0,
            SO_0001819: 0,
            SO_0001580: 0,
            SO_0001620: 0,
            SO_0001623: 0,
            SO_0001624: 0,
            SO_0001792: 0,
            SO_0001627: 0,
            SO_0001621: 0,
            SO_0001619: 0,
            SO_0001968: 0,
            SO_0001631: 0,
            SO_0001632: 0,
            SO_0001895: 0,
            SO_0001892: 0,
            SO_0001782: 0,
            SO_0001894: 0,
            SO_0001891: 0,
            SO_0001566: 0,
            SO_0001628: 0,
            SO_0001060: 0,
          }
        }
      end

      subject { get "/search?#{params.to_param}", headers: { Accept: 'application/json' } }

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns variants that have SO_0001583 in transcripts.consequence' do
        expect(json.dig('statistics', 'consequence', 'SO_0001583')).to be > 0

        json['data'].each do |variant|
          expect(variant['transcripts']).to include(a_hash_including('consequence' => include('SO_0001583')))
        end
      end
    end

    context 'Significance' do
      let :params do
        {
          significance: {
            NA: 0,
            P: 1,
            PLP: 0,
            LP: 0,
            LPLP: 0,
            DR: 0,
            ERA: 0,
            LRA: 0,
            URA: 0,
            CS: 0,
            A: 0,
            RF: 0,
            AF: 0,
            PR: 0,
            B: 0,
            LB: 0,
            CC: 0,
            AN: 0,
            O: 0,
            VH: 0,
            VM: 0,
            VL: 0,
            US: 0,
            NC: 0,
            NP: 0
          }
        }
      end

      subject { get "/search?#{params.to_param}", headers: { Accept: 'application/json' } }

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns variants that have SO_0001583 in transcripts.consequence' do
        expect(json.dig('statistics', 'significance', 'P')).to be > 0

        json['data'].each do |variant|
          expect(variant['significance']).to include(a_hash_including('interpretations' => include('P')))
        end
      end
    end

    context 'SSCV DB' do
      let :params do
        {
          sscv_db: {
            NA: 0,
            PEL: 1,
            CEI: 0,
            EE: 0,
            A: 0
          }
        }
      end

      subject { get "/search?#{params.to_param}", headers: { Accept: 'application/json' } }

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns variants that have predicted_splicing_type "Partial exon loss" in sscv_db' do
        json['data'].each do |variant|
          expect(variant['sscv_db']).to include(a_hash_including('predicted_splicing_type' => 'Partial exon loss'))
        end
      end
    end

    context 'AlphaMissense' do
      let :params do
        {
          alphamissense: {
            NA: 0,
            LB: 0,
            A: 0,
            LP: 1
          }
        }
      end

      subject { get "/search?#{params.to_param}", headers: { Accept: 'application/json' } }

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns variants that have a value great than 0.564 for alphamissense' do
        json['data'].each do |variant|
          expect(variant['alphamissense']).to be > 0.564
        end
      end
    end

    context 'SIFT' do
      let :params do
        {
          sift: {
            NA: 0,
            D: 1,
            T: 0
          }
        }
      end

      subject { get "/search?#{params.to_param}", headers: { Accept: 'application/json' } }

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns variants that have a value less than 0.05 for sift' do
        json['data'].each do |variant|
          expect(variant['sift']).to be < 0.05
        end
      end
    end

    context 'PolyPhen' do
      let :params do
        {
          polyphen: {
            NA: 0,
            PROBD: 1,
            POSSD: 0,
            B: 0,
            U: 0
          }
        }
      end

      subject { get "/search?#{params.to_param}", headers: { Accept: 'application/json' } }

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns variants that have a value greater than 0.908 for polyphen' do
        json['data'].each do |variant|
          expect(variant['polyphen']).to be > 0.908
        end
      end
    end

    context 'CADD Phred' do
      let :params do
        {
          cadd_phred: {
            NA: 0,
            P0: 0,
            P10: 0,
            P20: 1
          }
        }
      end

      subject { get "/search?#{params.to_param}", headers: { Accept: 'application/json' } }

      let :json do
        expect(subject).to be 200
        expect(response.content_type).to eq('application/json; charset=utf-8')

        JSON.parse(response.body)
      end

      it 'returns variants that have a value greater than and equal to 20 for cadd_phred' do
        json['data'].each do |variant|
          expect(variant['cadd_phred']).to be >= 20
        end
      end
    end
  end
end
