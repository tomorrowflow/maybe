class RetirementScenario
  # Analyzes optimal timing for pension cashouts, retirement dates,
  # and hold-vs-cashout decisions by running Monte Carlo simulations
  # across a range of dates.
  class SweetSpotAnalyzer
    ANALYSIS_SIMULATIONS = 100 # Quick sims per data point
    DATE_STEP_MONTHS = 12      # Test every 12 months

    attr_reader :scenario

    def initialize(scenario)
      @scenario = scenario
    end

    # Full analysis: retirement date optimization + cashout timing for each product
    def analyze
      {
        optimal_retirement: analyze_retirement_dates,
        cashout_timing: analyze_cashout_products,
        savings_gap_coverage: analyze_savings_gap_coverage,
        target_probability: 80
      }
    end

    private

      # Analyze each person's optimal retirement date independently
      def analyze_retirement_dates
        persons = scenario.retirement_scenario_persons.includes(:person).to_a
        return [] if persons.empty?

        persons.filter_map { |person| analyze_person_retirement(person) }
      end

      def analyze_person_retirement(rsp)
        base_date = rsp.salary_end_date
        return nil unless base_date

        results = []
        test_date = [ base_date - 3.years, Date.today + 1.year ].max
        end_date = base_date + 5.years

        while test_date <= end_date
          overrides = {
            person_retirement_dates: { rsp.id.to_s => test_date },
            simulation_count: ANALYSIS_SIMULATIONS
          }

          engine = MonteCarloEngine.new(scenario, overrides: overrides)
          result = engine.run

          results << {
            date: test_date.to_s,
            label: test_date.strftime("%b %Y"),
            success_rate: result[:success_rate],
            years_from_now: ((test_date - Date.today).to_f / 365.25).round(1)
          }

          test_date += DATE_STEP_MONTHS.months
        end

        sweet_spot = results.find { |r| r[:success_rate] >= 80 }

        {
          person_id: rsp.id.to_s,
          person_name: rsp.person.display_name,
          current_date: base_date.to_s,
          data_points: results,
          sweet_spot: sweet_spot,
          best_result: results.max_by { |r| r[:success_rate] }
        }
      end

      # For each cashable pension product, compare hold vs early cashout
      def analyze_cashout_products
        cashable_accounts = scenario.family.accounts.active
          .where(accountable_type: "Investment")
          .includes(:accountable)
          .select { |a| a.accountable.respond_to?(:allows_early_cashout?) && a.accountable.allows_early_cashout? }

        return [] if cashable_accounts.empty?

        cashable_accounts.map do |account|
          analyze_single_product(account)
        end.compact
      end

      def analyze_single_product(account)
        investment = account.accountable
        retirement_date = investment.retirement_date
        return nil unless retirement_date

        # Look up monthly contribution from linked payments
        monthly_contribution = find_monthly_contribution_for(account)
        growth_rate = scenario.portfolio_growth_rate || 7.0

        results = []

        # Test cashout at various dates from now to retirement
        test_date = [ Date.today + 1.year, Date.today ].max
        while test_date <= retirement_date + 2.years
          projected_value = investment.projected_value_at(
            test_date,
            fallback_growth_rate: growth_rate,
            monthly_contribution: monthly_contribution,
            contribution_end_date: test_date # Contributions stop at cashout
          )

          results << {
            date: test_date.to_s,
            label: test_date.strftime("%b %Y"),
            projected_value: projected_value.round(2),
            years_from_now: ((test_date - Date.today).to_f / 365.25).round(1)
          }

          test_date += DATE_STEP_MONTHS.months
        end

        # Compare: hold until retirement (monthly pension) vs cash out (lump sum)
        monthly_payout = investment.expected_monthly_payout || 0
        surrender_value = investment.surrender_value || 0
        projected_at_retirement = investment.projected_value_at(
          retirement_date,
          fallback_growth_rate: growth_rate,
          monthly_contribution: monthly_contribution,
          contribution_end_date: retirement_date
        )

        # Calculate breakeven: how many months of pension to equal lump sum
        breakeven_months = monthly_payout > 0 ? (projected_at_retirement / monthly_payout).ceil : nil

        # Find the pension source ID for this account (for explorer pre-fill)
        pension_source = scenario.pension_sources.find_by(account_id: account.id)

        # Recommended cashout date: if cashing out, use earliest sweet spot retirement date
        # (that's when you'd stop contributing and need the capital)
        recommended_cashout_date = if results.any?
          best_point = results.max_by { |r| r[:projected_value] }
          best_point[:date]
        end

        {
          account_name: account.name,
          account_id: account.id,
          pension_source_id: pension_source&.id&.to_s,
          subtype: account.subtype,
          recommended_cashout_date: recommended_cashout_date,
          current_value: account.balance.to_f.round(2),
          monthly_contribution: monthly_contribution.to_f.round(2),
          surrender_value: surrender_value.to_f.round(2),
          retirement_date: retirement_date.to_s,
          monthly_payout: monthly_payout.to_f.round(2),
          projected_at_retirement: projected_at_retirement.round(2),
          breakeven_months: breakeven_months,
          breakeven_years: breakeven_months ? (breakeven_months / 12.0).round(1) : nil,
          data_points: results,
          recommendation: build_recommendation(monthly_payout, projected_at_retirement, breakeven_months)
        }
      end

      # Find the monthly contribution for this account.
      # Delegates to the scenario's unified lookup.
      def find_monthly_contribution_for(account)
        scenario.find_linked_contribution_for(account)
      end

      # Analyze whether projected savings can bridge income gaps for each person
      def analyze_savings_gap_coverage
        persons = scenario.retirement_scenario_persons.includes(:person).to_a
        return [] if persons.empty?

        persons.filter_map do |rsp|
          next unless rsp.salary_end_date

          # Find gap: salary end → earliest pension/income start
          pension_dates = []
          pension_dates << rsp.state_pension_start_date if rsp.state_pension_start_date
          pension_dates << rsp.post_retirement_income_start_date if rsp.post_retirement_income_start_date
          scenario.pension_sources.with_payout.each { |ps| pension_dates << ps.payout_start_date if ps.payout_start_date }

          gap_end = pension_dates.compact.min
          next unless gap_end && gap_end > rsp.salary_end_date

          gap_months = ((gap_end - rsp.salary_end_date).to_f / 30.44).ceil
          monthly_expenses = (scenario.retirement_monthly_expenses || 0).to_f
          gap_cost = gap_months * monthly_expenses

          # Run quick sim to get median savings at gap start
          engine = MonteCarloEngine.new(scenario, overrides: { simulation_count: ANALYSIS_SIMULATIONS })
          result = engine.run

          gap_start_year = ((rsp.salary_end_date - (scenario.calculation_date || Date.today)).to_f / 365.25).round
          gap_start_year = [ gap_start_year, 0 ].max
          savings_at_gap = result.dig(:savings_percentiles, "p50", gap_start_year) || 0

          {
            person_name: rsp.person.display_name,
            gap_start: rsp.salary_end_date.to_s,
            gap_end: gap_end.to_s,
            gap_months: gap_months,
            gap_cost: gap_cost.round(2),
            median_savings_at_gap: savings_at_gap.round(2),
            coverage_ratio: gap_cost > 0 ? (savings_at_gap / gap_cost * 100).round(1) : nil,
            sufficient: savings_at_gap >= gap_cost
          }
        end
      end

      def build_recommendation(monthly_payout, projected_value, breakeven_months)
        if monthly_payout <= 0
          { action: :cash_out, reason: "No monthly payout configured — lump sum is the only option" }
        elsif breakeven_months && breakeven_months > 300 # 25+ years
          { action: :cash_out, reason: "Breakeven takes #{(breakeven_months / 12.0).round(1)} years — lump sum invested may perform better" }
        elsif breakeven_months && breakeven_months < 120 # Under 10 years
          { action: :hold, reason: "Monthly pension breaks even in #{(breakeven_months / 12.0).round(1)} years — holding is likely better" }
        else
          { action: :depends, reason: "Breakeven in #{(breakeven_months / 12.0).round(1)} years — depends on your investment returns and life expectancy" }
        end
      end
  end
end
