# frozen_string_literal: true

module QueryParameters
  class Base
    class << self
      def all
        self::ALL
      end

      def defaults(override = {})
        self::ALL.to_h { |x| [x.key.to_sym, x.default] }.merge(override)
      end

      def parameters
        self::ALL.map(&:key).map(&:to_sym)
      end

      def find_by_id(id)
        self::ALL.find { |x| x.id == id.to_s }
      end

      def find_by_key(name)
        self::ALL.find { |x| x.key == name.to_s }
      end

      def index_of(v)
        s = find_by_id(v) || find_by_key(v)

        return unless s

        self::ALL.index { |x| x.id == s.id.to_s }
      end
    end

    attr_accessor :id
    attr_accessor :label
    attr_accessor :key
    attr_accessor :default

    def initialize(id, label, key, default)
      @id = id
      @label = label
      @key = key
      @default = default
    end
  end

  class Dataset < Base
    ALL = Rails.configuration
               .application[:datasets]
               .values.flatten
               .map { |y| new(y[:id], y[:label], y[:id], y.key?(:authorization) ? '0' : '1') }
               .freeze
  end

  class Frequency < Base
    ALL = Rails.configuration
               .application
               .dig(:query_params, :frequency)
               .map { |x| new(x[:id], x[:label], x[:key], x[:default]) }
               .freeze
  end

  class Type < Base
    ALL = Rails.configuration
               .application
               .dig(:query_params, :type)
               .map { |x| new(x[:id], x[:label], x[:key], x[:default]) }
               .freeze
  end

  class ClinicalSignificance < Base
    LABEL_NOT_PROVIDED = 'not provided'

    ALL = Rails.configuration
               .application
               .dig(:query_params, :significance)
               .map { |x| new(x[:id], x[:label], x[:key], x[:default]) }
               .freeze
  end

  class Consequence < Base
    ALL = Rails.configuration
               .application
               .dig(:query_params, :consequence)
               .map { |x| new(x[:id], x[:label], x[:key], x[:default]) }
               .freeze
  end

  class SscvDb < Base
    ALL = Rails.configuration
               .application
               .dig(:query_params, :sscv_db)
               .map { |x| new(x[:id], x[:label], x[:key], x[:default]) }
               .freeze
  end

  class Sift < Base
    ALL = Rails.configuration
               .application
               .dig(:query_params, :sift)
               .map { |x| new(x[:id], x[:label], x[:key], x[:default]) }
               .freeze

    WITHOUT_SCORE = ALL.find { |x| x.id == 'without_score' }
    DELETERIOUS = ALL.find { |x| x.id == 'deleterious' }
    TOLERATED = ALL.find { |x| x.id == 'tolerated' }

    # @return [Prediction]
    def find_by_value(value)
      return WITHOUT_SCORE if value.blank?

      if value < 0.05
        DELETERIOUS
      elsif value >= 0.05
        TOLERATED
      end
    end
  end

  class Polyphen < Base
    ALL = Rails.configuration
               .application
               .dig(:query_params, :polyphen)
               .map { |x| new(x[:id], x[:label], x[:key], x[:default]) }
               .freeze

    WITHOUT_SCORE = ALL.find { |x| x.id == 'without_score' }
    PROBABLY_DAMAGING = ALL.find { |x| x.id == 'probably_damaging' }
    POSSIBLY_DAMAGING = ALL.find { |x| x.id == 'possibly_damaging' }
    BENIGN = ALL.find { |x| x.id == 'benign' }
    UNKNOWN = ALL.find { |x| x.id == 'unknown' }

    # @return [Prediction]
    def find_by_value(value)
      return WITHOUT_SCORE if value.blank?

      case
      when value > 0.908
        PROBABLY_DAMAGING
      when value > 0.446
        POSSIBLY_DAMAGING
      when value >= 0
        BENIGN
      else
        UNKNOWN
      end
    end
  end

  class AlphaMissense < Base
    ALL = Rails.configuration
               .application
               .dig(:query_params, :alphamissense)
               .map { |x| new(x[:id], x[:label], x[:key], x[:default]) }
               .freeze

    WITHOUT_SCORE = ALL.find { |x| x.id == 'without_score' }
    LIKELY_BENIGN = ALL.find { |x| x.id == 'likely_benign' }
    LIKELY_PATHOGENIC = ALL.find { |x| x.id == 'likely_pathogenic' }
    AMBIGUOUS = ALL.find { |x| x.id == 'ambiguous' }

    # @return [Prediction]
    def find_by_value(value)
      return WITHOUT_SCORE if value.blank?

      case
      when value < 0.34
        LIKELY_BENIGN
      when value > 0.564
        LIKELY_PATHOGENIC
      else
        AMBIGUOUS
      end
    end
  end
end
