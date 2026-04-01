require "test_helper"

module HousePriceProviderInterfaceTest
  extend ActiveSupport::Testing::Declarative

  test "fetches single house price index" do
    VCR.use_cassette("#{vcr_key_prefix}/house_price_index") do
      response = @subject.fetch_house_price_index(
        region: "DE",
        date: Date.parse("01.01.2024")
      )

      assert response.success?
      index = response.data

      assert_equal "DE", index.region
      assert index.date.is_a?(Date)
      assert index.index_value.is_a?(Numeric)
      assert_equal 2015, index.base_year
    end
  end

  test "fetches house price indices range" do
    VCR.use_cassette("#{vcr_key_prefix}/house_price_indices") do
      response = @subject.fetch_house_price_indices(
        region: "DE",
        start_date: Date.parse("01.01.2019"),
        end_date: Date.parse("31.12.2023")
      )

      assert response.success?
      indices = response.data

      assert indices.is_a?(Array)
      assert indices.any?
      assert indices.first.is_a?(Provider::HousePriceConcept::HousePriceIndex)
    end
  end

  test "calculates growth rate" do
    VCR.use_cassette("#{vcr_key_prefix}/growth_rate") do
      response = @subject.calculate_growth_rate(
        region: "DE",
        years: 5
      )

      assert response.success?
      rate = response.data

      assert_equal "DE", rate.region
      assert rate.annual_rate.is_a?(Numeric)
      assert rate.period_start.is_a?(Date)
      assert rate.period_end.is_a?(Date)
    end
  end

  private
    def vcr_key_prefix
      @subject.class.name.demodulize.underscore
    end
end
