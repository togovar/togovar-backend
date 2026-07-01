# frozen_string_literal: true

module QueryParameters
  NOT_AVAILABLE_KEYS = %w[NA not_available]

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

      def find(id_or_key)
        find_by_id(id_or_key) || find_by_key(id_or_key)
      end

      def find_by_id(id)
        v = id.to_s.downcase
        self::ALL.find { |x| x.id.downcase == v }
      end

      def find_by_key(name)
        v = name.to_s.downcase
        self::ALL.find { |x| x.key.downcase == v }
      end

      def find_by_label(label)
        v = label.to_s.downcase
        self::ALL.find { |x| x.label.downcase == v }
      end

      def index_of(v)
        return unless (s = find_by_id(v) || find_by_key(v))

        v = s.id.downcase
        self::ALL.index { |x| x.id.downcase == v }
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

    class << self
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

    class << self
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

    class << self
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

  class CaddPhred < Base
    ALL = Rails.configuration
               .application
               .dig(:query_params, :cadd_phred)
               .map { |x| new(x[:id], x[:label], x[:key], x[:default]) }
               .freeze

    WITHOUT_SCORE = ALL.find { |x| x.id == 'without_score' }
    P0 = ALL.find { |x| x.id == 'p0' }
    P10 = ALL.find { |x| x.id == 'p10' }
    P20 = ALL.find { |x| x.id == 'p20' }

    class << self
      # @return [Prediction]
      def find_by_value(value)
        return WITHOUT_SCORE if value.blank?

        case
        when value >= 20
          P20
        when value >= 10
          P10
        when value < 10
          P0
        else
          WITHOUT_SCORE
        end
      end
    end
  end
end
