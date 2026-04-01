require "test_helper"

class RetirementScenarioPersonTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @bob = persons(:bob_person)
    @sara = persons(:sara_person)
  end

  test "income_at_date returns salary before salary end" do
    rsp = RetirementScenarioPerson.new(
      person: @bob,
      current_annual_salary: 120000,
      salary_end_date: Date.new(2030, 12, 31)
    )

    assert_in_delta 10000, rsp.income_at_date(Date.new(2029, 6, 1)), 0.01
  end

  test "income_at_date returns 0 salary after salary end" do
    rsp = RetirementScenarioPerson.new(
      person: @bob,
      current_annual_salary: 120000,
      salary_end_date: Date.new(2030, 12, 31)
    )

    assert_in_delta 0, rsp.income_at_date(Date.new(2031, 6, 1)), 0.01
  end

  test "income_at_date includes state pension after start date" do
    rsp = RetirementScenarioPerson.new(
      person: @bob,
      state_pension_monthly: 1500,
      state_pension_start_date: Date.new(2032, 1, 1)
    )

    assert_in_delta 0, rsp.income_at_date(Date.new(2031, 12, 1)), 0.01
    assert_in_delta 1500, rsp.income_at_date(Date.new(2032, 6, 1)), 0.01
  end

  test "income_at_date includes post-retirement income within date range" do
    rsp = RetirementScenarioPerson.new(
      person: @bob,
      post_retirement_income_monthly: 2000,
      post_retirement_income_start_date: Date.new(2031, 1, 1),
      post_retirement_income_end_date: Date.new(2033, 12, 31)
    )

    assert_in_delta 0, rsp.income_at_date(Date.new(2030, 12, 1)), 0.01
    assert_in_delta 2000, rsp.income_at_date(Date.new(2032, 6, 1)), 0.01
    assert_in_delta 0, rsp.income_at_date(Date.new(2034, 1, 1)), 0.01
  end

  test "income_milestones includes salary end and pension start" do
    rsp = RetirementScenarioPerson.new(
      person: @bob,
      salary_end_date: Date.new(2030, 12, 31),
      state_pension_start_date: Date.new(2032, 1, 1),
      state_pension_monthly: 1500
    )

    milestones = rsp.income_milestones
    types = milestones.map { |m| m[:type] }

    assert_includes types, :salary_end
    assert_includes types, :state_pension_start
    assert milestones.all? { |m| m[:label].include?("Bob") }
  end

  test "income_milestones includes post-retirement work" do
    rsp = RetirementScenarioPerson.new(
      person: @bob,
      post_retirement_income_monthly: 2000,
      post_retirement_income_start_date: Date.new(2031, 1, 1),
      post_retirement_income_end_date: Date.new(2033, 12, 31)
    )

    milestones = rsp.income_milestones
    types = milestones.map { |m| m[:type] }

    assert_includes types, :post_retirement_start
    assert_includes types, :post_retirement_end
  end

  test "effective_retirement_date prefers target over salary end" do
    rsp = RetirementScenarioPerson.new(
      target_retirement_date: Date.new(2031, 6, 1),
      salary_end_date: Date.new(2030, 12, 31)
    )

    assert_equal Date.new(2031, 6, 1), rsp.effective_retirement_date
  end
end
