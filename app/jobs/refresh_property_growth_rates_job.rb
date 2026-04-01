class RefreshPropertyGrowthRatesJob < ApplicationJob
  queue_as :scheduled

  def perform
    return unless Setting.eurostat_enabled

    Rails.logger.info("RefreshPropertyGrowthRatesJob: Starting HPI data refresh")

    # Refresh cached growth rates
    Property.refresh_all_growth_rates
    Rails.logger.info("RefreshPropertyGrowthRatesJob: Refreshed growth rates")

    # Update HPI valuations for properties that use HPI projection
    properties_updated = update_hpi_valuations
    Rails.logger.info("RefreshPropertyGrowthRatesJob: Updated #{properties_updated} properties with new HPI valuations")
  end

  private

    def update_hpi_valuations
      properties_with_hpi = Property.includes(:account, :address).select(&:uses_hpi_projection?)
      updated_count = 0

      properties_with_hpi.each do |property|
        begin
          # Check if there's new HPI data since the last valuation
          last_hpi_valuation = property.account.entries.valuations
            .where("name LIKE ?", "HPI Valuation%")
            .order(date: :desc)
            .first

          last_valuation_date = last_hpi_valuation&.date || property.purchase_date || property.send(:first_valuation_date)
          next unless last_valuation_date

          # Generate any new HPI valuations
          new_valuations = property.generate_hpi_valuations
          if new_valuations && new_valuations > 0
            # Trigger a sync to update balances
            property.account.sync_later
            updated_count += 1
            Rails.logger.info("RefreshPropertyGrowthRatesJob: Created #{new_valuations} new valuations for property #{property.id}")
          end
        rescue => e
          Rails.logger.error("RefreshPropertyGrowthRatesJob: Error updating property #{property.id}: #{e.message}")
        end
      end

      updated_count
    end
end
