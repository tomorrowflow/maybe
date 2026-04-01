class RetirementScenario
  class CashFlowSnapshot
    attr_reader :monthly_income, :fixed_obligations, :living_expenses, :obligation_details, :incoming_payments, :currency

    def initialize(monthly_income:, fixed_obligations:, living_expenses:, obligation_details: [], incoming_payments: [], currency: "EUR")
      @monthly_income = to_numeric(monthly_income)
      @fixed_obligations = to_numeric(fixed_obligations)
      @living_expenses = to_numeric(living_expenses)
      @obligation_details = obligation_details
      @incoming_payments = incoming_payments
      @currency = currency
    end

    def monthly_savings
      monthly_income - fixed_obligations - living_expenses
    end

    def savings_rate
      return 0 if monthly_income <= 0
      (monthly_savings / monthly_income * 100).round(1)
    end

    def income_money
      Money.new(monthly_income, currency)
    end

    def obligations_money
      Money.new(fixed_obligations, currency)
    end

    def living_expenses_money
      Money.new(living_expenses, currency)
    end

    def savings_money
      Money.new(monthly_savings, currency)
    end

    def can_save?
      monthly_savings > 0
    end

    # Project savings at a future date, considering milestones that change obligations
    def monthly_savings_at_date(date, milestones: [])
      adjustments = 0

      milestones.select { |m| m.date <= date }.each do |milestone|
        case milestone.milestone_type
        when "debt_payoff", "bauspar_phase_change"
          adjustments += (milestone.amount || 0)
        when "income_start"
          adjustments += (milestone.amount || 0)
        when "income_stop"
          adjustments -= (milestone.amount || 0)
        end
      end

      monthly_savings + adjustments
    end

    private

      def to_numeric(value)
        return value.amount if value.is_a?(Money)
        BigDecimal(value.to_s)
      end
  end
end
