class Address < ApplicationRecord
  belongs_to :addressable, polymorphic: true

  after_commit :notify_property_of_country_change, on: [ :create, :update ], if: :should_notify_property?

  def to_s
    string = I18n.t("address.format",
      line1: line1,
      line2: line2,
      county: county,
      locality: locality,
      region: region,
      country: country,
      postal_code: postal_code
    )

    # Clean up the string to maintain I18n comma formatting
    string.split(",").map(&:strip).reject(&:empty?).join(", ")
  end

  private

    def should_notify_property?
      addressable_type == "Property" && saved_change_to_country?
    end

    def notify_property_of_country_change
      return unless Setting.eurostat_enabled
      return unless addressable.country_code.present?

      FetchPropertyGrowthRateJob.perform_later(addressable.id)
    end
end
