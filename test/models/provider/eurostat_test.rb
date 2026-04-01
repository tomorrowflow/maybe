require "test_helper"

class Provider::EurostatTest < ActiveSupport::TestCase
  include HousePriceProviderInterfaceTest

  setup do
    @subject = @eurostat = Provider::Eurostat.new
  end

  test "health check" do
    VCR.use_cassette("eurostat/health") do
      assert @eurostat.healthy?
    end
  end

  test "supports EU countries" do
    assert @eurostat.supported_region?("DE")
    assert @eurostat.supported_region?("FR")
    assert @eurostat.supported_region?("IT")
    assert @eurostat.supported_region?("ES")
    assert @eurostat.supported_region?("EU")
  end

  test "does not support non-EU countries" do
    assert_not @eurostat.supported_region?("US")
    assert_not @eurostat.supported_region?("CN")
    assert_not @eurostat.supported_region?("JP")
  end

  test "maps Greece country code to EL" do
    assert_equal "EL", @eurostat.send(:eurostat_geo_code, "GR")
  end

  test "maps EU to EU27_2020" do
    assert_equal "EU27_2020", @eurostat.send(:eurostat_geo_code, "EU")
  end

  test "converts date to quarter format" do
    assert_equal "2024-Q1", @eurostat.send(:date_to_quarter, Date.new(2024, 1, 15))
    assert_equal "2024-Q2", @eurostat.send(:date_to_quarter, Date.new(2024, 4, 1))
    assert_equal "2024-Q3", @eurostat.send(:date_to_quarter, Date.new(2024, 9, 30))
    assert_equal "2024-Q4", @eurostat.send(:date_to_quarter, Date.new(2024, 12, 31))
  end

  test "converts quarter string to end of quarter date" do
    assert_equal Date.new(2024, 3, 31), @eurostat.send(:quarter_to_date, "2024-Q1")
    assert_equal Date.new(2024, 6, 30), @eurostat.send(:quarter_to_date, "2024-Q2")
    assert_equal Date.new(2024, 9, 30), @eurostat.send(:quarter_to_date, "2024-Q3")
    assert_equal Date.new(2024, 12, 31), @eurostat.send(:quarter_to_date, "2024-Q4")
  end
end
