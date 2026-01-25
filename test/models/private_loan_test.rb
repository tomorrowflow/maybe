require "test_helper"

class PrivateLoanTest < ActiveSupport::TestCase
  def create_private_loan_account(loan_attrs = {}, account_attrs = {})
    defaults = {
      principal_amount: 10000,
      interest_rate: 5.0,
      rate_type: "fixed",
      term_months: 24,
      repayment_type: "annuity"
    }

    account_defaults = {
      family: families(:dylan_family),
      name: "Test Private Loan",
      balance: 10000,
      currency: "EUR"
    }

    Account.create!(
      **account_defaults.merge(account_attrs),
      accountable: PrivateLoan.new(defaults.merge(loan_attrs))
    )
  end

  # === Classification and Display ===

  test "private loan is classified as asset" do
    assert_equal "asset", PrivateLoan.classification
  end

  test "displays correct name" do
    loan = PrivateLoan.new
    assert_equal "Private Loan", loan.display_name
  end

  test "has correct icon" do
    assert_equal "hand-coins", PrivateLoan.icon
  end

  # === Monthly Payment Calculations ===

  test "calculates annuity payment correctly" do
    account = create_private_loan_account(
      principal_amount: 10000,
      interest_rate: 6.0,
      term_months: 12,
      repayment_type: "annuity"
    )

    payment = account.private_loan.monthly_payment
    # Expected: ~861 for 10000 at 6% over 12 months
    assert payment > 850 && payment < 870, "Expected ~861, got #{payment}"
  end

  test "calculates bullet payment as interest only" do
    account = create_private_loan_account(
      principal_amount: 10000,
      interest_rate: 6.0,
      term_months: 12,
      repayment_type: "bullet"
    )

    payment = account.private_loan.monthly_payment
    # Expected: 50 (10000 * 0.06 / 12)
    assert_equal 50, payment.round
  end

  test "calculates interest only payment" do
    account = create_private_loan_account(
      principal_amount: 10000,
      interest_rate: 6.0,
      term_months: 12,
      repayment_type: "interest_only"
    )

    payment = account.private_loan.monthly_payment
    assert_equal 50, payment.round
  end

  test "returns nil for custom repayment type" do
    account = create_private_loan_account(
      principal_amount: 10000,
      interest_rate: 6.0,
      term_months: 12,
      repayment_type: "custom"
    )

    assert_nil account.private_loan.monthly_payment
  end

  # === Interest Calculations ===

  test "calculates monthly interest payment" do
    account = create_private_loan_account(
      principal_amount: 12000,
      interest_rate: 6.0
    )

    interest = account.private_loan.monthly_interest_payment
    assert_equal 60, interest.round # 12000 * 0.06 / 12
  end

  test "calculates total interest for bullet loan" do
    account = create_private_loan_account(
      principal_amount: 10000,
      interest_rate: 6.0,
      term_months: 12,
      repayment_type: "bullet"
    )

    total = account.private_loan.total_interest
    assert_equal 600, total.round # 50 * 12
  end

  test "calculates total repayment" do
    account = create_private_loan_account(
      principal_amount: 10000,
      interest_rate: 6.0,
      term_months: 12,
      repayment_type: "bullet"
    )

    total = account.private_loan.total_repayment
    assert_equal 10600, total.round # principal + interest
  end

  # === Repayment Progress ===

  test "calculates repayment progress percent" do
    account = create_private_loan_account(
      { principal_amount: 10000 },
      { balance: 6000 } # 4000 repaid
    )

    progress = account.private_loan.repayment_progress_percent
    assert_equal 40.0, progress
  end

  test "caps repayment progress at 100 percent" do
    account = create_private_loan_account(
      { principal_amount: 10000 },
      { balance: 0 } # Fully repaid
    )

    progress = account.private_loan.repayment_progress_percent
    assert_equal 100.0, progress
  end

  # === Past Due Detection ===

  test "detects past due loan" do
    account = create_private_loan_account(
      { maturity_date: 1.month.ago.to_date },
      { balance: 5000 }
    )

    assert account.private_loan.past_due?
  end

  test "not past due when maturity in future" do
    account = create_private_loan_account(
      { maturity_date: 1.month.from_now.to_date },
      { balance: 5000 }
    )

    assert_not account.private_loan.past_due?
  end

  test "not past due when fully repaid" do
    account = create_private_loan_account(
      { maturity_date: 1.month.ago.to_date },
      { balance: 0 }
    )

    assert_not account.private_loan.past_due?
  end

  # === Timeline Calculations ===

  test "calculates days until maturity" do
    loan = PrivateLoan.new(
      principal_amount: 10000,
      maturity_date: 30.days.from_now.to_date
    )

    days = loan.days_until_maturity
    assert days >= 29 && days <= 31, "Expected ~30 days, got #{days}"
  end

  test "returns zero days when maturity passed" do
    loan = PrivateLoan.new(
      principal_amount: 10000,
      maturity_date: 1.week.ago.to_date
    )

    assert_equal 0, loan.days_until_maturity
  end

  test "calculates months until maturity" do
    loan = PrivateLoan.new(
      principal_amount: 10000,
      maturity_date: 6.months.from_now.to_date
    )

    months = loan.months_until_maturity
    assert months > 5 && months < 7, "Expected ~6 months, got #{months}"
  end

  test "calculates elapsed months" do
    loan = PrivateLoan.new(
      principal_amount: 10000,
      start_date: 3.months.ago.to_date
    )

    elapsed = loan.elapsed_months
    assert elapsed > 2.5 && elapsed < 3.5, "Expected ~3 months, got #{elapsed}"
  end

  # === Description Methods ===

  test "repayment type descriptions are correct" do
    assert_equal "Annuity (Equal Payments)", PrivateLoan.new(repayment_type: "annuity", principal_amount: 1).repayment_type_description
    assert_equal "Bullet (Interest Only, Principal at End)", PrivateLoan.new(repayment_type: "bullet", principal_amount: 1).repayment_type_description
    assert_equal "Interest Only", PrivateLoan.new(repayment_type: "interest_only", principal_amount: 1).repayment_type_description
    assert_equal "Custom Schedule", PrivateLoan.new(repayment_type: "custom", principal_amount: 1).repayment_type_description
  end

  test "rate type descriptions are correct" do
    assert_equal "Fixed Rate", PrivateLoan.new(rate_type: "fixed", principal_amount: 1).rate_type_description
    assert_equal "Variable Rate", PrivateLoan.new(rate_type: "variable", principal_amount: 1).rate_type_description
  end

  # === Validations ===

  test "requires principal amount" do
    loan = PrivateLoan.new(principal_amount: nil)
    assert_not loan.valid?
    assert_includes loan.errors[:principal_amount], "can't be blank"
  end

  test "principal amount must be positive" do
    loan = PrivateLoan.new(principal_amount: -1000)
    assert_not loan.valid?
    assert_includes loan.errors[:principal_amount], "must be greater than 0"
  end

  test "interest rate must be non-negative" do
    loan = PrivateLoan.new(principal_amount: 1000, interest_rate: -1)
    assert_not loan.valid?
    assert_includes loan.errors[:interest_rate], "must be greater than or equal to 0"
  end

  test "term months must be positive" do
    loan = PrivateLoan.new(principal_amount: 1000, term_months: 0)
    assert_not loan.valid?
    assert_includes loan.errors[:term_months], "must be greater than 0"
  end

  test "rate type must be valid" do
    loan = PrivateLoan.new(principal_amount: 1000, rate_type: "invalid")
    assert_not loan.valid?
    assert_includes loan.errors[:rate_type], "is not included in the list"
  end

  test "repayment type must be valid" do
    loan = PrivateLoan.new(principal_amount: 1000, repayment_type: "invalid")
    assert_not loan.valid?
    assert_includes loan.errors[:repayment_type], "is not included in the list"
  end

  # === Zero Interest Handling ===

  test "handles zero interest rate" do
    account = create_private_loan_account(
      principal_amount: 10000,
      interest_rate: 0,
      term_months: 12,
      repayment_type: "bullet"
    )

    assert_equal 0, account.private_loan.monthly_interest_payment
  end
end
