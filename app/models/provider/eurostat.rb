class Provider::Eurostat < Provider
  include HousePriceConcept

  Error = Class.new(Provider::Error)
  InvalidResponseError = Class.new(Error)

  BASE_URL = "https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data"
  DATASET = "teicp270"  # House price index quarterly (2015=100)
  BASE_YEAR = 2015

  # Eurostat geo codes for EU countries
  COUNTRY_MAPPING = {
    "AT" => "AT",  # Austria
    "BE" => "BE",  # Belgium
    "BG" => "BG",  # Bulgaria
    "HR" => "HR",  # Croatia
    "CY" => "CY",  # Cyprus
    "CZ" => "CZ",  # Czechia
    "DK" => "DK",  # Denmark
    "EE" => "EE",  # Estonia
    "FI" => "FI",  # Finland
    "FR" => "FR",  # France
    "DE" => "DE",  # Germany
    "GR" => "EL",  # Greece (Eurostat uses EL)
    "HU" => "HU",  # Hungary
    "IE" => "IE",  # Ireland
    "IT" => "IT",  # Italy
    "LV" => "LV",  # Latvia
    "LT" => "LT",  # Lithuania
    "LU" => "LU",  # Luxembourg
    "MT" => "MT",  # Malta
    "NL" => "NL",  # Netherlands
    "PL" => "PL",  # Poland
    "PT" => "PT",  # Portugal
    "RO" => "RO",  # Romania
    "SK" => "SK",  # Slovakia
    "SI" => "SI",  # Slovenia
    "ES" => "ES",  # Spain
    "SE" => "SE",  # Sweden
    "NO" => "NO",  # Norway (EFTA)
    "IS" => "IS",  # Iceland (EFTA)
    "CH" => "CH",  # Switzerland (EFTA)
    "UK" => "UK",  # United Kingdom (historical data)
    "EU" => "EU27_2020"  # EU aggregate
  }.freeze

  # Regions that can be used as defaults
  AVAILABLE_REGIONS = COUNTRY_MAPPING.keys.freeze

  def healthy?
    with_provider_response do
      response = client.get(data_url, { format: "JSON", geo: "EU27_2020", sinceTimePeriod: most_recent_quarter })
      response.status == 200
    end
  end

  def fetch_house_price_index(region:, date:)
    with_provider_response do
      geo_code = eurostat_geo_code(region)
      quarter = date_to_quarter(date)

      response = client.get(data_url, {
        format: "JSON",
        geo: geo_code,
        time: quarter
      })

      parse_single_index(response, region, date)
    end
  end

  def fetch_house_price_indices(region:, start_date:, end_date:)
    with_provider_response do
      fetch_indices_internal(region: region, start_date: start_date, end_date: end_date)
    end
  end

  # Internal method for fetching indices without provider response wrapper
  def fetch_indices_internal(region:, start_date:, end_date:)
    geo_code = eurostat_geo_code(region)

    Rails.logger.info("Eurostat: Fetching data for geo=#{geo_code}, period=#{date_to_quarter(start_date)} to #{date_to_quarter(end_date)}")

    response = client.get(data_url, {
      format: "JSON",
      geo: geo_code,
      sinceTimePeriod: date_to_quarter(start_date),
      untilTimePeriod: date_to_quarter(end_date)
    })

    indices = parse_indices(response, region)
    Rails.logger.info("Eurostat: Parsed #{indices.size} indices")
    indices
  rescue Faraday::Error => e
    Rails.logger.error("Eurostat API error: #{e.class} - #{e.message}")
    nil
  rescue JSON::ParserError => e
    Rails.logger.error("Eurostat JSON parse error: #{e.message}")
    nil
  end

  def calculate_growth_rate(region:, years: 5)
    with_provider_response do
      end_date = Date.current
      start_date = end_date - years.years

      # Fetch indices directly without wrapping in another provider response
      indices = fetch_indices_internal(region: region, start_date: start_date, end_date: end_date)

      return nil if indices.nil? || indices.empty? || indices.size < 2

      # Sort by date and get first and last
      sorted = indices.sort_by(&:date)
      first_index = sorted.first
      last_index = sorted.last

      Rails.logger.info("Eurostat: Found #{indices.size} data points from #{first_index.date} to #{last_index.date}")
      Rails.logger.info("Eurostat: Index values - start: #{first_index.index_value}, end: #{last_index.index_value}")

      # Calculate CAGR: ((end_value / start_value) ^ (1/years)) - 1
      actual_years = (last_index.date - first_index.date).to_f / 365.25
      return nil if actual_years < 0.5 || first_index.index_value.zero?

      cagr = ((last_index.index_value.to_f / first_index.index_value) ** (1.0 / actual_years)) - 1
      annual_rate = (cagr * 100).round(2)

      GrowthRate.new(
        region: region,
        annual_rate: annual_rate,
        period_start: first_index.date,
        period_end: last_index.date
      )
    end
  end

  def supported_region?(region)
    region_str = region.to_s.upcase
    # Direct country code match
    return true if COUNTRY_MAPPING.key?(region_str)
    # Also accept German city names (we'll use DE country data as fallback)
    is_german_city?(region_str)
  end

  # Check if a region is a known German city
  def is_german_city?(region)
    GERMAN_CITIES.include?(region.to_s.upcase.gsub(/[^A-Z]/, ""))
  end

  # German cities that we recognize (used for fallback to DE country data)
  GERMAN_CITIES = %w[
    BERLIN HAMBURG MUNICH MUNCHEN COLOGNE KOLN FRANKFURT
    STUTTGART DUSSELDORF DÜSSELDORF HANNOVER HANOVER
    NUREMBERG NURNBERG BREMEN DRESDEN LEIPZIG DORTMUND
    ESSEN DUISBURG BOCHUM WUPPERTAL BIELEFELD BONN
    MUNSTER KARLSRUHE MANNHEIM AUGSBURG WIESBADEN
  ].freeze

  private

    def data_url
      "#{BASE_URL}/#{DATASET}"
    end

    def client
      @client ||= Faraday.new do |faraday|
        faraday.request(:retry, {
          max: 2,
          interval: 0.05,
          interval_randomness: 0.5,
          backoff_factor: 2
        })
        faraday.response :raise_error
        faraday.headers["Accept"] = "application/json"
      end
    end

    def eurostat_geo_code(region)
      code = region.to_s.upcase
      # German cities should use DE country code for Eurostat API
      return "DE" if is_german_city?(code)
      COUNTRY_MAPPING[code] || code
    end

    def date_to_quarter(date)
      quarter = ((date.month - 1) / 3) + 1
      "#{date.year}-Q#{quarter}"
    end

    def quarter_to_date(quarter_string)
      # Parse "2024-Q1" format to end-of-quarter date
      match = quarter_string.match(/(\d{4})-Q(\d)/)
      return nil unless match

      year = match[1].to_i
      quarter = match[2].to_i

      # Return end of quarter month
      end_month = quarter * 3
      Date.new(year, end_month, 1).end_of_month
    end

    def most_recent_quarter
      date_to_quarter(Date.current - 3.months)
    end

    def parse_single_index(response, region, date)
      data = JSON.parse(response.body)

      # JSON-stat format: values are in "value" object, keyed by index
      values = data.dig("value")
      return nil if values.nil? || values.empty?

      index_value = values.values.first
      return nil unless index_value

      HousePriceIndex.new(
        region: region,
        date: date,
        index_value: index_value.to_f,
        base_year: BASE_YEAR
      )
    end

    def parse_indices(response, region)
      data = JSON.parse(response.body)

      values = data.dig("value") || {}
      time_dimension = data.dig("dimension", "time", "category", "index") || {}

      # Map index positions to quarter labels
      time_labels = time_dimension.invert

      values.map do |index_str, value|
        quarter = time_labels[index_str.to_i]
        next unless quarter && value

        date = quarter_to_date(quarter)
        next unless date

        HousePriceIndex.new(
          region: region,
          date: date,
          index_value: value.to_f,
          base_year: BASE_YEAR
        )
      end.compact
    end
end
