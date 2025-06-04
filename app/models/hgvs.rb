class HGVS
  ENSEMBL_URL = if ENV['TOGOVAR_REFERENCE'] == 'GRCh37'
                  'https://grch37.rest.ensembl.org'.freeze
                else
                  'https://rest.ensembl.org'.freeze
                end

  VARIANT_RECORDER_PATH = '/variant_recoder/human/%s'.freeze

  HGVS_REGEXP = /.+:[cgmnpr]\..+/.freeze

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
    result = translate

    return [] unless result.is_a?(Array)

    result.map { |hash| hash.values.filter_map { |v| v.is_a?(Hash) ? v['vcf_string'] : nil } }.flatten.uniq
  rescue Faraday::ConnectionFailed
    raise "Server not responding: #{ENSEMBL_URL}"
  rescue Faraday::ClientError, Faraday::ServerError => e
    raise "#{e.response&.status} #{e.message}"
  rescue Faraday::Error
    raise "Server returned error: #{ENSEMBL_URL}"
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
  rescue Faraday::ConnectionFailed
    @translate_error = "Server not responding: #{ENSEMBL_URL}"
    nil
  rescue Faraday::ClientError, Faraday::ServerError => e
    @translate_error = "#{e.response&.status} #{e.message}"
    nil
  rescue Faraday::Error
    @translate_error = "Server returned error: #{ENSEMBL_URL}"
    nil
  rescue StandardError => e
    Rails.logger.error(self.class) { [e.message, e.backtrace].join("\n") }
    @translate_error = '500 Internal Server Error'
    nil
  end

  private

  def translate
    @translate ||= begin
                     query = { vcf_string: 1 }.to_query
                     url = "#{VARIANT_RECORDER_PATH % URI.encode_www_form_component(@term)}?#{query}"
                     response = ensembl.get(url) do |req|
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
  end

  def ensembl
    @connection ||= Faraday.new(ENSEMBL_URL) do |conn|
      conn.options[:open_timeout] = 10
      conn.options[:timeout] = 30
      conn.adapter Faraday.default_adapter
    end
  end
end
