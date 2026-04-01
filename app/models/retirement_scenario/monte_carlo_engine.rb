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
      # Two-Pool Simulation
      # ========================================

      def simulate_one_path(rng)
        savings = initial_savings
        investments = initial_investments
        yearly_totals = [ savings + investments ]
        yearly_savings = [ savings ]

        projection_years.times do |year|
          current_date = start_date + year.years

          # Growth: each pool grows independently
          investment_return = random_log_normal_return(rng)
          investments *= (1 + investment_return)
          savings *= (1 + savings_rate)

          # Cash flows
          income = annual_income_at(current_date)
          expenses = annual_expenses * ((1 + inflation_rate) ** year)
          obligations = annual_obligations_at(current_date)
          contributions = annual_contributions_at(current_date)
          cashout = cashout_amount_at(current_date)

          # Cashouts go to savings (pension liquidations land in bank account)
          savings += cashout

          # Net cash flow = income + contributions - expenses - obligations
          net_flow = income + contributions - expenses - obligations

          if net_flow >= 0
            # Surplus → savings
            savings += net_flow
          else
            # Deficit → draw from savings first, then investments
            deficit = -net_flow
            if savings >= deficit
              savings -= deficit
            else
              deficit -= savings
              savings = 0
              investments -= deficit
            end
          end

          # Overflow: if savings exceed threshold × annual expenses, move excess to investments
          if overflow_threshold > 0
            expense_cap = expenses * overflow_threshold
            if savings > expense_cap && expense_cap > 0
              overflow = savings - expense_cap
              investments += overflow
              savings -= overflow
            end
          end

          investments = [ investments, 0 ].max
          savings = [ savings, 0 ].max

          yearly_totals << savings + investments
          yearly_savings << savings
        end

        { totals: yearly_totals, savings: yearly_savings }
      end

      # Log-normal return: prevents returns below -100%
      def random_log_normal_return(rng)
        mean = growth_rate
        std_dev = growth_std_dev

        return mean if std_dev == 0

        variance = std_dev ** 2
        mu = Math.log((1 + mean) ** 2 / Math.sqrt(variance + (1 + mean) ** 2))
        sigma = Math.sqrt(Math.log(1 + variance / (1 + mean) ** 2))

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

        scenario_persons.each do |rsp|
          if rsp.salary_end_date.nil? || date < rsp.salary_end_date
            income += (rsp.current_annual_salary || 0).to_f
          end

          if rsp.state_pension_start_date.present? && date >= rsp.state_pension_start_date
            income += (rsp.state_pension_monthly || 0).to_f * 12
          end

          if rsp.post_retirement_income_start_date.present? && date >= rsp.post_retirement_income_start_date
            unless rsp.post_retirement_income_end_date.present? && date > rsp.post_retirement_income_end_date
              income += (rsp.post_retirement_income_monthly || 0).to_f * 12
            end
          end
        end

        pension_sources_data.each do |ps|
          if ps[:payout_start_date].present? && date >= ps[:payout_start_date]
            income += (ps[:expected_monthly_payout] || 0).to_f * 12
          end
        end

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
          started = o[:start_date].nil? || date >= o[:start_date]
          ended = o[:end_date].present? && date >= o[:end_date]
          total += o[:monthly_amount].to_f * 12 if started && !ended
        end

        [ total, 0 ].max
      end

      def annual_contributions_at(date)
        still_working = scenario_persons.any? { |rsp|
          rsp.salary_end_date.nil? || date < rsp.salary_end_date
        }
        still_working = true if scenario_persons.empty?
        return 0.0 unless still_working

        (monthly_contribution || effective_savings_amount).to_f * 12
      end

      def cashout_amount_at(date)
        total = 0.0
        cashout_events.each do |event|
          event_date = event[:date]
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
        # Success: total > 0 AND savings >= target
        target = target_savings_amount
        success_count = all_paths.count { |path|
          path[:totals].last > 0 && path[:savings].last >= target
        }
        raw_rate = (success_count.to_f / all_paths.size * 100)
        success_rate = (raw_rate / 5.0).round * 5

        years = (0..projection_years).to_a
        percentiles = {}
        savings_percentiles = {}

        [ 10, 25, 50, 75, 90 ].each do |pct|
          percentiles["p#{pct}"] = years.map do |year|
            values = all_paths.map { |path| path[:totals][year] || 0 }.sort
            percentile_value(values, pct).round(2)
          end
          savings_percentiles["p#{pct}"] = years.map do |year|
            values = all_paths.map { |path| path[:savings][year] || 0 }.sort
            percentile_value(values, pct).round(2)
          end
        end

        failed_paths = all_paths.select { |path| path[:totals].last <= 0 || path[:savings].last < target }
        depletion_years = all_paths.select { |p| p[:totals].last <= 0 }.map { |path|
          path[:totals].index { |v| v <= 0 } || projection_years
        }

        savings_depletion = all_paths.map { |path|
          path[:savings].index { |v| v <= 0 }
        }.compact

        {
          success_rate: success_rate,
          years: years,
          percentiles: percentiles,
          savings_percentiles: savings_percentiles,
          target_savings: target.round(2),
          initial_savings: initial_savings.round(2),
          initial_investments: initial_investments.round(2),
          median_depletion_year: depletion_years.any? ? median(depletion_years) : nil,
          worst_case_depletion_year: depletion_years.any? ? depletion_years.min : nil,
          median_savings_depletion_year: savings_depletion.any? ? median(savings_depletion) : nil
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

      def initial_savings
        @initial_savings ||= (overrides[:current_savings_value] || scenario.scoped_savings_value).to_f
      end

      def initial_investments
        @initial_investments ||= (overrides[:current_investment_value] || scenario.scoped_investment_value).to_f
      end

      def growth_rate
        (overrides[:portfolio_growth_rate] || scenario.portfolio_growth_rate || 7.0).to_f / 100.0
      end

      def growth_std_dev
        (overrides[:portfolio_growth_std_dev] || scenario.portfolio_growth_std_dev || 15.0).to_f / 100.0
      end

      def savings_rate
        @savings_rate ||= (overrides[:savings_growth_rate] || scenario.weighted_savings_rate || 1.0).to_f / 100.0
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

      def effective_savings_amount
        scenario.effective_monthly_savings rescue 0
      end

      def target_age
        (overrides[:target_age] || scenario.target_age || 90).to_i
      end

      def target_savings_amount
        target = (Setting.retirement_target_savings || 50_000).to_f
        person_count = [ scenario_persons.size, 1 ].max
        target * person_count
      end

      def overflow_threshold
        (scenario.savings_overflow_threshold || 2.0).to_f
      end

      def effective_simulation_count
        count = (overrides[:simulation_count] || scenario.simulation_count || 1000).to_i
        [ count, MAX_SIMULATIONS ].min
      end

      def projection_years
        ages = scenario_persons.filter_map { |rsp|
          rsp.person&.respond_to?(:age) ? rsp.person.age : nil
        }
        current_age = ages.min || 35
        [ target_age - current_age, 1 ].max
      end

      def start_date
        scenario.calculation_date || Date.today
      end

      # ========================================
      # Cached Data (loaded once per run)
      # ========================================

      def scenario_persons
        @scenario_persons ||= begin
          persons = scenario.retirement_scenario_persons.includes(:person).to_a
          date_overrides = overrides[:person_retirement_dates] || {}

          persons.map do |rsp|
            if date_overrides[rsp.id.to_s].present?
              PersonProxy.new(rsp, date_overrides[rsp.id.to_s])
            else
              rsp
            end
          end
        end
      end

      def pension_sources_data
        @pension_sources_data ||= begin
          date_overrides = overrides[:pension_payout_dates] || {}

          scenario.pension_sources.with_payout.map { |ps|
            payout_date = date_overrides[ps.id.to_s] || ps.payout_start_date
            { expected_monthly_payout: ps.expected_monthly_payout, payout_start_date: payout_date }
          }
        end
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

      class PersonProxy
        attr_reader :original, :overridden_date

        delegate :person, :current_annual_salary, :state_pension_monthly,
                 :state_pension_start_date, :post_retirement_income_monthly,
                 :post_retirement_income_start_date, :post_retirement_income_end_date,
                 :id, to: :original

        def initialize(original, overridden_date)
          @original = original
          @overridden_date = overridden_date
        end

        def salary_end_date
          overridden_date
        end

        def target_retirement_date
          overridden_date
        end
      end
  end
end
