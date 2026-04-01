class Provider::DashboardDeutschland < Provider
  include HousePriceConcept

  Error = Class.new(Provider::Error)
  InvalidResponseError = Class.new(Error)

  BASE_URL = "https://www.dashboard-deutschland.de/api/tile/indicators"
  BASE_YEAR = 2015
  BASE_QUARTER = 4  # Q4 2015 = 100

  # Indicator IDs for different property types
  INDICATORS = {
    apartment: "data_woh_preise_immobilien_hpi_wohnungen",
    house: "data_woh_preise_immobilien_hpi_haueser"
  }.freeze

  # District type codes mapped to series indices in the API response
  # The API returns 5 series in a specific order
  DISTRICT_TYPES = {
    metropolen: { index: 0, name: "Metropolen", description: "7 largest cities (Berlin, Hamburg, Munich, Cologne, Frankfurt, Stuttgart, Düsseldorf)" },
    grossstaedte: { index: 1, name: "Kreisfreie Großstädte", description: "Large independent cities (excluding metropolises)" },
    staedtische_kreise: { index: 2, name: "Städtische Kreise", description: "Urban districts" },
    laendliche_verdichtung: { index: 3, name: "Ländliche Kreise mit Verdichtungsansätzen", description: "Rural districts with density features" },
    duenn_besiedelt: { index: 4, name: "Dünn besiedelte ländliche Kreise", description: "Sparsely populated rural districts" }
  }.freeze

  # German metropolises (7 largest cities)
  METROPOLEN = %w[
    BERLIN HAMBURG MUNICH MÜNCHEN COLOGNE KÖLN FRANKFURT
    STUTTGART DÜSSELDORF DUSSELDORF
  ].freeze

  # Major cities that are "kreisfreie Großstädte" but not metropolises
  LARGE_CITIES = %w[
    HANNOVER HANOVER NÜRNBERG NUREMBERG BREMEN DRESDEN LEIPZIG
    DORTMUND ESSEN DUISBURG BOCHUM WUPPERTAL BIELEFELD BONN
    MÜNSTER KARLSRUHE MANNHEIM AUGSBURG WIESBADEN GELSENKIRCHEN
    MÖNCHENGLADBACH BRAUNSCHWEIG KIEL CHEMNITZ AACHEN HALLE
    MAGDEBURG FREIBURG KREFELD LÜBECK OBERHAUSEN ERFURT
    MAINZ ROSTOCK KASSEL SAARBRÜCKEN HAGEN HAMM MÜLHEIM
    POTSDAM LUDWIGSHAFEN OLDENBURG LEVERKUSEN OSNABRÜCK
    SOLINGEN HEIDELBERG HERNE NEUSS DARMSTADT PADERBORN
    REGENSBURG INGOLSTADT WÜRZBURG WOLFSBURG FÜRTH ULM
    HEILBRONN GÖTTINGEN PFORZHEIM OFFENBACH BOTTROP REUTLINGEN
    REMSCHEID BREMERHAVEN KOBLENZ BERGISCH GLADBACH JENA TRIER
    ERLANGEN MOERS SALZGITTER SIEGEN COTTBUS HILDESHEIM
  ].freeze

  def healthy?
    with_provider_response do
      response = client.get(BASE_URL, { ids: INDICATORS[:apartment] })
      response.status == 200
    end
  end

  def fetch_house_price_index(region:, date:, property_type: :apartment)
    with_provider_response do
      indicator = INDICATORS[property_type] || INDICATORS[:apartment]
      district_type = region_to_district_type(region)

      response = client.get(BASE_URL, { ids: indicator })
      parse_single_index(response, region, date, district_type)
    end
  end

  def fetch_house_price_indices(region:, start_date:, end_date:, property_type: :apartment)
    with_provider_response do
      fetch_indices_internal(region: region, start_date: start_date, end_date: end_date, property_type: property_type)
    end
  end

  # Internal method for fetching indices without provider response wrapper
  def fetch_indices_internal(region:, start_date:, end_date:, property_type: :apartment)
    indicator = INDICATORS[property_type] || INDICATORS[:apartment]
    district_type = region_to_district_type(region)

    Rails.logger.info("DashboardDeutschland: Fetching #{property_type} data for district_type=#{district_type}, period=#{start_date} to #{end_date}")

    response = client.get(BASE_URL, { ids: indicator })
    indices = parse_indices(response, region, district_type, start_date, end_date)

    Rails.logger.info("DashboardDeutschland: Parsed #{indices.size} indices")
    indices
  rescue Faraday::Error => e
    Rails.logger.error("DashboardDeutschland API error: #{e.class} - #{e.message}")
    nil
  rescue JSON::ParserError => e
    Rails.logger.error("DashboardDeutschland JSON parse error: #{e.message}")
    nil
  end

  def calculate_growth_rate(region:, years: 5, property_type: :apartment)
    with_provider_response do
      end_date = Date.current
      start_date = end_date - years.years

      # Fetch indices directly without wrapping in another provider response
      indices = fetch_indices_internal(
        region: region,
        start_date: start_date,
        end_date: end_date,
        property_type: property_type
      )

      return nil if indices.nil? || indices.empty? || indices.size < 2

      # Filter to requested date range
      filtered = indices.select { |idx| idx.date >= start_date && idx.date <= end_date }
      return nil if filtered.size < 2

      # Sort by date and get first and last
      sorted = filtered.sort_by(&:date)
      first_index = sorted.first
      last_index = sorted.last

      Rails.logger.info("DashboardDeutschland: Found #{filtered.size} data points from #{first_index.date} to #{last_index.date}")
      Rails.logger.info("DashboardDeutschland: Index values - start: #{first_index.index_value}, end: #{last_index.index_value}")

      # Calculate CAGR
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
    # Only supports German regions
    region_str = region.to_s.upcase
    region_str == "DE" || region_str.start_with?("DE_") || is_german_city?(region_str)
  end

  # Check if a city name is a German metropolis
  def is_metropolis?(city_name)
    normalized = normalize_city_name(city_name)
    METROPOLEN.any? { |city| normalized.include?(normalize_city_name(city)) }
  end

  # Check if a city is a large city (kreisfreie Großstadt)
  def is_large_city?(city_name)
    normalized = normalize_city_name(city_name)
    LARGE_CITIES.any? { |city| normalized.include?(normalize_city_name(city)) }
  end

  # Determine district type based on city/region
  def region_to_district_type(region)
    region_str = region.to_s.upcase

    if is_metropolis?(region_str)
      :metropolen
    elsif is_large_city?(region_str)
      :grossstaedte
    elsif region_str == "DE" || region_str == "DE_URBAN"
      :staedtische_kreise  # Default to urban for generic Germany
    elsif region_str == "DE_RURAL"
      :laendliche_verdichtung
    elsif region_str == "DE_SPARSE"
      :duenn_besiedelt
    else
      # Default to urban districts for unknown regions
      :staedtische_kreise
    end
  end

  # Get human-readable district type name
  def district_type_name(district_type)
    DISTRICT_TYPES[district_type]&.dig(:name) || "Unknown"
  end

  private

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

    def normalize_city_name(name)
      name.to_s.upcase.gsub(/[^A-Z]/, "")
    end

    def is_german_city?(name)
      is_metropolis?(name) || is_large_city?(name)
    end

    def timestamp_to_date(timestamp_ms)
      Time.at(timestamp_ms / 1000).to_date
    end

    def date_to_end_of_quarter(date)
      quarter = ((date.month - 1) / 3) + 1
      end_month = quarter * 3
      Date.new(date.year, end_month, 1).end_of_month
    end

    def parse_single_index(response, region, date, district_type)
      data = JSON.parse(response.body)

      series = find_series_for_district_type(data, district_type)
      return nil unless series

      # Find the data point closest to the requested date
      target_quarter_end = date_to_end_of_quarter(date)
      closest = series.min_by { |point| (timestamp_to_date(point[0]) - target_quarter_end).abs }
      return nil unless closest

      HousePriceIndex.new(
        region: region,
        date: timestamp_to_date(closest[0]),
        index_value: closest[1].to_f,
        base_year: BASE_YEAR
      )
    end

    def parse_indices(response, region, district_type, start_date, end_date)
      data = JSON.parse(response.body)

      series = find_series_for_district_type(data, district_type)
      return [] unless series

      series.filter_map do |point|
        timestamp, value = point
        next unless timestamp && value

        date = timestamp_to_date(timestamp)
        next if date < start_date || date > end_date

        HousePriceIndex.new(
          region: region,
          date: date,
          index_value: value.to_f,
          base_year: BASE_YEAR
        )
      end
    end

    def find_series_for_district_type(data, district_type)
      # The API returns an array with one indicator object
      indicator = data.is_a?(Array) ? data.first : data
      return nil unless indicator

      # The actual data is inside a nested JSON string in the "json" field
      json_string = indicator["json"]
      return nil unless json_string.present?

      nested_data = JSON.parse(json_string)
      components = nested_data["components"]
      return nil unless components.is_a?(Array) && components.any?

      # Get the first component's series
      component = components.first
      all_series = component["series"]

      # If series is empty, try to get data from dataPlatformQueryParams
      # Note: Dashboard Deutschland requires authentication for actual data
      if all_series.nil? || all_series.empty?
        Rails.logger.info("DashboardDeutschland: Series data is empty (API may require authentication)")
        return nil
      end

      # Get the series index for this district type
      series_index = DISTRICT_TYPES.dig(district_type, :index)
      return nil unless series_index

      # Get the data points from the correct series
      target_series = all_series[series_index]
      return nil unless target_series

      target_series["data"]
    rescue JSON::ParserError => e
      Rails.logger.error("DashboardDeutschland: Failed to parse nested JSON: #{e.message}")
      nil
    end
end
