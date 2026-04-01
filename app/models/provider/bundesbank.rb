class Provider::Bundesbank < Provider
  include HousePriceConcept

  Error = Class.new(Provider::Error)
  InvalidResponseError = Class.new(Error)

  BASE_URL = "https://api.statistiken.bundesbank.de/rest/data"
  DATASET = "BBDY1"  # System of indicators for German residential property market
  BASE_YEAR = 2010   # Bundesbank uses 2010=100

  # Geographic slide codes in BBDY1 dataset for P0030 (price index)
  # G100 = 127 cities (includes all major German cities - best available granularity)
  # G150 = Germany overall (districts and independent cities)
  # Note: G200 (7 major cities) has NO DATA in BBDY1 despite being listed as a dimension value
  REGION_MAPPING = {
    # German major cities use 127-cities aggregate (best available)
    "DE_BERLIN" => "G100",
    "DE_MUNICH" => "G100",
    "DE_HAMBURG" => "G100",
    "DE_FRANKFURT" => "G100",
    "DE_COLOGNE" => "G100",
    "DE_DUSSELDORF" => "G100",
    "DE_STUTTGART" => "G100",
    # Generic German major city
    "DE_MAJOR" => "G100",
    # German national
    "DE" => "G150"
  }.freeze

  # Cities that belong to the 7-city aggregate
  MAJOR_CITIES = %w[
    BERLIN MUNICH HAMBURG FRANKFURT COLOGNE DUSSELDORF STUTTGART
    MÜNCHEN KÖLN DÜSSELDORF
  ].freeze

  def healthy?
    with_provider_response do
      response = client.get(data_url, { format: "sdmx_json", lastNObservations: 1 })
      response.status == 200
    end
  end

  def fetch_house_price_index(region:, date:)
    with_provider_response do
      slide_code = region_to_slide_code(region)

      response = client.get(data_url, {
        format: "sdmx_json",
        startPeriod: date.year.to_s,
        endPeriod: date.year.to_s
      })

      parse_single_index(response, region, date, slide_code)
    end
  end

  def fetch_house_price_indices(region:, start_date:, end_date:)
    with_provider_response do
      fetch_indices_internal(region: region, start_date: start_date, end_date: end_date)
    end
  end

  # Internal method for fetching indices without provider response wrapper
  def fetch_indices_internal(region:, start_date:, end_date:)
    slide_code = region_to_slide_code(region)

    Rails.logger.info("Bundesbank: Fetching data for slide_code=#{slide_code}, period=#{start_date.year}-#{end_date.year}")

    response = client.get(data_url, {
      format: "sdmx_json",
      startPeriod: start_date.year.to_s,
      endPeriod: end_date.year.to_s
    })

    Rails.logger.info("Bundesbank: API response status=#{response.status}")
    Rails.logger.info("Bundesbank: Response body preview: #{response.body[0..200]}...")

    indices = parse_indices(response, region, slide_code)
    Rails.logger.info("Bundesbank: Parsed #{indices&.size || 0} indices")

    indices
  rescue Faraday::Error => e
    Rails.logger.error("Bundesbank API error: #{e.class} - #{e.message}")
    nil
  rescue JSON::ParserError => e
    Rails.logger.error("Bundesbank JSON parse error: #{e.message}")
    nil
  end

  def calculate_growth_rate(region:, years: 5)
    with_provider_response do
      end_date = Date.current
      start_date = end_date - years.years

      # Fetch indices directly without wrapping in another provider response
      indices = fetch_indices_internal(region: region, start_date: start_date, end_date: end_date)

      return nil if indices.nil? || indices.empty? || indices.size < 2

      # Filter to requested date range (API may return more data than requested)
      filtered_indices = indices.select { |idx| idx.date >= start_date && idx.date <= end_date }
      return nil if filtered_indices.size < 2

      # Sort by date and get first and last
      sorted = filtered_indices.sort_by(&:date)
      first_index = sorted.first
      last_index = sorted.last

      Rails.logger.info("Bundesbank: Found #{indices.size} data points from #{first_index.date} to #{last_index.date}")
      Rails.logger.info("Bundesbank: Index values - start: #{first_index.index_value}, end: #{last_index.index_value}")

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
    return true if region_str == "DE"
    return true if region_str.start_with?("DE_")
    is_major_city?(region_str)
  end

  # Check if a city name is one of the 7 major German cities
  def is_major_city?(city_name)
    normalized = city_name.to_s.upcase.gsub(/[^A-Z]/, "")
    MAJOR_CITIES.any? { |city| normalized.include?(city.gsub(/[^A-Z]/, "")) }
  end

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

    def region_to_slide_code(region)
      region_str = region.to_s.upcase

      # Direct mapping
      return REGION_MAPPING[region_str] if REGION_MAPPING.key?(region_str)

      # Check if it's a major city name - use 127 cities aggregate
      if is_major_city?(region_str)
        return "G100"  # 127 cities aggregate (includes all major cities)
      end

      # Default to national German index
      "G150"
    end

    # P0030 is the price index indicator code
    # The series key format is: FREQ.GROUP.ADJUSTMENT.SLIDE.INDICATOR.SUFFIX
    # For P0030 with G250 (7 cities): A.B10..G250.P0030.I
    def series_key_for_slide(slide_code)
      # Annual frequency, B10 group (price indices), no adjustment, slide code, P0030 indicator, I suffix
      "A.B10..#{slide_code}.P0030.I"
    end

    def parse_single_index(response, region, date, slide_code)
      data = JSON.parse(response.body)

      # Find the series matching our slide code
      series = find_series_for_slide(data, slide_code)
      return nil unless series

      # Get observation for the requested year
      observations = series.dig("observations") || {}
      index_value = observations.values.flatten.first

      return nil unless index_value

      HousePriceIndex.new(
        region: region,
        date: Date.new(date.year, 12, 31),
        index_value: index_value.to_f,
        base_year: BASE_YEAR
      )
    end

    def parse_indices(response, region, slide_code)
      data = JSON.parse(response.body)

      # Get time dimension to map indices to years
      time_dimension = extract_time_dimension(data)
      Rails.logger.debug("Bundesbank: Time dimension has #{time_dimension.size} periods")

      # Find the series matching our slide code
      series = find_series_for_slide(data, slide_code)
      unless series
        Rails.logger.warn("Bundesbank: No series found for slide_code=#{slide_code}")
        # Log available slides for debugging
        log_available_slides(data)
        return []
      end

      observations = series.dig("observations") || {}
      Rails.logger.debug("Bundesbank: Found #{observations.size} observations")

      observations.map do |index_str, values|
        value = values.is_a?(Array) ? values.first : values
        next unless value

        year = time_dimension[index_str.to_i]
        next unless year

        HousePriceIndex.new(
          region: region,
          date: Date.new(year.to_i, 12, 31),
          index_value: value.to_f,
          base_year: BASE_YEAR
        )
      end.compact
    end

    def log_available_slides(data)
      dimensions = data.dig("data", "structure", "dimensions", "series") || []
      Rails.logger.warn("Bundesbank: Found #{dimensions.size} series dimensions")

      dimensions.each do |dim|
        dim_id = dim["id"]
        values = dim.dig("values") || []
        value_ids = values.map { |v| v["id"] }.first(10).join(", ")
        Rails.logger.warn("Bundesbank: Dimension '#{dim_id}' has #{values.size} values: #{value_ids}#{values.size > 10 ? '...' : ''}")
      end

      slide_dim = dimensions.find { |d| d["id"] == "BBK_DOSR_SLIDE" }
      unless slide_dim
        Rails.logger.warn("Bundesbank: BBK_DOSR_SLIDE dimension not found!")
        return
      end

      slide_values = slide_dim.dig("values") || []
      available = slide_values.map { |v| v["id"] }.join(", ")
      Rails.logger.warn("Bundesbank: Available slide codes: #{available}")
    end

    def find_series_for_slide(data, slide_code)
      # SDMX-JSON structure: data.dataSets[0].series (dataSets under data, not root)
      Rails.logger.info("Bundesbank: Response keys: #{data.keys.join(', ')}")
      data_sets = data.dig("data", "dataSets") || []
      Rails.logger.info("Bundesbank: dataSets count: #{data_sets.size}")
      if data_sets.empty?
        Rails.logger.warn("Bundesbank: No dataSets in response")
        return nil
      end

      series_hash = data_sets.first.dig("series") || {}
      Rails.logger.debug("Bundesbank: Found #{series_hash.size} series in response")

      # Get dimension indices - note: dimensions are under data.structure, not structure
      dimensions = data.dig("data", "structure", "dimensions", "series") || []
      slide_dim_index = dimensions.find_index { |d| d["id"] == "BBK_DOSR_SLIDE" }
      indicator_dim_index = dimensions.find_index { |d| d["id"] == "BBK_DOSR_NAME" }

      unless slide_dim_index
        Rails.logger.warn("Bundesbank: BBK_DOSR_SLIDE dimension not found in structure")
        return nil
      end

      unless indicator_dim_index
        Rails.logger.warn("Bundesbank: BBK_DOSR_NAME dimension not found in structure")
        return nil
      end

      # Find slide code index in dimension values
      slide_values = dimensions[slide_dim_index].dig("values") || []
      target_slide_index = slide_values.find_index { |v| v["id"] == slide_code }

      unless target_slide_index
        available_slides = slide_values.map { |v| v["id"] }.join(", ")
        Rails.logger.warn("Bundesbank: Slide code '#{slide_code}' not found. Available: #{available_slides}")
        return nil
      end

      # Find P0030 indicator index
      indicator_values = dimensions[indicator_dim_index].dig("values") || []
      p0030_index = indicator_values.find_index { |v| v["id"] == "P0030" }

      unless p0030_index
        available_indicators = indicator_values.map { |v| v["id"] }.first(10).join(", ")
        Rails.logger.warn("Bundesbank: P0030 indicator not found. Available: #{available_indicators}...")
        return nil
      end

      Rails.logger.info("Bundesbank: Looking for series with slide_dim=#{slide_dim_index}:#{target_slide_index}, indicator_dim=#{indicator_dim_index}:#{p0030_index}")
      Rails.logger.info("Bundesbank: Total series in dataset: #{series_hash.size}")
      Rails.logger.info("Bundesbank: First 5 series keys: #{series_hash.keys.first(5).join(', ')}")

      # Find the series with matching slide and indicator
      series_hash.each do |key, series_data|
        key_parts = key.split(":").map(&:to_i)
        if key_parts[slide_dim_index] == target_slide_index &&
           key_parts[indicator_dim_index] == p0030_index
          Rails.logger.info("Bundesbank: Found matching series with key #{key}")
          return series_data
        end
      end

      # Log what slide/indicator combinations we DID find
      found_combinations = series_hash.keys.first(10).map do |key|
        parts = key.split(":").map(&:to_i)
        "slide=#{parts[slide_dim_index]},name=#{parts[indicator_dim_index]}"
      end
      Rails.logger.warn("Bundesbank: Sample combinations found: #{found_combinations.join('; ')}")
      Rails.logger.warn("Bundesbank: No series matched slide_index=#{target_slide_index}, p0030_index=#{p0030_index}")
      nil
    end

    def extract_time_dimension(data)
      # Get observation-level time dimension - note: under data.structure
      obs_dimensions = data.dig("data", "structure", "dimensions", "observation") || []
      time_dim = obs_dimensions.find { |d| d["id"] == "TIME_PERIOD" }
      return {} unless time_dim

      values = time_dim.dig("values") || []
      values.each_with_index.map { |v, i| [ i, v["id"] ] }.to_h
    end
end
