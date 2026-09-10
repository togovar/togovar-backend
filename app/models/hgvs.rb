class HGVS
  ENSEMBL_URL = 'https://grch37.rest.ensembl.org'.freeze
  HGVS2VCF_URL = ENV.fetch('TOGOVAR_HGVS2VCF_URL', 'http://localhost:4567').freeze

  VARIANT_RECORDER_PATH = '/variant_recoder/human/%s'.freeze
  HGVS2VCF_DECODE_PATH = '/decode'.freeze

  HGVS_REGEXP = /.+:[cgmnpr]\..+/.freeze

  REFSEQ_TO_CHROMOSOME = {
    'NC_000001' => '1',
    'NC_000002' => '2',
    'NC_000003' => '3',
    'NC_000004' => '4',
    'NC_000005' => '5',
    'NC_000006' => '6',
    'NC_000007' => '7',
    'NC_000008' => '8',
    'NC_000009' => '9',
    'NC_000010' => '10',
    'NC_000011' => '11',
    'NC_000012' => '12',
    'NC_000013' => '13',
    'NC_000014' => '14',
    'NC_000015' => '15',
    'NC_000016' => '16',
    'NC_000017' => '17',
    'NC_000018' => '18',
    'NC_000019' => '19',
    'NC_000020' => '20',
    'NC_000021' => '21',
    'NC_000022' => '22',
    'NC_000023' => 'X',
    'NC_000024' => 'Y',
    'NC_012920' => 'MT'
  }.freeze

  class UnknownSequenceError < StandardError; end

  class << self
    def match?(term)
      term.match?(HGVS_REGEXP)
    end
  end

  attr_reader :translate_error, :translate_warning

  def initialize(term)
    @term = term
  end

  def match?(term)
    self.class.match?(term)
  end

  def resolve
    @result ||= request

    return [] unless @result.is_a?(Array)

    @result.map { |hash| hash.values.filter_map { |v| v.is_a?(Hash) ? v['vcf_string'] : nil } }.flatten.uniq
  rescue Faraday::ConnectionFailed, Faraday::TimeoutError, Net::ReadTimeout
    raise "Server not responding: #{service_url}"
  rescue Faraday::ClientError, Faraday::ServerError => e
    raise "#{e.response&.status} #{e.message}"
  rescue Faraday::Error
    raise "Server returned error: #{service_url}"
  rescue StandardError => e
    Rails.logger.error(self.class) { [e.message, e.backtrace].join("\n") }
    raise '500 Internal Server Error'
  end

  def extract_location
    if (vcf = resolve.first).present?
      chr, pos, ref, alt = vcf.split('-')

      "#{chr}:#{pos}:#{ref}>#{alt}"
    else
      @translate_error = "Failed to translate HGVS representation: #{@term}"
      nil
    end
  rescue => e
    Rails.logger.error(self.class) { [e.message, e.backtrace].join("\n") }
    @translate_error = e.message
    nil
  end

  private

  def request_ensembl
    query = { vcf_string: 1 }.to_query
    url = "#{VARIANT_RECORDER_PATH % URI.encode_www_form_component(@term)}?#{query}"
    response = client.get(url) do |req|
      req.headers['Accept'] = 'application/json'
    end

    json = JSON.parse(response.body)

    if json.is_a?(Hash) && json['error'].present?
      @translate_error = json['error']
      return
    end

    if (warning = json.dig(0, 'warnings', 0)).present?
      @translate_warning = warning
    end

    json
  end

  def request_hgvs2vcf
    response = client.post(HGVS2VCF_DECODE_PATH) do |req|
      req.headers['Content-Type'] = 'application/json'
      req.body = { hgvs: [@term] }.to_json
    end

    json = JSON.parse(response.body)

    if (warning = json.dig(0, 'warnings', 0)).present?
      @translate_warning = warning
    end

    json.flat_map do |result|
      Array(result['vcf']).filter_map do |vcf|
        chrom = REFSEQ_TO_CHROMOSOME[vcf['chrom'][/(NC_\d+)(\.\d+)?/, 1]]
        pos = vcf['pos']
        ref = vcf['ref']
        alt = vcf['alt']

        next if [chrom, pos, ref, alt].any?(&:blank?)

        { vcf['alt'] => { 'vcf_string' => [chrom, pos, ref, alt].join('-') } }
      end
    end
  end

  def request
    ENV['TOGOVAR_REFERENCE'] == 'GRCh38' ? request_hgvs2vcf : request_ensembl
  end

  def service_url
    ENV['TOGOVAR_REFERENCE'] == 'GRCh38' ? HGVS2VCF_URL : ENSEMBL_URL
  end

  def client
    @connection ||= Faraday.new(service_url) do |conn|
      conn.options[:open_timeout] = 10
      conn.options[:timeout] = 30
      conn.adapter Faraday.default_adapter
    end
  end
end
