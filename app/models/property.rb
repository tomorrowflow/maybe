class Property < ApplicationRecord
  include Accountable, Provided

  SUBTYPES = {
    "single_family_home" => { short: "Single Family Home", long: "Single Family Home" },
    "multi_family_home" => { short: "Multi-Family Home", long: "Multi-Family Home" },
    "condominium" => { short: "Condo", long: "Condominium" },
    "townhouse" => { short: "Townhouse", long: "Townhouse" },
    "investment_property" => { short: "Investment Property", long: "Investment Property" },
    "second_home" => { short: "Second Home", long: "Second Home" }
  }.freeze

  has_one :address, as: :addressable, dependent: :destroy

  accepts_nested_attributes_for :address

  attribute :area_unit, :string

  class << self
    def icon
      "home"
    end

    def color
      "#06AED4"
    end

    def classification
      "asset"
    end
  end

  def area
    Measurement.new(area_value, area_unit) if area_value.present?
  end

  def country_code
    return nil unless address&.country.present?

    # Try to extract 2-letter country code
    # Address country might be full name or ISO code
    country = address.country.to_s.strip.upcase
    return country if country.length == 2

    # Map common country names to ISO codes
    COUNTRY_NAME_TO_CODE[country] || nil
  end

  COUNTRY_NAME_TO_CODE = {
    "GERMANY" => "DE",
    "DEUTSCHLAND" => "DE",
    "FRANCE" => "FR",
    "ITALY" => "IT",
    "ITALIA" => "IT",
    "SPAIN" => "ES",
    "ESPANA" => "ES",
    "NETHERLANDS" => "NL",
    "AUSTRIA" => "AT",
    "OSTERREICH" => "AT",
    "BELGIUM" => "BE",
    "POLAND" => "PL",
    "PORTUGAL" => "PT",
    "SWEDEN" => "SE",
    "DENMARK" => "DK",
    "FINLAND" => "FI",
    "IRELAND" => "IE",
    "GREECE" => "GR",
    "CZECHIA" => "CZ",
    "CZECH REPUBLIC" => "CZ",
    "ROMANIA" => "RO",
    "HUNGARY" => "HU",
    "CROATIA" => "HR",
    "SLOVAKIA" => "SK",
    "SLOVENIA" => "SI",
    "BULGARIA" => "BG",
    "LITHUANIA" => "LT",
    "LATVIA" => "LV",
    "ESTONIA" => "EE",
    "LUXEMBOURG" => "LU",
    "CYPRUS" => "CY",
    "MALTA" => "MT",
    "NORWAY" => "NO",
    "SWITZERLAND" => "CH",
    "ICELAND" => "IS",
    "UNITED KINGDOM" => "UK",
    "UK" => "UK"
  }.freeze

  def purchase_price
    first_valuation_amount
  end

  def trend
    Trend.new(current: estimated_current_value, previous: first_valuation_amount)
  end

  # Returns the estimated current value based on Eurostat HPI growth
  # Falls back to actual balance if no projection available
  def estimated_current_value
    projected = projected_value_from_hpi
    projected.present? ? projected : account.balance_money
  end

  # Calculate projected value using Eurostat regional growth rate
  def projected_value_from_hpi
    return nil unless purchase_price.present?
    return nil unless purchase_date.present? || first_valuation_date.present?

    growth_rate = regional_growth_rate
    return nil unless growth_rate.present?

    start_date = purchase_date || first_valuation_date
    years_held = (Date.current - start_date).to_f / 365.25
    return nil if years_held <= 0

    # Compound growth: FV = PV * (1 + r)^n
    annual_rate = growth_rate / 100.0
    projected_amount = purchase_price.amount * ((1 + annual_rate) ** years_held)

    Money.new(projected_amount.round(2), purchase_price.currency)
  end

  def balance_display_name
    "market value"
  end

  def opening_balance_display_name
    "original purchase price"
  end

  def uses_hpi_projection?
    projected_value_from_hpi.present?
  end

  # Generate HPI-based valuations as activity entries
  # For Eurostat: quarterly valuations (quarterly data available)
  # For Bundesbank: annual valuations (only annual data available)
  def generate_hpi_valuations
    return unless uses_hpi_projection?
    return unless purchase_price.present?

    start_date = purchase_date || first_valuation_date
    return unless start_date.present?

    # Fetch HPI indices from provider
    indices = fetch_hpi_indices(start_date)
    return if indices.blank? || indices.size < 2

    # Find the index closest to purchase date
    purchase_index = find_index_for_date(indices, start_date)
    return unless purchase_index.present?

    purchase_amount = purchase_price.amount
    currency = purchase_price.currency.to_s
    source_name = growth_rate_source

    Rails.logger.info("Generating HPI valuations for property #{id}: purchase_index=#{purchase_index.index_value} at #{purchase_index.date}, source=#{source_name}")

    # Create valuations for each data point after purchase
    valuations_created = 0
    indices.select { |idx| idx.date > start_date }.each do |idx|
      # Calculate property value: purchase_price * (current_index / purchase_index)
      ratio = idx.index_value / purchase_index.index_value
      projected_value = (purchase_amount * ratio).round(2)

      # Skip if a valuation already exists for this date (or within a week to handle quarterly vs specific dates)
      existing = account.entries.valuations.where(date: (idx.date - 7.days)..(idx.date + 7.days)).exists?
      next if existing

      # Create valuation entry
      account.entries.create!(
        date: idx.date,
        amount: projected_value,
        currency: currency,
        name: "HPI Valuation (#{source_name})",
        entryable: Valuation.new(kind: "reconciliation")
      )

      valuations_created += 1
      Rails.logger.debug("Created HPI valuation: #{idx.date} -> #{projected_value} (ratio: #{ratio.round(4)})")
    end

    Rails.logger.info("Created #{valuations_created} HPI valuations for property #{id}")
    valuations_created
  end

  # Fetch HPI indices from available providers (tries each until one returns data)
  # Eurostat provides quarterly data, Bundesbank provides annual data
  def fetch_hpi_indices(since_date)
    region = effective_region_code
    return [] unless region.present?

    providers = self.class.house_price_providers(region: country_code, city: address&.locality)
    return [] if providers.empty?

    providers.each do |provider|
      next unless provider.present?
      next unless provider.supported_region?(region)

      provider_name = provider.class.name.demodulize

      begin
        response = provider.fetch_house_price_indices(
          region: region,
          start_date: since_date - 1.year, # Get a bit before purchase for better baseline
          end_date: Date.current
        )

        if response&.success? && response.data.present? && response.data.any?
          indices = response.data

          # Filter to only include indices within the requested range
          filtered = indices.select { |idx| idx.date >= (since_date - 1.year) && idx.date <= Date.current }

          if filtered.any?
            Rails.logger.info("#{provider_name} returned #{filtered.size} HPI indices for #{region}")
            return filtered
          end
        end

        Rails.logger.info("#{provider_name} returned no HPI indices for #{region}, trying next provider...")
      rescue => e
        Rails.logger.warn("#{provider_name} failed to fetch HPI indices for #{region}: #{e.message}, trying next provider...")
      end
    end

    Rails.logger.warn("No provider returned HPI indices for #{region}")
    []
  end

  # Find the index value closest to (but not after) a given date
  def find_index_for_date(indices, target_date)
    sorted = indices.sort_by(&:date)
    # Find the last index on or before the target date, or the first available
    sorted.select { |idx| idx.date <= target_date }.last || sorted.first
  end

  # Generate projected balance records based on HPI growth
  # This creates balance entries showing how the property value should have grown
  def generate_hpi_projected_balances
    return unless uses_hpi_projection?

    growth_rate = regional_growth_rate
    return unless growth_rate.present?

    start_date = purchase_date || first_valuation_date
    return unless start_date.present?

    purchase_amount = purchase_price.amount
    currency = purchase_price.currency.to_s
    annual_rate = growth_rate / 100.0
    now = Time.current

    # Generate monthly balance records from purchase date to today
    current_date = start_date
    balances_to_create = []
    previous_balance = purchase_amount

    while current_date <= Date.current
      years_elapsed = (current_date - start_date).to_f / 365.25
      projected_balance = purchase_amount * ((1 + annual_rate) ** years_elapsed)

      balances_to_create << build_balance_record(
        date: current_date,
        start_balance: previous_balance,
        end_balance: projected_balance,
        currency: currency,
        now: now
      )

      previous_balance = projected_balance
      current_date = current_date.next_month.beginning_of_month
    end

    # Add today's balance if not already included
    if balances_to_create.last&.dig(:date) != Date.current
      years_elapsed = (Date.current - start_date).to_f / 365.25
      projected_balance = purchase_amount * ((1 + annual_rate) ** years_elapsed)

      balances_to_create << build_balance_record(
        date: Date.current,
        start_balance: previous_balance,
        end_balance: projected_balance,
        currency: currency,
        now: now
      )
    end

    # Delete existing balances and insert projected ones
    account.balances.delete_all
    Balance.insert_all(balances_to_create) if balances_to_create.any?

    Rails.logger.info("Generated #{balances_to_create.size} HPI projected balance records for property #{id}")
  end

  private
    def first_valuation_amount
      account.entries.valuations.order(:date).first&.amount_money || account.balance_money
    end

    def first_valuation_date
      account.entries.valuations.order(:date).first&.date
    end

    def build_balance_record(date:, start_balance:, end_balance:, currency:, now:)
      # For properties (non-cash balance type), value is tracked in non_cash fields
      adjustment = end_balance - start_balance

      {
        account_id: account.id,
        date: date,
        balance: end_balance.round(2),
        cash_balance: 0,
        currency: currency,
        start_cash_balance: 0,
        start_non_cash_balance: start_balance.round(2),
        cash_inflows: 0,
        cash_outflows: 0,
        non_cash_inflows: 0,
        non_cash_outflows: 0,
        net_market_flows: 0,
        cash_adjustments: 0,
        non_cash_adjustments: adjustment.round(2),
        flows_factor: 1,
        created_at: now,
        updated_at: now
      }
    end
end
