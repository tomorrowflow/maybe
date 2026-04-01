class RetirementScenario
  class AccountProjector
    attr_reader :account, :fallback_growth_rate

    def initialize(account, fallback_growth_rate: 7.0)
      @account = account
      @fallback_growth_rate = fallback_growth_rate
    end

    # Project account value for a given number of months
    # contribution_amount: monthly contribution to this account (can be nil for no contributions)
    def project_value(months:, contribution_amount: 0)
      value = current_value
      monthly_rate = monthly_growth_rate

      months.times do
        # Apply monthly growth
        growth = value * monthly_rate
        value = value + growth + contribution_amount
      end

      value
    end

    # Generate month-by-month projections for this account
    def generate_projections(months:, contribution_amount: 0, start_date: Date.today)
      value = current_value
      monthly_rate = monthly_growth_rate
      projections = []

      months.times do |month|
        growth = value * monthly_rate
        value = value + growth + contribution_amount

        projections << {
          month: month + 1,
          date: start_date + (month + 1).months,
          value: value,
          growth: growth,
          contribution: contribution_amount,
          growth_rate: annual_growth_rate
        }
      end

      projections
    end

    # The annual growth rate for this account (as percentage, e.g., 7.0)
    def annual_growth_rate
      account.projected_growth_rate(fallback_rate: fallback_growth_rate) || 0
    end

    # The monthly growth rate (as decimal, e.g., 0.00583 for 7% annual)
    def monthly_growth_rate
      annual_growth_rate / 100.0 / 12.0
    end

    # Current account balance
    def current_value
      account.balance.to_f
    end

    # Check if this account has a custom growth rate set
    def has_custom_rate?
      account.projected_growth_rate.present?
    end

    # Account classification for contribution distribution
    def contribution_eligible?
      # Typically only contribute to asset accounts (not liabilities)
      account.classification == "asset" && !liability_account_type?
    end

    private

      def liability_account_type?
        %w[CreditCard Loan OtherLiability PrivateLoan].include?(account.accountable_type)
      end
  end
end
