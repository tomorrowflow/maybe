class RetirementScenario
  class IncomeTimelineBuilder
    attr_reader :scenario

    def initialize(scenario)
      @scenario = scenario
    end

    def build_chart_data(years: 25)
      timeline = generate_timeline(years)

      {
        series: build_series_data(timeline),
        milestones: build_milestone_markers,
        gap_period: detect_gap_period,
        expenses_line: build_expenses_line(timeline),
        metadata: build_metadata(years, timeline)
      }
    end

    def to_json_chart_data(years: 25)
      build_chart_data(years: years).to_json
    end

    private

      def generate_timeline(years)
        start = scenario.calculation_date || Date.today
        months = years * 12
        expenses = (scenario.retirement_monthly_expenses || 0).to_f
        inflation = (scenario.inflation_rate || 3.0).to_f / 100.0

        months.times.map do |month|
          date = start + month.months
          years_elapsed = month / 12.0

          salary = monthly_salary_at(date)
          state_pension = monthly_state_pension_at(date)
          private_pensions = monthly_private_pensions_at(date)
          total = salary + state_pension + private_pensions
          adjusted_expenses = expenses * ((1 + inflation) ** years_elapsed)

          {
            date: date,
            month: month,
            salary: salary.round(2),
            state_pension: state_pension.round(2),
            private_pensions: private_pensions.round(2),
            total_income: total.round(2),
            expenses: adjusted_expenses.round(2),
            surplus_deficit: (total - adjusted_expenses).round(2)
          }
        end
      end

      def monthly_salary_at(date)
        scenario.retirement_scenario_persons.sum do |rsp|
          if rsp.current_annual_salary.present? && rsp.current_annual_salary > 0
            if rsp.salary_end_date.nil? || date <= rsp.salary_end_date
              rsp.current_annual_salary.to_f / 12.0
            else
              0
            end
          else
            0
          end
        end
      end

      def monthly_state_pension_at(date)
        scenario.retirement_scenario_persons.sum do |rsp|
          if rsp.state_pension_monthly.present? && rsp.state_pension_monthly > 0
            if rsp.state_pension_start_date.present? && date >= rsp.state_pension_start_date
              rsp.state_pension_monthly.to_f
            else
              0
            end
          else
            0
          end
        end
      end

      def monthly_private_pensions_at(date)
        scenario.pension_sources.with_payout.sum do |ps|
          if ps.payout_start_date.present? && date >= ps.payout_start_date
            (ps.expected_monthly_payout || 0).to_f
          else
            0
          end
        end
      end

      def build_series_data(timeline)
        {
          salary: timeline.map { |t| { date: t[:date].to_s, value: t[:salary] } },
          state_pension: timeline.map { |t| { date: t[:date].to_s, value: t[:state_pension] } },
          private_pensions: timeline.map { |t| { date: t[:date].to_s, value: t[:private_pensions] } },
          other: timeline.map { |t| { date: t[:date].to_s, value: 0 } }
        }
      end

      def build_milestone_markers
        markers = []

        scenario.retirement_scenario_persons.includes(:person).each do |rsp|
          rsp.income_milestones.each do |m|
            markers << {
              date: m[:date].to_s,
              type: m[:type].to_s,
              label: m[:label],
              amount: m[:amount]&.to_f&.round(2)
            }
          end
        end

        scenario.pension_sources.with_payout.includes(:account).each do |ps|
          next unless ps.payout_start_date.present?
          markers << {
            date: ps.payout_start_date.to_s,
            type: "pension_start",
            label: "#{ps.account.name} payout starts",
            amount: ps.expected_monthly_payout&.to_f&.round(2)
          }
        end

        markers.sort_by { |m| m[:date] }
      end

      def detect_gap_period
        salary_end_dates = scenario.retirement_scenario_persons
          .filter_map(&:salary_end_date)
        pension_start_dates = scenario.retirement_scenario_persons
          .filter_map(&:state_pension_start_date)
        pension_start_dates += scenario.pension_sources.with_payout
          .filter_map(&:payout_start_date)

        return nil if salary_end_dates.empty? || pension_start_dates.empty?

        latest_salary_end = salary_end_dates.max
        earliest_pension = pension_start_dates.min

        return nil unless earliest_pension > latest_salary_end + 1.day

        gap_start = latest_salary_end + 1.day
        gap_end = earliest_pension - 1.day
        months = ((gap_end.year - gap_start.year) * 12) + (gap_end.month - gap_start.month) + 1

        {
          start_date: gap_start.to_s,
          end_date: gap_end.to_s,
          months: months,
          monthly_shortfall: (scenario.retirement_monthly_expenses || 0).to_f.round(2)
        }
      end

      def build_expenses_line(timeline)
        timeline.map { |t| { date: t[:date].to_s, value: t[:expenses] } }
      end

      def build_metadata(years, timeline)
        start_date = scenario.calculation_date || Date.today

        {
          currency: scenario.family.currency,
          currency_symbol: Money::Currency.new(scenario.family.currency).symbol,
          start_date: start_date.to_s,
          end_date: (start_date + years.years).to_s,
          years: years,
          has_gap: detect_gap_period.present?,
          monthly_expenses: (scenario.retirement_monthly_expenses || 0).to_f.round(2),
          total_pension_income: scenario.calculate_total_pension_income.to_f.round(2)
        }
      end
  end
end
