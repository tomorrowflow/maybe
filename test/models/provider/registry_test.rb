require "test_helper"

class Provider::RegistryTest < ActiveSupport::TestCase
  test "synth configured with ENV" do
    Setting.stubs(:synth_api_key).returns(nil)

    with_env_overrides SYNTH_API_KEY: "123" do
      assert_instance_of Provider::Synth, Provider::Registry.get_provider(:synth)
    end
  end

  test "synth configured with Setting" do
    Setting.stubs(:synth_api_key).returns("123")

    with_env_overrides SYNTH_API_KEY: nil do
      assert_instance_of Provider::Synth, Provider::Registry.get_provider(:synth)
    end
  end

  test "synth not configured" do
    Setting.stubs(:synth_api_key).returns(nil)

    with_env_overrides SYNTH_API_KEY: nil do
      assert_nil Provider::Registry.get_provider(:synth)
    end
  end

  test "eurostat configured with ENV" do
    Setting.stubs(:eurostat_enabled).returns(false)

    with_env_overrides EUROSTAT_ENABLED: "true" do
      assert_instance_of Provider::Eurostat, Provider::Registry.get_provider(:eurostat)
    end
  end

  test "eurostat configured with Setting" do
    Setting.stubs(:eurostat_enabled).returns(true)

    with_env_overrides EUROSTAT_ENABLED: nil do
      assert_instance_of Provider::Eurostat, Provider::Registry.get_provider(:eurostat)
    end
  end

  test "eurostat not configured" do
    Setting.stubs(:eurostat_enabled).returns(false)

    with_env_overrides EUROSTAT_ENABLED: nil do
      assert_nil Provider::Registry.get_provider(:eurostat)
    end
  end

  test "house_prices concept returns eurostat provider" do
    Setting.stubs(:eurostat_enabled).returns(true)

    registry = Provider::Registry.for_concept(:house_prices)
    provider = registry.get_provider(:eurostat)

    assert_instance_of Provider::Eurostat, provider
  end
end
