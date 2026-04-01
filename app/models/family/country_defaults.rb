class Family
  module CountryDefaults
    # Number format examples shown in the dropdown
    NUMBER_FORMATS = [
      "1,234.56",  # comma thousands, dot decimal (US/UK/AU/CA)
      "1.234,56",  # dot thousands, comma decimal (DE/AT/BR/IT/ES/NL/PT)
      "1 234,56",  # space thousands, comma decimal (FR/SE/NO/FI/RU/PL)
      "1'234.56"   # apostrophe thousands, dot decimal (CH)
    ].freeze

    MEASUREMENT_SYSTEMS = %w[metric imperial].freeze

    # Country code → default preferences
    # currency_format: %u = unit/symbol, %n = number
    DEFAULTS = {
      # Europe — dot thousands, comma decimal, symbol after
      "DE" => { number_format: "1.234,56", measurement_system: "metric", date_format: "%d.%m.%Y", currency_format: "%n %u" },
      "AT" => { number_format: "1.234,56", measurement_system: "metric", date_format: "%d.%m.%Y", currency_format: "%n %u" },
      "IT" => { number_format: "1.234,56", measurement_system: "metric", date_format: "%d/%m/%Y", currency_format: "%n %u" },
      "ES" => { number_format: "1.234,56", measurement_system: "metric", date_format: "%d/%m/%Y", currency_format: "%n %u" },
      "NL" => { number_format: "1.234,56", measurement_system: "metric", date_format: "%d-%m-%Y", currency_format: "%u %n" },
      "BE" => { number_format: "1.234,56", measurement_system: "metric", date_format: "%d/%m/%Y", currency_format: "%n %u" },
      "PT" => { number_format: "1.234,56", measurement_system: "metric", date_format: "%d/%m/%Y", currency_format: "%n %u" },
      "GR" => { number_format: "1.234,56", measurement_system: "metric", date_format: "%d/%m/%Y", currency_format: "%n %u" },
      "HR" => { number_format: "1.234,56", measurement_system: "metric", date_format: "%d.%m.%Y", currency_format: "%n %u" },

      # Europe — space thousands, comma decimal
      "FR" => { number_format: "1 234,56", measurement_system: "metric", date_format: "%d/%m/%Y", currency_format: "%n %u" },
      "SE" => { number_format: "1 234,56", measurement_system: "metric", date_format: "%Y-%m-%d", currency_format: "%n %u" },
      "NO" => { number_format: "1 234,56", measurement_system: "metric", date_format: "%d.%m.%Y", currency_format: "%n %u" },
      "FI" => { number_format: "1 234,56", measurement_system: "metric", date_format: "%d.%m.%Y", currency_format: "%n %u" },
      "DK" => { number_format: "1.234,56", measurement_system: "metric", date_format: "%d.%m.%Y", currency_format: "%n %u" },
      "PL" => { number_format: "1 234,56", measurement_system: "metric", date_format: "%d.%m.%Y", currency_format: "%n %u" },
      "CZ" => { number_format: "1 234,56", measurement_system: "metric", date_format: "%d.%m.%Y", currency_format: "%n %u" },
      "RO" => { number_format: "1.234,56", measurement_system: "metric", date_format: "%d.%m.%Y", currency_format: "%n %u" },
      "HU" => { number_format: "1 234,56", measurement_system: "metric", date_format: "%Y.%m.%d", currency_format: "%n %u" },
      "RU" => { number_format: "1 234,56", measurement_system: "metric", date_format: "%d.%m.%Y", currency_format: "%n %u" },

      # Switzerland — apostrophe thousands
      "CH" => { number_format: "1'234.56", measurement_system: "metric", date_format: "%d.%m.%Y", currency_format: "%u %n" },

      # English-speaking — comma thousands, dot decimal, symbol before
      "US" => { number_format: "1,234.56", measurement_system: "imperial", date_format: "%m-%d-%Y", currency_format: "%u%n" },
      "GB" => { number_format: "1,234.56", measurement_system: "imperial", date_format: "%d/%m/%Y", currency_format: "%u%n" },
      "CA" => { number_format: "1,234.56", measurement_system: "metric",   date_format: "%Y-%m-%d", currency_format: "%u%n" },
      "AU" => { number_format: "1,234.56", measurement_system: "metric",   date_format: "%d/%m/%Y", currency_format: "%u%n" },
      "NZ" => { number_format: "1,234.56", measurement_system: "metric",   date_format: "%d/%m/%Y", currency_format: "%u%n" },
      "IE" => { number_format: "1,234.56", measurement_system: "metric",   date_format: "%d/%m/%Y", currency_format: "%u%n" },

      # Asia
      "JP" => { number_format: "1,234.56", measurement_system: "metric", date_format: "%Y/%m/%d", currency_format: "%u%n" },
      "CN" => { number_format: "1,234.56", measurement_system: "metric", date_format: "%Y-%m-%d", currency_format: "%u%n" },
      "IN" => { number_format: "1,234.56", measurement_system: "metric", date_format: "%d-%m-%Y", currency_format: "%u%n" },
      "KR" => { number_format: "1,234.56", measurement_system: "metric", date_format: "%Y.%m.%d", currency_format: "%u%n" },

      # Latin America — dot thousands, comma decimal
      "BR" => { number_format: "1.234,56", measurement_system: "metric", date_format: "%d/%m/%Y", currency_format: "%u %n" },
      "MX" => { number_format: "1,234.56", measurement_system: "metric", date_format: "%d/%m/%Y", currency_format: "%u%n" },
      "AR" => { number_format: "1.234,56", measurement_system: "metric", date_format: "%d/%m/%Y", currency_format: "%u %n" }
    }.freeze

    FALLBACK = { number_format: "1,234.56", measurement_system: "metric", date_format: "%Y-%m-%d", currency_format: "%u%n" }.freeze

    def self.for(country_code)
      DEFAULTS[country_code.to_s.upcase] || FALLBACK
    end

    # Convert the display format string into delimiter/separator options
    def self.number_format_options(format_string)
      case format_string
      when "1.234,56" then { delimiter: ".", separator: "," }
      when "1 234,56" then { delimiter: "\u00A0", separator: "," }  # non-breaking space
      when "1'234.56" then { delimiter: "'", separator: "." }
      else                  { delimiter: ",", separator: "." }  # "1,234.56" default
      end
    end
  end
end
