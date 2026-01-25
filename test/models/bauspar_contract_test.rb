require "test_helper"

class BausparContractTest < ActiveSupport::TestCase
  def create_bauspar_account(bauspar_attrs = {}, account_attrs = {})
    defaults = {
      bausparsumme: 50000,
      phase: "saving",
      minimum_savings_percent: 40
    }

    account_defaults = {
      family: families(:dylan_family),
      name: "Test Bausparvertrag",
      balance: 10000,
      currency: "EUR"
    }

    Account.create!(
      **account_defaults.merge(account_attrs),
      accountable: BausparContract.new(defaults.merge(bauspar_attrs))
    )
  end

  # === Classification and Display ===

  test "bauspar contract is classified as asset" do
    assert_equal "asset", BausparContract.classification
  end

  test "displays correct name" do
    bauspar = BausparContract.new
    assert_equal "Building Savings (Bausparvertrag)", bauspar.display_name
  end

  # === Phase Predicates ===

  test "phase predicates return correct values" do
    saving = BausparContract.new(phase: "saving", bausparsumme: 1000)
    allocated = BausparContract.new(phase: "allocated", bausparsumme: 1000)
    loan = BausparContract.new(phase: "loan", bausparsumme: 1000)
    closed = BausparContract.new(phase: "closed", bausparsumme: 1000)

    assert saving.saving_phase?
    assert_not saving.allocated_phase?

    assert allocated.allocated_phase?
    assert_not allocated.saving_phase?

    assert loan.loan_phase?
    assert_not loan.allocated_phase?

    assert closed.closed_phase?
    assert_not closed.loan_phase?
  end

  test "phase_description returns correct German terminology" do
    assert_equal "Savings Phase (Ansparphase)", BausparContract.new(phase: "saving", bausparsumme: 1000).phase_description
    assert_equal "Allocated - Ready for Loan (Zuteilung)", BausparContract.new(phase: "allocated", bausparsumme: 1000).phase_description
    assert_equal "Loan Phase (Darlehensphase)", BausparContract.new(phase: "loan", bausparsumme: 1000).phase_description
    assert_equal "Closed", BausparContract.new(phase: "closed", bausparsumme: 1000).phase_description
  end

  # === Savings Progress Calculations ===

  test "calculates savings progress percent correctly" do
    account = create_bauspar_account(
      { bausparsumme: 50000, minimum_savings_percent: 40 },
      { balance: 10000 } # 50% of target (20000)
    )

    assert_equal 50.0, account.bauspar_contract.savings_progress_percent
  end

  test "caps savings progress at 100 percent" do
    account = create_bauspar_account(
      { bausparsumme: 50000, minimum_savings_percent: 40 },
      { balance: 25000 } # 125% of target
    )

    assert_equal 100.0, account.bauspar_contract.savings_progress_percent
  end

  test "returns zero progress when bausparsumme is zero" do
    account = create_bauspar_account(
      { bausparsumme: 0.01, minimum_savings_percent: 40 }, # minimum valid amount
      { balance: 0 }
    )

    assert_equal 0.0, account.bauspar_contract.savings_progress_percent
  end

  test "calculates savings target amount correctly" do
    account = create_bauspar_account(
      { bausparsumme: 50000, minimum_savings_percent: 40 },
      { balance: 5000, currency: "EUR" }
    )

    target = account.bauspar_contract.savings_target_amount
    assert_equal 20000, target.amount
    assert_equal "EUR", target.currency.iso_code
  end

  test "uses default 40% when minimum_savings_percent is nil" do
    account = create_bauspar_account(
      { bausparsumme: 50000, minimum_savings_percent: nil },
      { balance: 5000 }
    )

    assert_equal 40.0, account.bauspar_contract.savings_target_percent
  end

  # === Loan Amount Calculations ===

  test "calculates available loan amount" do
    account = create_bauspar_account(
      { bausparsumme: 50000 },
      { balance: 20000, currency: "EUR" }
    )

    loan_amount = account.bauspar_contract.available_loan_amount
    assert_equal 30000, loan_amount.amount
    assert_equal "EUR", loan_amount.currency.iso_code
  end

  test "available loan amount is zero when balance exceeds bausparsumme" do
    account = create_bauspar_account(
      { bausparsumme: 50000 },
      { balance: 60000 }
    )

    assert_equal 0, account.bauspar_contract.available_loan_amount.amount
  end

  # === Minimum Savings Period ===

  test "minimum savings period is met when enough time has passed" do
    bauspar = BausparContract.new(
      bausparsumme: 50000,
      phase: "saving",
      contract_start_date: 8.years.ago.to_date,
      minimum_savings_period_months: 84 # 7 years
    )

    assert bauspar.minimum_savings_period_met?
  end

  test "minimum savings period is not met when not enough time has passed" do
    bauspar = BausparContract.new(
      bausparsumme: 50000,
      phase: "saving",
      contract_start_date: 3.years.ago.to_date,
      minimum_savings_period_months: 84 # 7 years
    )

    assert_not bauspar.minimum_savings_period_met?
  end

  test "minimum savings period is met when no period specified" do
    bauspar = BausparContract.new(
      bausparsumme: 50000,
      phase: "saving",
      contract_start_date: 1.year.ago.to_date,
      minimum_savings_period_months: nil
    )

    assert bauspar.minimum_savings_period_met?
  end

  test "calculates months until minimum period correctly" do
    bauspar = BausparContract.new(
      bausparsumme: 50000,
      phase: "saving",
      contract_start_date: 5.years.ago.to_date,
      minimum_savings_period_months: 84 # 7 years = 84 months
    )

    # About 24 months remaining (84 - 60)
    remaining = bauspar.months_until_minimum_period
    assert remaining > 20 && remaining < 30, "Expected ~24 months remaining, got #{remaining}"
  end

  # === Bewertungszahl ===

  test "bewertungszahl is met when current exceeds minimum" do
    bauspar = BausparContract.new(
      bausparsumme: 50000,
      phase: "saving",
      minimum_bewertungszahl: 2000,
      current_bewertungszahl: 2500
    )

    assert bauspar.bewertungszahl_met?
  end

  test "bewertungszahl is not met when current is below minimum" do
    bauspar = BausparContract.new(
      bausparsumme: 50000,
      phase: "saving",
      minimum_bewertungszahl: 2500,
      current_bewertungszahl: 1800
    )

    assert_not bauspar.bewertungszahl_met?
  end

  test "bewertungszahl is considered met when not specified" do
    bauspar = BausparContract.new(
      bausparsumme: 50000,
      phase: "saving",
      minimum_bewertungszahl: nil,
      current_bewertungszahl: nil
    )

    assert bauspar.bewertungszahl_met?
  end

  # === Allocation Readiness ===

  test "allocation_ready returns true when all conditions met" do
    account = create_bauspar_account(
      {
        bausparsumme: 50000,
        phase: "saving",
        minimum_savings_percent: 40,
        contract_start_date: 10.years.ago.to_date,
        minimum_savings_period_months: 84,
        minimum_bewertungszahl: 2000,
        current_bewertungszahl: 2500
      },
      { balance: 25000 } # Above 40% target (20000)
    )

    assert account.bauspar_contract.allocation_ready?
  end

  test "allocation_ready returns false when savings target not met" do
    account = create_bauspar_account(
      {
        bausparsumme: 50000,
        phase: "saving",
        minimum_savings_percent: 40,
        contract_start_date: 10.years.ago.to_date,
        minimum_savings_period_months: 84,
        minimum_bewertungszahl: 2000,
        current_bewertungszahl: 2500
      },
      { balance: 10000 } # Below 40% target
    )

    assert_not account.bauspar_contract.allocation_ready?
  end

  test "allocation_ready returns false when not in saving phase" do
    account = create_bauspar_account(
      {
        bausparsumme: 50000,
        phase: "allocated", # Not in saving phase
        minimum_savings_percent: 40
      },
      { balance: 25000 }
    )

    assert_not account.bauspar_contract.allocation_ready?
  end

  # === Subsidies ===

  test "has_subsidies returns true when any subsidy is eligible" do
    bauspar = BausparContract.new(
      bausparsumme: 50000,
      phase: "saving",
      wohnungsbauspraemie_eligible: true,
      arbeitnehmersparzulage_eligible: false,
      wohn_riester_eligible: false,
      vermoegenswirksame_leistungen: false
    )

    assert bauspar.has_subsidies?
  end

  test "has_subsidies returns false when no subsidies eligible" do
    bauspar = BausparContract.new(
      bausparsumme: 50000,
      phase: "saving",
      wohnungsbauspraemie_eligible: false,
      arbeitnehmersparzulage_eligible: false,
      wohn_riester_eligible: false,
      vermoegenswirksame_leistungen: false
    )

    assert_not bauspar.has_subsidies?
  end

  test "active_subsidies returns list of eligible subsidies" do
    bauspar = BausparContract.new(
      bausparsumme: 50000,
      phase: "saving",
      wohnungsbauspraemie_eligible: true,
      arbeitnehmersparzulage_eligible: false,
      wohn_riester_eligible: true,
      vermoegenswirksame_leistungen: false
    )

    subsidies = bauspar.active_subsidies
    assert_includes subsidies, "Wohnungsbauprämie"
    assert_includes subsidies, "Wohn-Riester"
    assert_not_includes subsidies, "Arbeitnehmersparzulage"
    assert_equal 2, subsidies.length
  end

  # === Timeline Calculations ===

  test "calculates years until allocation" do
    bauspar = BausparContract.new(
      bausparsumme: 50000,
      phase: "saving",
      expected_allocation_date: 3.years.from_now.to_date
    )

    years = bauspar.years_until_allocation
    assert years > 2.5 && years < 3.5, "Expected ~3 years, got #{years}"
  end

  test "returns zero years when allocation date has passed" do
    bauspar = BausparContract.new(
      bausparsumme: 50000,
      phase: "saving",
      expected_allocation_date: 1.year.ago.to_date
    )

    assert_equal 0, bauspar.years_until_allocation
  end

  test "calculates contract duration in years" do
    bauspar = BausparContract.new(
      bausparsumme: 50000,
      phase: "saving",
      contract_start_date: 5.years.ago.to_date
    )

    duration = bauspar.contract_duration_years
    assert duration > 4.5 && duration < 5.5, "Expected ~5 years, got #{duration}"
  end

  # === Suggested Monthly Contribution ===

  test "calculates suggested monthly contribution at 4 per mille" do
    account = create_bauspar_account(
      { bausparsumme: 50000 },
      { currency: "EUR" }
    )

    suggestion = account.bauspar_contract.suggested_monthly_contribution
    assert_equal 200, suggestion.amount # 50000 * 0.004
    assert_equal "EUR", suggestion.currency.iso_code
  end

  # === Validations ===

  test "requires bausparsumme" do
    bauspar = BausparContract.new(phase: "saving", bausparsumme: nil)
    assert_not bauspar.valid?
    assert_includes bauspar.errors[:bausparsumme], "can't be blank"
  end

  test "bausparsumme must be positive" do
    bauspar = BausparContract.new(phase: "saving", bausparsumme: -1000)
    assert_not bauspar.valid?
    assert_includes bauspar.errors[:bausparsumme], "must be greater than 0"
  end

  test "requires valid phase" do
    bauspar = BausparContract.new(bausparsumme: 50000, phase: "invalid")
    assert_not bauspar.valid?
    assert_includes bauspar.errors[:phase], "is not included in the list"
  end

  test "minimum_savings_percent must be between 0 and 100" do
    bauspar = BausparContract.new(bausparsumme: 50000, phase: "saving", minimum_savings_percent: 150)
    assert_not bauspar.valid?
    assert_includes bauspar.errors[:minimum_savings_percent], "must be less than or equal to 100"
  end
end
