class RetirementScenariosController < ApplicationController
  before_action :set_scenario, only: [ :show, :edit, :update, :destroy, :recalculate ]

  WIZARD_STEPS = %w[basics income portfolio].freeze

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
      name: "My Retirement Plan"
    )
    @scenario.build_pension_sources_for_accounts
    @step = params[:step] || "basics"
    @step = "basics" unless WIZARD_STEPS.include?(@step)
    render layout: "wizard"
  end

  def create
    @scenario = Current.family.retirement_scenarios.build(scenario_params)
    @scenario.calculation_date = Date.today

    if @scenario.save
      redirect_to retirement_scenario_path(@scenario), notice: "Retirement scenario created"
    else
      @step = params[:step] || "basics"
      render :new, status: :unprocessable_entity, layout: "wizard"
    end
  end

  def update
    if @scenario.update(scenario_params)
      redirect_to retirement_scenario_path(@scenario), notice: "Scenario updated"
    else
      @step = "basics"
      render :edit, status: :unprocessable_entity, layout: "wizard"
    end
  end

  def edit
    @scenario.build_pension_sources_for_accounts
    @step = "basics"
    render layout: "wizard"
  end

  def destroy
    @scenario.destroy
    redirect_to retirement_scenarios_path, notice: "Scenario deleted"
  end

  # Recalculate with current data and create snapshot
  def recalculate
    @scenario.recalculate!
    @scenario.create_snapshot_if_needed!(notes: "Manual snapshot")
    redirect_to retirement_scenario_path(@scenario), notice: "Scenario recalculated and snapshot saved"
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
        pension_sources_attributes: [:id, :account_id, :expected_monthly_payout, :payout_start_date, :_destroy]
      )
    end
end
