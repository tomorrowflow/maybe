class RetirementScenario
  class MonteCarloEngine
    MAX_SIMULATIONS = 5000

    attr_reader :scenario, :overrides

    def initialize(scenario, overrides: {})
      @scenario = scenario
      @overrides = overrides.with_indifferent_access
    end

    def run
      count = effective_simulation_count
      seed = Random.new_seed
      rng = Random.new(seed)

      all_paths = Array.new(count) { simulate_one_path(rng) }

      analyze_results(all_paths).merge(
        simulation_count: count,
        seed: seed,
        ran_at: Time.current.iso8601
      )
    end

    private

      # ========================================
      # Simulation
      # ========================================

      def simulate_one_path(rng)
        portfolio = initial_portfolio
        yearly_values = [ portfolio ]

        projection_years.times do |year|
          current_date = start_date + year.years

          # Random log-normal return
          annual_return = random_log_normal_return(rng)

          # Income streams active at this date
          income = annual_income_at(current_date)

          # Inflation-adjusted expenses
          expenses = annual_expenses * ((1 + inflation_rate) ** year)

          # Fixed obligations (loans, Bauspar) — adjusted by milestones
          obligations = annual_obligations_at(current_date)

          # Net withdrawal from portfolio
          net_withdrawal = [ expenses + obligations - income, 0 ].max

          # Contributions (while still working)
          contributions = annual_contributions_at(current_date)

          # One-time cashout injections
          cashout = cashout_amount_at(current_date)

          # Apply return, then adjust
          portfolio = portfolio * (1 + annual_return) - net_withdrawal + contributions + cashout
          portfolio = [ portfolio, 0 ].max

          yearly_values << portfolio
        end

        yearly_values
      end

      # Log-normal return: prevents returns below -100%
      # Calibrate mu/sigma so that E[return] = mean and Var[return] = std_dev^2
      def random_log_normal_return(rng)
        mean = growth_rate
        std_dev = growth_std_dev

        return mean if std_dev == 0

        # Convert arithmetic mean/std_dev to log-normal parameters
        variance = std_dev ** 2
        mu = Math.log((1 + mean) ** 2 / Math.sqrt(variance + (1 + mean) ** 2))
        sigma = Math.sqrt(Math.log(1 + variance / (1 + mean) ** 2))

        # Box-Muller transform for standard normal
        u1 = rng.rand
        u2 = rng.rand
        z = Math.sqrt(-2.0 * Math.log(u1)) * Math.cos(2.0 * Math::PI * u2)

        Math.exp(mu + sigma * z) - 1
      end

      # ========================================
      # Cash Flow Components
      # ========================================

      def annual_income_at(date)
        income = 0.0

        # Salary income from persons (until their salary_end_date)
        scenario_persons.each do |rsp|
          if rsp.salary_end_date.nil? || date < rsp.salary_end_date
            income += (rsp.current_annual_salary || 0).to_f
          end

          # State pension (from start date)
          if rsp.state_pension_start_date.present? && date >= rsp.state_pension_start_date
            income += (rsp.state_pension_monthly || 0).to_f * 12
          end

          # Post-retirement income (between start and end dates)
          if rsp.post_retirement_income_start_date.present? && date >= rsp.post_retirement_income_start_date
            unless rsp.post_retirement_income_end_date.present? && date > rsp.post_retirement_income_end_date
              income += (rsp.post_retirement_income_monthly || 0).to_f * 12
            end
          end
        end

        # Pension sources (from payout_start_date)
        pension_sources_data.each do |ps|
          if ps[:payout_start_date].present? && date >= ps[:payout_start_date]
            income += (ps[:expected_monthly_payout] || 0).to_f * 12
          end
        end

        # PrivateLoan income (until maturity)
        incoming_payments_data.each do |p|
          if p[:end_date].nil? || date < p[:end_date]
            income += p[:monthly_amount].to_f * 12
          end
        end

        income
      end

      def annual_obligations_at(date)
        total = 0.0

        obligations_data.each do |o|
          if o[:end_date].nil? || date < o[:end_date]
            total += o[:monthly_amount].to_f * 12
          end
        end

        # Apply milestone adjustments
        sorted_milestones.each do |m|
          next unless m.date <= date

          case m.milestone_type
          when "debt_payoff", "bauspar_phase_change"
            total -= (m.amount || 0).to_f * 12
          end
        end

        [ total, 0 ].max
      end

      def annual_contributions_at(date)
        # Contributions stop when all persons have stopped working
        still_working = scenario_persons.any? { |rsp|
          rsp.salary_end_date.nil? || date < rsp.salary_end_date
        }

        # If no persons defined, assume working until retirement_monthly_expenses is set
        still_working = true if scenario_persons.empty?

        return 0.0 unless still_working

        (monthly_contribution || effective_savings).to_f * 12
      end

      def cashout_amount_at(date)
        total = 0.0

        cashout_events.each do |event|
          event_date = event[:date]
          # Match if this year contains the cashout date
          if event_date >= date && event_date < date + 1.year
            total += event[:amount].to_f
          end
        end

        total
      end

      # ========================================
      # Analysis
      # ========================================

      def analyze_results(all_paths)
        success_count = all_paths.count { |path| path.last > 0 }
        raw_rate = (success_count.to_f / all_paths.size * 100)
        success_rate = (raw_rate / 5.0).round * 5 # Round to nearest 5%

        years = (0..projection_years).to_a
        percentiles = {}

        [ 10, 25, 50, 75, 90 ].each do |pct|
          percentiles["p#{pct}"] = years.map do |year|
            values = all_paths.map { |path| path[year] || 0 }.sort
            percentile_value(values, pct).round(2)
          end
        end

        # Find depletion years for failed paths
        failed_paths = all_paths.select { |path| path.last <= 0 }
        depletion_years = failed_paths.map { |path|
          path.index { |v| v <= 0 } || projection_years
        }

        {
          success_rate: success_rate,
          years: years,
          percentiles: percentiles,
          median_depletion_year: depletion_years.any? ? median(depletion_years) : nil,
          worst_case_depletion_year: depletion_years.any? ? depletion_years.min : nil
        }
      end

      def percentile_value(sorted_array, percentile)
        return 0 if sorted_array.empty?
        k = (percentile / 100.0 * (sorted_array.size - 1)).round
        sorted_array[k]
      end

      def median(array)
        sorted = array.sort
        mid = sorted.size / 2
        sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
      end

      # ========================================
      # Parameters (with override support)
      # ========================================

      def initial_portfolio
        @initial_portfolio ||= (overrides[:current_portfolio_value] || scenario.scoped_portfolio_value).to_f
      end

      def growth_rate
        (overrides[:portfolio_growth_rate] || scenario.portfolio_growth_rate || 7.0).to_f / 100.0
      end

      def growth_std_dev
        (overrides[:portfolio_growth_std_dev] || scenario.portfolio_growth_std_dev || 15.0).to_f / 100.0
      end

      def inflation_rate
        (overrides[:inflation_rate] || scenario.inflation_rate || 3.0).to_f / 100.0
      end

      def annual_expenses
        (overrides[:retirement_monthly_expenses] || scenario.retirement_monthly_expenses || 0).to_f * 12
      end

      def monthly_contribution
        overrides[:monthly_contribution] || scenario.monthly_contribution
      end

      def effective_savings
        scenario.effective_monthly_savings rescue 0
      end

      def target_age
        (overrides[:target_age] || scenario.target_age || 90).to_i
      end

      def effective_simulation_count
        count = (overrides[:simulation_count] || scenario.simulation_count || 1000).to_i
        [ count, MAX_SIMULATIONS ].min
      end

      def projection_years
        # Estimate current age from the oldest person, or assume 40 years
        ages = scenario_persons.filter_map { |rsp|
          rsp.person&.respond_to?(:age) ? rsp.person.age : nil
        }
        current_age = ages.min || 35 # Default assumption
        [ target_age - current_age, 1 ].max
      end

      def start_date
        scenario.calculation_date || Date.today
      end

      # ========================================
      # Cached Data (loaded once per run)
      # ========================================

      def scenario_persons
        @scenario_persons ||= scenario.retirement_scenario_persons.includes(:person).to_a
      end

      def pension_sources_data
        @pension_sources_data ||= scenario.pension_sources.with_payout.map { |ps|
          { expected_monthly_payout: ps.expected_monthly_payout, payout_start_date: ps.payout_start_date }
        }
      end

      def obligations_data
        @obligations_data ||= scenario.fixed_obligations
      end

      def incoming_payments_data
        @incoming_payments_data ||= scenario.incoming_loan_payments
      end

      def sorted_milestones
        @sorted_milestones ||= scenario.milestones.chronological.to_a
      end

      def cashout_events
        @cashout_events ||= scenario.build_cashout_events(scenario.portfolio_growth_rate || 7.0)
      end
  end
end
