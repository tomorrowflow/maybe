module Provider::HousePriceConcept
  extend ActiveSupport::Concern

  HousePriceIndex = Data.define(:region, :date, :index_value, :base_year)
  GrowthRate = Data.define(:region, :annual_rate, :period_start, :period_end)

  # Fetch house price index for a region and date
  def fetch_house_price_index(region:, date:)
    raise NotImplementedError, "Subclasses must implement #fetch_house_price_index"
  end

  # Fetch historical indices for calculating growth
  def fetch_house_price_indices(region:, start_date:, end_date:)
    raise NotImplementedError, "Subclasses must implement #fetch_house_price_indices"
  end

  # Calculate annual growth rate from indices
  def calculate_growth_rate(region:, years: 5)
    raise NotImplementedError, "Subclasses must implement #calculate_growth_rate"
  end
end
