class RetirementScenariosController < ApplicationController
  before_action :set_scenario, only: [ :show, :edit, :update, :destroy, :recalculate, :explore, :apply_exploration ]

  WIZARD_STEPS = %w[basics cashflow income portfolio].freeze

  def index
    @scenarios = Current.family.retirement_scenarios.order(is_primary: :desc, created_at: :desc)
    @primary_scenario = @scenarios.find(&:is_primary)
  end

  def show
    # Main retirement planning view
  end

  def new
    @scenario = Current.family.retirement_scenarios.build(
      calculation_date: Date.today,
      portfolio_withdrawal_rate: 4.0,
      portfolio_growth_rate: 7.0,
      inflation_rate: 3.0,
      name: "My Retirement Plan",
      scenario_type: params[:scenario_type] || "household"
    )

    build_scenario_persons(@scenario)
    @scenario.build_pension_sources_for_accounts
    @persons = Current.family.persons.ordered
    @analysis = build_cash_flow_analysis
    @step = params[:step] || "basics"
    @step = "basics" unless WIZARD_STEPS.include?(@step)
    render layout: "wizard"
  end

  def create
    @scenario = Current.family.retirement_scenarios.build(scenario_params)
    @scenario.calculation_date = Date.today

    if @scenario.save
      @scenario.build_auto_milestones
      redirect_to retirement_scenario_path(@scenario), notice: t(".success")
    else
      @step = params[:step] || "basics"
      render :new, status: :unprocessable_entity, layout: "wizard"
    end
  end

  def update
    if @scenario.update(scenario_params)
      redirect_to retirement_scenario_path(@scenario), notice: t(".success")
    else
      @step = "basics"
      render :edit, status: :unprocessable_entity, layout: "wizard"
    end
  end

  def edit
    build_scenario_persons(@scenario)
    @scenario.build_pension_sources_for_accounts
    @persons = Current.family.persons.ordered
    @analysis = build_cash_flow_analysis
    @step = "basics"
    render layout: "wizard"
  end

  def destroy
    @scenario.destroy
    redirect_to retirement_scenarios_path, notice: t(".success")
  end

  # Interactive exploration: recalculate with overridden dates (no save)
  def explore
    explorer = RetirementScenario::Explorer.new(@scenario, explore_params)
    @explored = explorer.explore

    respond_to do |format|
      format.turbo_stream
    end
  end

  # Persist explored dates
  def apply_exploration
    @scenario.apply_exploration!(explore_params)
    redirect_to retirement_scenario_path(@scenario), notice: t(".success")
  rescue => e
    redirect_to retirement_scenario_path(@scenario), alert: t(".failure")
  end

  # Recalculate with current data and create snapshot
  def recalculate
    @scenario.recalculate!
    @scenario.create_snapshot_if_needed!(notes: "Manual snapshot")
    redirect_to retirement_scenario_path(@scenario), notice: t(".success")
  end

  private

    def set_scenario
      @scenario = Current.family.retirement_scenarios.find(params[:id])
    end

    def scenario_params
      params.require(:retirement_scenario).permit(
        :name,
        :description,
        :is_primary,
        :scenario_type,
        :person_id,
        :retirement_monthly_expenses,
        :portfolio_withdrawal_rate,
        :salary_end_date,
        :current_annual_salary,
        :gesetzliche_rente_start_date,
        :gesetzliche_rente_monthly,
        :riester_monthly,
        :ruerup_monthly,
        :betriebsrente_monthly,
        :other_pension_start_date,
        :other_pension_monthly,
        :portfolio_growth_rate,
        :monthly_contribution,
        :inflation_rate,
        :after_tax_monthly_income,
        :monthly_living_expenses,
        :analysis_year,
        pension_sources_attributes: [ :id, :account_id, :expected_monthly_payout, :payout_start_date, :_destroy ],
        milestones_attributes: [ :id, :milestone_type, :date, :label, :amount, :account_id, :_destroy ],
        linked_payments_attributes: [ :id, :transaction_name, :monthly_amount, :account_id, :is_regular_expense, :_destroy ],
        retirement_scenario_persons_attributes: [
          :id, :person_id,
          :current_annual_salary, :salary_end_date,
          :retirement_age, :target_retirement_date,
          :state_pension_start_date, :state_pension_monthly,
          :post_retirement_income_monthly, :post_retirement_income_start_date, :post_retirement_income_end_date,
          :_destroy
        ]
      )
    end

    def explore_params
      params.permit(
        :salary_end_date,
        :gesetzliche_rente_start_date,
        person_retirement_dates: {},
        pension_payout_dates: {}
      )
    end

    def build_cash_flow_analysis
      year = params[:analysis_year]&.to_i || @scenario&.analysis_year || (Date.today.year - 1)
      analyzer = RetirementScenario::CashFlowAnalyzer.new(Current.family, year: year)
      analyzer.analyze
    rescue => e
      Rails.logger.error("Cash flow analysis failed: #{e.message}")
      nil
    end

    def build_scenario_persons(scenario)
      # Always pre-build persons for all family members so the form has them ready
      # when the user switches scenario type client-side (no server round-trip)
      Current.family.persons.ordered.each do |person|
        unless scenario.retirement_scenario_persons.any? { |rsp| rsp.person_id == person.id }
          scenario.retirement_scenario_persons.build(person: person)
        end
      end
    end
end
