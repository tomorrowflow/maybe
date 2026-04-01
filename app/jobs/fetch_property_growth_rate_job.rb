class FetchPropertyGrowthRateJob < ApplicationJob
  queue_as :default

  def perform(property_id)
    property = Property.find_by(id: property_id)
    return unless property.present?
    return unless Setting.eurostat_enabled

    Rails.logger.info("FetchPropertyGrowthRateJob: Processing property #{property_id}, country_code: #{property.country_code}")

    # Fetch and cache the growth rate
    growth_rate = property.fetch_regional_growth_rate(force: true)
    Rails.logger.info("FetchPropertyGrowthRateJob: Growth rate fetched: #{growth_rate}")

    # Trigger a sync to update balances with HPI projection
    # The Account::Syncer will detect HPI projection and use it for balance calculation
    if property.uses_hpi_projection? && property.account.present?
      Rails.logger.info("FetchPropertyGrowthRateJob: Triggering account sync to apply HPI projection")
      property.account.sync_later
    end
  end
end
