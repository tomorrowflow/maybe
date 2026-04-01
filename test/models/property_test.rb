require "test_helper"

class PropertyTest < ActiveSupport::TestCase
  test "extracts country code from 2-letter address country" do
    property = Property.new
    property.build_address(country: "DE")

    assert_equal "DE", property.country_code
  end

  test "maps full country name to ISO code" do
    property = Property.new
    property.build_address(country: "Germany")

    assert_equal "DE", property.country_code
  end

  test "maps lowercase country name to ISO code" do
    property = Property.new
    property.build_address(country: "germany")

    assert_equal "DE", property.country_code
  end

  test "returns nil for unsupported country names" do
    property = Property.new
    property.build_address(country: "Unknown Country")

    assert_nil property.country_code
  end

  test "returns nil when no address" do
    property = Property.new

    assert_nil property.country_code
  end

  test "returns nil when address has no country" do
    property = Property.new
    property.build_address(line1: "123 Main St")

    assert_nil property.country_code
  end

  test "regional_growth_rate returns nil when provider not available" do
    Provider::Registry.stubs(:for_concept).raises(Provider::Registry::Error.new("No provider"))

    property = Property.new
    property.build_address(country: "DE")

    assert_nil property.regional_growth_rate
  end

  test "regional_growth_rate returns nil when country not supported" do
    property = Property.new
    property.build_address(country: "US")

    assert_nil property.regional_growth_rate
  end
end
