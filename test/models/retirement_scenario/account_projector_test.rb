require "test_helper"

class RetirementScenario::AccountProjectorTest < ActiveSupport::TestCase
  setup do
    @depository_account = accounts(:depository)
    @investment_account = accounts(:investment)
  end

  test "returns fallback rate when account has no custom rate" do
    # Ensure the account has no custom rate set
    @depository_account.accountable.update!(interest_rate: nil)

    projector = RetirementScenario::AccountProjector.new(@depository_account, fallback_growth_rate: 7.0)

    assert_equal 7.0, projector.annual_growth_rate
    assert_not projector.has_custom_rate?
  end

  test "returns custom rate when depository has interest_rate set" do
    @depository_account.accountable.update!(interest_rate: 2.5)

    projector = RetirementScenario::AccountProjector.new(@depository_account, fallback_growth_rate: 7.0)

    assert_equal 2.5, projector.annual_growth_rate
    assert projector.has_custom_rate?
  end

  test "returns custom rate when investment has expected_growth_rate set" do
    @investment_account.accountable.update!(expected_growth_rate: 10.0)

    projector = RetirementScenario::AccountProjector.new(@investment_account, fallback_growth_rate: 7.0)

    assert_equal 10.0, projector.annual_growth_rate
    assert projector.has_custom_rate?
  end

  test "calculates correct monthly growth rate" do
    @investment_account.accountable.update!(expected_growth_rate: 12.0)

    projector = RetirementScenario::AccountProjector.new(@investment_account)

    # 12% annual = 1% monthly
    assert_in_delta 0.01, projector.monthly_growth_rate, 0.0001
  end

  test "projects value forward correctly with compound growth" do
    @depository_account.accountable.update!(interest_rate: 12.0)  # 12% annual for easy math
    @depository_account.update!(balance: 10000)

    projector = RetirementScenario::AccountProjector.new(@depository_account)

    # After 12 months at 12% annual (1% monthly), should be approximately 10000 * 1.01^12
    projected = projector.project_value(months: 12, contribution_amount: 0)

    expected = 10000 * (1.01 ** 12)  # ~11268.25
    assert_in_delta expected, projected, 1.0
  end

  test "projects value forward correctly with contributions" do
    @depository_account.accountable.update!(interest_rate: 0)  # No growth for simpler math
    @depository_account.update!(balance: 10000)

    projector = RetirementScenario::AccountProjector.new(@depository_account)

    # After 12 months at 0% growth with 100/month contribution
    projected = projector.project_value(months: 12, contribution_amount: 100)

    assert_equal 11200, projected  # 10000 + 12 * 100
  end

  test "generates month-by-month projections" do
    @investment_account.accountable.update!(expected_growth_rate: 7.0)
    @investment_account.update!(balance: 100000)

    projector = RetirementScenario::AccountProjector.new(@investment_account)
    projections = projector.generate_projections(months: 12, contribution_amount: 500)

    assert_equal 12, projections.length
    assert_equal 1, projections.first[:month]
    assert_equal 12, projections.last[:month]

    # Each projection should have required keys
    projections.each do |p|
      assert p.key?(:month)
      assert p.key?(:date)
      assert p.key?(:value)
      assert p.key?(:growth)
      assert p.key?(:contribution)
      assert p.key?(:growth_rate)
    end

    # Values should be increasing
    values = projections.map { |p| p[:value] }
    assert_equal values.sort, values
  end

  test "contribution_eligible returns true for asset accounts" do
    projector = RetirementScenario::AccountProjector.new(@depository_account)
    assert projector.contribution_eligible?
  end

  test "contribution_eligible returns false for liability accounts" do
    credit_card_account = accounts(:credit_card)
    projector = RetirementScenario::AccountProjector.new(credit_card_account)
    assert_not projector.contribution_eligible?
  end

  test "current_value returns account balance" do
    @investment_account.update!(balance: 50000)

    projector = RetirementScenario::AccountProjector.new(@investment_account)

    assert_equal 50000, projector.current_value
  end
end
