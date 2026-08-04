# frozen_string_literal: true

module TogoVar
  module Helper
    def hashing(text)
      Digest::SHA512.hexdigest(text)
    end
  end
end
