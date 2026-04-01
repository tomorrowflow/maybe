module Property::Provided
  extend ActiveSupport::Concern

  GROWTH_RATE_CACHE_TTL = 24.hours

  included do
    after_commit :fetch_regional_growth_rate_later, on: [ :create, :update ], if: :should_fetch_growth_rate?
  end

  class_methods do
    # Returns a single provider (first available) - for backwards compatibility
    def house_price_provider(region: nil, city: nil)
      house_price_providers(region: region, city: city).first
    end

    # Returns all available providers in priority order
    def house_price_providers(region: nil, city: nil)
      registry = Provider::Registry.for_concept(:house_prices)
      providers = []

      # For German properties, prefer Dashboard Deutschland, then Bundesbank, then Eurostat
      if region.present? && is_german_region?(region)
        # Try Dashboard Deutschland first (quarterly, district-type granularity)
        begin
          provider = registry.get_provider(:dashboard_deutschland)
          providers << provider if provider.present?
        rescue Provider::Registry::Error
          # Provider not available
        end

        # Then Bundesbank (annual, 127-cities aggregate)
        begin
          provider = registry.get_provider(:bundesbank)
          providers << provider if provider.present?
        rescue Provider::Registry::Error
          # Provider not available
        end
      end

      # Eurostat for all European countries (including German fallback)
      begin
        provider = registry.get_provider(:eurostat)
        providers << provider if provider.present?
      rescue Provider::Registry::Error
        # Provider not available
      end

      providers
    rescue Provider::Registry::Error
      []
    end

    def is_german_region?(region)
      return false unless region.present?
      region_str = region.to_s.upcase
      region_str == "DE" || region_str.start_with?("DE_")
    end

    def refresh_all_growth_rates
      Property.includes(:address).find_each do |property|
        property.fetch_regional_growth_rate(force: true)
      end
    end
  end

  def regional_growth_rate(years: 5, force: false)
    region = effective_region_code
    return nil unless region.present?

    cache_key = regional_growth_rate_cache_key(region, years)

    if force
      fetch_and_cache_growth_rate(region, years, cache_key)
    else
      Rails.cache.fetch(cache_key, expires_in: GROWTH_RATE_CACHE_TTL) do
        fetch_growth_rate_from_provider(region, years)
      end
    end
  end

  # Returns the effective region code for HPI lookup
  # For German properties, includes the city name for district type classification
  def effective_region_code
    base_code = country_code
    return nil unless base_code.present?

    # For German properties, return the city name for better district type classification
    if base_code == "DE" && address&.locality.present?
      return address.locality.upcase
    end

    base_code
  end

  # Returns the district type for German properties
  def german_district_type
    return nil unless country_code == "DE"

    provider = Provider::DashboardDeutschland.new rescue nil
    return nil unless provider

    city = address&.locality
    return :staedtische_kreise unless city.present?

    provider.region_to_district_type(city)
  end

  # Returns human-readable district type name
  def german_district_type_name
    district_type = german_district_type
    return nil unless district_type

    Provider::DashboardDeutschland::DISTRICT_TYPES.dig(district_type, :name)
  end

  def fetch_regional_growth_rate(force: false)
    regional_growth_rate(force: force)
  end

  # Returns a user-friendly description of the data source
  def growth_rate_source
    region = effective_region_code
    return nil unless region.present?

    if self.class.is_german_region?(country_code)
      district_name = german_district_type_name
      if district_name
        "Destatis (#{district_name})"
      else
        "Destatis"
      end
    else
      "Eurostat"
    end
  end

  def regional_house_price_index
    provider = self.class.house_price_provider(region: country_code, city: address&.locality)
    return nil unless provider.present?

    region = effective_region_code
    return nil unless region.present?
    return nil unless provider.supported_region?(region)

    provider_name = provider.class.name.demodulize.underscore
    cache_key = "#{provider_name}/hpi/#{region}/#{Date.current.beginning_of_quarter}"

    Rails.cache.fetch(cache_key, expires_in: GROWTH_RATE_CACHE_TTL) do
      response = provider.fetch_house_price_index(region: region, date: Date.current)
      response.success? ? response.data : nil
    end
  rescue => e
    Rails.logger.warn("Failed to fetch house price index for #{region}: #{e.message}")
    nil
  end

  private

    def regional_growth_rate_cache_key(region, years)
      provider_key = if self.class.is_german_region?(country_code)
        "dashboard_deutschland"
      else
        "eurostat"
      end
      "#{provider_key}/growth_rate/#{region}/#{years}y/#{Date.current.beginning_of_quarter}"
    end

    def fetch_and_cache_growth_rate(region, years, cache_key)
      rate = fetch_growth_rate_from_provider(region, years)
      Rails.cache.write(cache_key, rate, expires_in: GROWTH_RATE_CACHE_TTL) if rate
      rate
    end

    def fetch_growth_rate_from_provider(region, years)
      providers = self.class.house_price_providers(region: country_code, city: address&.locality)
      return nil if providers.empty?

      providers.each do |provider|
        next unless provider.present?
        next unless provider.supported_region?(region)

        provider_name = provider.class.name.demodulize

        Rails.logger.info("Fetching HPI from #{provider_name} for region: #{region}, years: #{years}")

        begin
          response = provider.calculate_growth_rate(region: region, years: years)

          if response&.success? && response.data&.annual_rate.present?
            rate = response.data.annual_rate
            Rails.logger.info("#{provider_name} HPI result for #{region}: #{rate}% annual growth (#{response.data&.period_start} to #{response.data&.period_end})")
            return rate
          else
            Rails.logger.info("#{provider_name} returned no data for #{region}, trying next provider...")
          end
        rescue => e
          Rails.logger.warn("#{provider_name} failed for #{region}: #{e.message}, trying next provider...")
        end
      end

      Rails.logger.warn("No provider returned valid growth rate for #{region}")
      nil
    end

    def should_fetch_growth_rate?
      Setting.eurostat_enabled && country_code.present?
    end

    def fetch_regional_growth_rate_later
      FetchPropertyGrowthRateJob.perform_later(id)
    end
end
