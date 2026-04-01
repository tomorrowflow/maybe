require "test_helper"

class Provider::DashboardDeutschlandTest < ActiveSupport::TestCase
  include HousePriceProviderInterfaceTest

  setup do
    @subject = @provider = Provider::DashboardDeutschland.new
  end

  test "health check" do
    VCR.use_cassette("dashboard_deutschland/health") do
      assert @provider.healthy?
    end
  end

  test "supports German regions" do
    assert @provider.supported_region?("DE")
    assert @provider.supported_region?("DE_URBAN")
    assert @provider.supported_region?("DE_RURAL")
  end

  test "supports German cities" do
    assert @provider.supported_region?("BERLIN")
    assert @provider.supported_region?("MUNICH")
    assert @provider.supported_region?("HAMBURG")
    assert @provider.supported_region?("HANNOVER")
  end

  test "does not support non-German regions" do
    assert_not @provider.supported_region?("FR")
    assert_not @provider.supported_region?("US")
    assert_not @provider.supported_region?("IT")
  end

  test "classifies metropolises correctly" do
    assert @provider.is_metropolis?("BERLIN")
    assert @provider.is_metropolis?("berlin")
    assert @provider.is_metropolis?("HAMBURG")
    assert @provider.is_metropolis?("MUNICH")
    assert @provider.is_metropolis?("MÜNCHEN")
    assert @provider.is_metropolis?("COLOGNE")
    assert @provider.is_metropolis?("KÖLN")
    assert @provider.is_metropolis?("FRANKFURT")
    assert @provider.is_metropolis?("STUTTGART")
    assert @provider.is_metropolis?("DÜSSELDORF")
    assert @provider.is_metropolis?("DUSSELDORF")
  end

  test "does not classify non-metropolises as metropolises" do
    assert_not @provider.is_metropolis?("HANNOVER")
    assert_not @provider.is_metropolis?("DRESDEN")
    assert_not @provider.is_metropolis?("BONN")
  end

  test "classifies large cities correctly" do
    assert @provider.is_large_city?("HANNOVER")
    assert @provider.is_large_city?("DRESDEN")
    assert @provider.is_large_city?("LEIPZIG")
    assert @provider.is_large_city?("BREMEN")
    assert @provider.is_large_city?("NÜRNBERG")
    assert @provider.is_large_city?("NUREMBERG")
  end

  test "maps metropolises to correct district type" do
    assert_equal :metropolen, @provider.region_to_district_type("BERLIN")
    assert_equal :metropolen, @provider.region_to_district_type("MUNICH")
  end

  test "maps large cities to grossstaedte" do
    assert_equal :grossstaedte, @provider.region_to_district_type("HANNOVER")
    assert_equal :grossstaedte, @provider.region_to_district_type("DRESDEN")
  end

  test "maps generic DE to staedtische_kreise" do
    assert_equal :staedtische_kreise, @provider.region_to_district_type("DE")
  end

  test "maps DE_URBAN to staedtische_kreise" do
    assert_equal :staedtische_kreise, @provider.region_to_district_type("DE_URBAN")
  end

  test "maps DE_RURAL to laendliche_verdichtung" do
    assert_equal :laendliche_verdichtung, @provider.region_to_district_type("DE_RURAL")
  end

  test "maps DE_SPARSE to duenn_besiedelt" do
    assert_equal :duenn_besiedelt, @provider.region_to_district_type("DE_SPARSE")
  end

  test "defaults unknown regions to staedtische_kreise" do
    assert_equal :staedtische_kreise, @provider.region_to_district_type("UNKNOWN_CITY")
  end

  test "returns correct district type names" do
    assert_equal "Metropolen", @provider.district_type_name(:metropolen)
    assert_equal "Kreisfreie Großstädte", @provider.district_type_name(:grossstaedte)
    assert_equal "Städtische Kreise", @provider.district_type_name(:staedtische_kreise)
    assert_equal "Ländliche Kreise mit Verdichtungsansätzen", @provider.district_type_name(:laendliche_verdichtung)
    assert_equal "Dünn besiedelte ländliche Kreise", @provider.district_type_name(:duenn_besiedelt)
  end
end
