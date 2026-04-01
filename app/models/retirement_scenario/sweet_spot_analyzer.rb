class RetirementScenario
  # Analyzes optimal timing for retirement and pension cashouts.
  # For each person, tests retirement dates centered around the first feasible date.
  # Determines which contracts to cash out to cover the income gap while keeping
  # savings above the target minimum.
  class SweetSpotAnalyzer
    ANALYSIS_SIMULATIONS = 100
    DATE_STEP_MONTHS = 12
    TARGET_FEASIBILITY = 85 # Center the date range around this feasibility threshold

    attr_reader :scenario

    def initialize(scenario)
      @scenario = scenario
    end

    def analyze
      {
        per_person_strategies: analyze_per_person,
        target_probability: TARGET_FEASIBILITY,
        target_savings: target_minimum_savings,
        scenario_type: scenario.scenario_type
      }
    end

    private

      def target_minimum_savings
        target = (Setting.retirement_target_savings || 50_000).to_f
        person_count = [ scenario.retirement_scenario_persons.size, 1 ].max
        # For joint/household: shared target, not multiplied
        target
      end

      # Analyze each person independently
      def analyze_per_person
        persons = scenario.retirement_scenario_persons.includes(:person).to_a
        return [] if persons.empty?

        cashable_contracts = load_cashable_contracts

        persons.filter_map do |rsp|
          analyze_person(rsp, cashable_contracts, persons)
        end
      end

      def analyze_person(rsp, cashable_contracts, all_persons)
        base_date = rsp.salary_end_date
        return nil unless base_date

        pension_start = find_pension_start_for_person(rsp)

        # Center date: user's preferred retirement date
        center_date = base_date

        # Calculate 9 years: 4 before center + center + 4 after center
        # Bounded by: earliest = next year, latest = official retirement date
        earliest = Date.new(Date.today.year + 1, Date.today.month, 1)
        latest = base_date

        strategies = []
        (-4..4).each do |offset|
          test_date = center_date + offset.years
          next if test_date < earliest
          next if test_date > latest + 1.year # Allow 1 year past official date
          strategy = build_strategy_for_date(rsp, test_date, pension_start, cashable_contracts, all_persons)
          strategies << strategy if strategy
        end

        sweet_spot = strategies.find { |s| s[:feasible] && s[:success_rate] >= TARGET_FEASIBILITY }

        {
          person_id: rsp.id.to_s,
          person_name: rsp.person.display_name,
          current_planned_date: base_date.to_s,
          sweet_spot: sweet_spot,
          strategies: strategies,
          center_index: strategies.index { |s| s[:date] == center_date.to_s } || (strategies.size / 2),
          earliest_year: earliest.year,
          latest_year: latest.year
        }
      end

      # Calculate a single year's strategy (called on-demand from controller)
      def self.calculate_single_year(scenario, person_id, year)
        rsp = scenario.retirement_scenario_persons.includes(:person).find(person_id)
        analyzer = new(scenario)
        pension_start = analyzer.send(:find_pension_start_for_person, rsp)
        cashable_contracts = analyzer.send(:load_cashable_contracts)
        all_persons = scenario.retirement_scenario_persons.includes(:person).to_a

        test_date = Date.new(year, rsp.salary_end_date&.month || 1, rsp.salary_end_date&.day || 1)
        analyzer.send(:build_strategy_for_date, rsp, test_date, pension_start, cashable_contracts, all_persons)
      end

      # Quick scan to find the first feasible retirement date
      def find_first_feasible_date(rsp, base_date, pension_start, cashable_contracts, all_persons)
        test_date = Date.new(Date.today.year + 1, Date.today.month, 1)
        end_date = base_date # Official retirement date is the maximum

        while test_date <= end_date
          strategy = build_strategy_for_date(rsp, test_date, pension_start, cashable_contracts, all_persons)
          return test_date if strategy && strategy[:feasible] && strategy[:success_rate] >= TARGET_FEASIBILITY
          test_date += DATE_STEP_MONTHS.months
        end

        nil
      end

      def find_pension_start_for_person(rsp)
        dates = []
        dates << rsp.state_pension_start_date if rsp.state_pension_start_date
        dates << rsp.person.estimated_retirement_date if rsp.person.respond_to?(:estimated_retirement_date) && rsp.person.estimated_retirement_date

        # Also include pension sources (shared in joint scenarios)
        scenario.pension_sources.with_payout.each do |ps|
          dates << ps.payout_start_date if ps.payout_start_date
        end

        dates.compact.min
      end

      def build_strategy_for_date(rsp, retirement_date, pension_start, cashable_contracts, all_persons)
        # Gap calculation
        gap_end = pension_start
        if gap_end.nil? || gap_end <= retirement_date
          gap_months = 0
          gap_cost = 0
        else
          gap_months = ((gap_end - retirement_date).to_f / 30.44).ceil
          gap_cost = gap_months * monthly_expenses
        end

        required_total = gap_cost + target_minimum_savings

        # Run Monte Carlo with this person's retirement date overridden
        overrides = {
          person_retirement_dates: { rsp.id.to_s => retirement_date },
          simulation_count: ANALYSIS_SIMULATIONS
        }
        engine = MonteCarloEngine.new(scenario, overrides: overrides)
        mc_result = engine.run

        retirement_year = ((retirement_date - (scenario.calculation_date || Date.today)).to_f / 365.25).round
        retirement_year = [ retirement_year, 0 ].max
        projected_savings = mc_result.dig(:savings_percentiles, "p50", retirement_year) || 0

        shortfall = required_total - projected_savings

        # Build cashout plan if there's a shortfall
        cashout_plan = []
        total_cashout = 0
        total_lost_pension = 0

        if shortfall > 0
          cashout_plan = optimize_cashouts(cashable_contracts, retirement_date, shortfall)
          total_cashout = cashout_plan.sum { |c| c[:cashout_value] }
          total_lost_pension = cashout_plan.sum { |c| c[:lost_monthly_payout] }
        end

        savings_after_gap = projected_savings + total_cashout - gap_cost
        feasible = savings_after_gap >= target_minimum_savings

        {
          date: retirement_date.to_s,
          label: retirement_date.strftime("%b %Y"),
          years_from_now: ((retirement_date - Date.today).to_f / 365.25).round(1),
          success_rate: mc_result[:success_rate],
          gap_months: gap_months,
          gap_cost: gap_cost.round(2),
          projected_savings: projected_savings.round(2),
          shortfall: [ shortfall, 0 ].max.round(2),
          cashout_plan: cashout_plan,
          total_cashout: total_cashout.round(2),
          total_lost_pension: total_lost_pension.round(2),
          savings_after_gap: savings_after_gap.round(2),
          feasible: feasible
        }
      end

      def optimize_cashouts(contracts, cashout_date, shortfall)
        remaining = shortfall
        selected = []

        sorted = contracts.sort_by { |c| c[:monthly_payout] }

        sorted.each do |contract|
          break if remaining <= 0

          cashout_value = contract_cashout_value(contract, cashout_date)
          next if cashout_value <= 0

          selected << {
            account_name: contract[:account_name],
            account_id: contract[:account_id],
            pension_source_id: contract[:pension_source_id],
            cashout_value: cashout_value.round(2),
            lost_monthly_payout: contract[:monthly_payout],
            cashout_date: (contract[:early_cashout_date] || cashout_date).to_s,
            subtype: contract[:subtype]
          }

          remaining -= cashout_value
        end

        selected
      end

      def contract_cashout_value(contract, date)
        if contract[:has_surrender_value] && contract[:surrender_value].to_f > 0
          return contract[:surrender_value].to_f
        end

        investment = contract[:investment]
        return 0 unless investment

        contribution = scenario.find_linked_contribution_for(contract[:account]) rescue 0
        investment.projected_value_at(
          contract[:early_cashout_date] || date,
          fallback_growth_rate: scenario.portfolio_growth_rate || 7.0,
          monthly_contribution: contribution,
          contribution_end_date: contract[:early_cashout_date] || date
        )
      end

      def load_cashable_contracts
        scenario.family.accounts.active
          .where(accountable_type: "Investment")
          .includes(:accountable)
          .select { |a| a.accountable.respond_to?(:allows_early_cashout?) && a.accountable.allows_early_cashout? }
          .map { |account|
            inv = account.accountable
            pension_source = scenario.pension_sources.find_by(account_id: account.id)
            {
              account: account,
              account_name: account.name,
              account_id: account.id,
              pension_source_id: pension_source&.id&.to_s,
              subtype: account.subtype,
              investment: inv,
              current_value: account.balance.to_f,
              monthly_payout: (inv.expected_monthly_payout || 0).to_f,
              surrender_value: (inv.surrender_value || 0).to_f,
              has_surrender_value: inv.has_surrender_value,
              early_cashout_date: inv.early_cashout_date,
              retirement_date: inv.retirement_date,
              monthly_contribution: (inv.monthly_contribution || 0).to_f
            }
          }
      end

      def monthly_expenses
        (scenario.retirement_monthly_expenses || 0).to_f
      end
  end
end
