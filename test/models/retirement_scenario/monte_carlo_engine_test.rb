require "test_helper"

class RetirementScenario::MonteCarloEngineTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)

    # Build a minimal scenario for testing (not persisted — tables may not exist yet)
    @scenario = RetirementScenario.new(
      family: @family,
      name: "Test Plan",
      calculation_date: Date.today,
      retirement_monthly_expenses: 4000,
      portfolio_growth_rate: 7.0,
      portfolio_growth_std_dev: 15.0,
      inflation_rate: 3.0,
      simulation_count: 100,
      target_age: 90
    )
  end

  test "returns valid result structure" do
    engine = RetirementScenario::MonteCarloEngine.new(@scenario, overrides: {
      current_portfolio_value: 500_000,
      simulation_count: 50
    })

    result = engine.run

    assert result.key?(:success_rate)
    assert result.key?(:simulation_count)
    assert result.key?(:years)
    assert result.key?(:percentiles)
    assert result.key?(:seed)
    assert result.key?(:ran_at)

    assert_equal 50, result[:simulation_count]
    assert_includes 0..100, result[:success_rate]

    # Percentile arrays exist and have correct length
    %w[p10 p25 p50 p75 p90].each do |key|
      assert result[:percentiles].key?(key), "Missing percentile #{key}"
      assert_equal result[:years].size, result[:percentiles][key].size
    end
  end

  test "success rate is rounded to nearest 5%" do
    engine = RetirementScenario::MonteCarloEngine.new(@scenario, overrides: {
      current_portfolio_value: 500_000,
      simulation_count: 100
    })

    result = engine.run

    assert_equal 0, result[:success_rate] % 5, "Success rate should be rounded to nearest 5%"
  end

  test "percentiles are ordered correctly at each year" do
    engine = RetirementScenario::MonteCarloEngine.new(@scenario, overrides: {
      current_portfolio_value: 500_000,
      simulation_count: 200
    })

    result = engine.run
    percentiles = result[:percentiles]

    result[:years].each_with_index do |_year, i|
      p10 = percentiles["p10"][i]
      p25 = percentiles["p25"][i]
      p50 = percentiles["p50"][i]
      p75 = percentiles["p75"][i]
      p90 = percentiles["p90"][i]

      assert p10 <= p25, "p10 (#{p10}) should be <= p25 (#{p25}) at year #{i}"
      assert p25 <= p50, "p25 (#{p25}) should be <= p50 (#{p50}) at year #{i}"
      assert p50 <= p75, "p50 (#{p50}) should be <= p75 (#{p75}) at year #{i}"
      assert p75 <= p90, "p75 (#{p75}) should be <= p90 (#{p90}) at year #{i}"
    end
  end

  test "zero expenses and no withdrawals yields 100% success" do
    engine = RetirementScenario::MonteCarloEngine.new(@scenario, overrides: {
      current_portfolio_value: 100_000,
      retirement_monthly_expenses: 0,
      simulation_count: 100
    })

    result = engine.run

    assert_equal 100, result[:success_rate]
  end

  test "zero portfolio with expenses yields 0% success" do
    engine = RetirementScenario::MonteCarloEngine.new(@scenario, overrides: {
      current_portfolio_value: 0,
      retirement_monthly_expenses: 5000,
      monthly_contribution: 0,
      simulation_count: 100
    })

    result = engine.run

    assert_equal 0, result[:success_rate]
  end

  test "very large portfolio relative to expenses yields high success rate" do
    engine = RetirementScenario::MonteCarloEngine.new(@scenario, overrides: {
      current_portfolio_value: 10_000_000,
      retirement_monthly_expenses: 1000,
      simulation_count: 200
    })

    result = engine.run

    assert result[:success_rate] >= 90, "Large portfolio should have high success rate, got #{result[:success_rate]}%"
  end

  test "all paths start with the same initial portfolio value" do
    engine = RetirementScenario::MonteCarloEngine.new(@scenario, overrides: {
      current_portfolio_value: 250_000,
      simulation_count: 50
    })

    result = engine.run

    # Year 0 should be the initial portfolio for all percentiles
    %w[p10 p25 p50 p75 p90].each do |key|
      assert_equal 250_000.0, result[:percentiles][key][0],
        "#{key} at year 0 should equal initial portfolio"
    end
  end

  test "higher growth rate increases success probability" do
    low_growth = RetirementScenario::MonteCarloEngine.new(@scenario, overrides: {
      current_portfolio_value: 300_000,
      portfolio_growth_rate: 3.0,
      simulation_count: 500
    }).run

    high_growth = RetirementScenario::MonteCarloEngine.new(@scenario, overrides: {
      current_portfolio_value: 300_000,
      portfolio_growth_rate: 10.0,
      simulation_count: 500
    }).run

    assert high_growth[:success_rate] >= low_growth[:success_rate],
      "Higher growth (#{high_growth[:success_rate]}%) should have >= success than lower growth (#{low_growth[:success_rate]}%)"
  end

  test "zero std_dev produces deterministic results" do
    engine = RetirementScenario::MonteCarloEngine.new(@scenario, overrides: {
      current_portfolio_value: 500_000,
      portfolio_growth_std_dev: 0,
      simulation_count: 10
    })

    result = engine.run

    # With zero volatility, all percentiles should be equal at every year
    result[:years].each_with_index do |_year, i|
      values = %w[p10 p25 p50 p75 p90].map { |k| result[:percentiles][k][i] }
      assert_equal 1, values.uniq.size,
        "With zero std_dev, all percentiles should be equal at year #{i}, got #{values}"
    end
  end

  test "depletion year is reported for failed paths" do
    engine = RetirementScenario::MonteCarloEngine.new(@scenario, overrides: {
      current_portfolio_value: 50_000,
      retirement_monthly_expenses: 10_000,
      portfolio_growth_rate: 2.0,
      portfolio_growth_std_dev: 5.0,
      monthly_contribution: 0,
      simulation_count: 200
    })

    result = engine.run

    if result[:success_rate] < 100
      assert_not_nil result[:worst_case_depletion_year],
        "Should report worst case depletion year when some paths fail"
      assert result[:worst_case_depletion_year] > 0,
        "Depletion year should be positive"
    end
  end

  test "respects max simulation count" do
    engine = RetirementScenario::MonteCarloEngine.new(@scenario, overrides: {
      current_portfolio_value: 100_000,
      simulation_count: 10_000  # Over MAX_SIMULATIONS
    })

    result = engine.run

    assert_equal RetirementScenario::MonteCarloEngine::MAX_SIMULATIONS, result[:simulation_count]
  end

  test "overrides take precedence over scenario values" do
    engine = RetirementScenario::MonteCarloEngine.new(@scenario, overrides: {
      current_portfolio_value: 999_999,
      retirement_monthly_expenses: 1,
      simulation_count: 20
    })

    result = engine.run

    # With huge portfolio and tiny expenses, should be 100%
    assert_equal 100, result[:success_rate]
  end
end
