class RetirementScenarioPerson < ApplicationRecord
  include Monetizable

  belongs_to :retirement_scenario
  belongs_to :person

  monetize :current_annual_salary,
           :state_pension_monthly,
           :post_retirement_income_monthly

  validates :person_id, uniqueness: { scope: :retirement_scenario_id }
  validates :current_annual_salary, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :state_pension_monthly, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :post_retirement_income_monthly, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  def display_name
    person.display_name
  end

  # When does this person formally stop working?
  def effective_retirement_date
    target_retirement_date || salary_end_date
  end

  # Total income from this person at a given date
  def income_at_date(date)
    total = 0

    # Salary
    if current_annual_salary.present? && current_annual_salary > 0
      if salary_end_date.nil? || date <= salary_end_date
        total += current_annual_salary / 12.0
      end
    end

    # State pension
    if state_pension_monthly.present? && state_pension_monthly > 0
      if state_pension_start_date.nil? || date >= state_pension_start_date
        total += state_pension_monthly
      end
    end

    # Post-retirement income (part-time work)
    if post_retirement_income_monthly.present? && post_retirement_income_monthly > 0
      start = post_retirement_income_start_date || salary_end_date
      if start && date >= start
        if post_retirement_income_end_date.nil? || date <= post_retirement_income_end_date
          total += post_retirement_income_monthly
        end
      end
    end

    total
  end

  # Income milestones for this person
  def income_milestones
    milestones = []

    if salary_end_date.present?
      milestones << {
        date: salary_end_date,
        type: :salary_end,
        label: "#{person.first_name} stops working",
        person_name: person.display_name
      }
    end

    if state_pension_start_date.present? && state_pension_monthly.to_f > 0
      milestones << {
        date: state_pension_start_date,
        type: :state_pension_start,
        label: "#{person.first_name}'s state pension starts",
        person_name: person.display_name,
        amount: state_pension_monthly
      }
    end

    if post_retirement_income_start_date.present? && post_retirement_income_monthly.to_f > 0
      milestones << {
        date: post_retirement_income_start_date,
        type: :post_retirement_start,
        label: "#{person.first_name} starts part-time work",
        person_name: person.display_name,
        amount: post_retirement_income_monthly
      }

      if post_retirement_income_end_date.present?
        milestones << {
          date: post_retirement_income_end_date,
          type: :post_retirement_end,
          label: "#{person.first_name} stops part-time work",
          person_name: person.display_name
        }
      end
    end

    milestones
  end

  private

    def monetizable_currency
      retirement_scenario&.family&.currency
    end
end
