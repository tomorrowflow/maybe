require "test_helper"

class RetirementScenarioIncomeTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @scenario_with_gap = retirement_scenarios(:with_gap)
    @scenario_no_gap = retirement_scenarios(:conservative_plan)
  end

  test "detects gap period when salary ends before pension starts" do
    gap = @scenario_with_gap.gap_period

    assert_not_nil gap
    assert_equal Date.new(2041, 1, 1), gap[:start_date]
    assert_equal Date.new(2041, 12, 31), gap[:end_date]
    assert_equal 12, gap[:months]
    assert_equal 4000, gap[:monthly_shortfall]
  end

  test "returns nil for gap period when pension starts before salary ends" do
    gap = @scenario_no_gap.gap_period

    assert_nil gap
  end

  test "calculates gap bridge amount" do
    assert_equal 48000, @scenario_with_gap.gap_bridge_amount
  end

  test "projects income at date includes salary before end date" do
    today = Date.today
    breakdown = @scenario_with_gap.income_breakdown_at_date(today)

    assert_equal 6000, breakdown[:salary]  # 72000 / 12
  end

  test "projects income at date excludes salary after end date" do
    future_date = Date.new(2041, 6, 1)  # After salary ends
    breakdown = @scenario_with_gap.income_breakdown_at_date(future_date)

    assert_equal 0, breakdown[:salary]
  end

  test "projects income at date includes state pension after start date" do
    future_date = Date.new(2042, 2, 1)  # After pension starts
    breakdown = @scenario_with_gap.income_breakdown_at_date(future_date)

    assert_equal 1500, breakdown[:state_pension]
  end

  test "projects income at date excludes state pension before start date" do
    today = Date.today
    breakdown = @scenario_with_gap.income_breakdown_at_date(today)

    assert_equal 0, breakdown[:state_pension]
  end

  test "generates income milestones" do
    milestones = @scenario_with_gap.income_milestones

    assert milestones.any? { |m| m[:type] == :salary_end }
    assert milestones.any? { |m| m[:type] == :state_pension_start }
    assert milestones.any? { |m| m[:type] == :gap_start }
    assert milestones.any? { |m| m[:type] == :gap_end }
  end

  test "income milestones are sorted by date" do
    milestones = @scenario_with_gap.income_milestones
    dates = milestones.map { |m| m[:date] }

    assert_equal dates.sort, dates
  end

  test "generates income timeline" do
    timeline = @scenario_with_gap.generate_income_timeline(years: 5)

    assert_equal 60, timeline.length
    assert timeline.first.key?(:salary)
    assert timeline.first.key?(:state_pension)
    assert timeline.first.key?(:total_income)
    assert timeline.first.key?(:expenses)
    assert timeline.first.key?(:in_gap_period)
  end

  test "income at today returns current income" do
    income = @scenario_with_gap.income_at_today

    assert_equal 6000, income  # Salary only (72000 / 12)
  end

  test "income at full pension returns all pensions" do
    income = @scenario_with_gap.income_at_full_pension

    assert_equal 1500, income  # Only state pension configured
  end

  test "earliest pension start date returns correct date" do
    date = @scenario_with_gap.earliest_pension_start_date

    assert_equal Date.new(2042, 1, 1), date
  end

  test "in_gap_period? returns true during gap" do
    assert @scenario_with_gap.in_gap_period?(Date.new(2041, 6, 1))
  end

  test "in_gap_period? returns false outside gap" do
    assert_not @scenario_with_gap.in_gap_period?(Date.new(2040, 6, 1))
    assert_not @scenario_with_gap.in_gap_period?(Date.new(2042, 6, 1))
  end
end
