# frozen_string_literal: true

class ApplicationController < ActionController::API
  include ActionController::Cookies
  include ActionController::MimeResponds

  # GET /
  def index
    render json: {
      name: Rails.application.class.module_parent_name
    }
  end

  protected

  # @return [Hash]
  def request_headers
    headers = request.headers
    {
      'Accept': headers['Accept'],
      'Accept-Encoding': headers['Accept-Encoding'],
      'Accept-Language': headers['Accept-Language'],
      'Content-Length': headers['Content-Length'],
      'Content-Type': headers['Content-Type'],
      'Origin': headers['Origin'],
      'User-Agent': headers['User-Agent']
    }.compact
  end
end
