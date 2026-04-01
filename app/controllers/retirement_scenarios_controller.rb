class RetirementScenariosController < ApplicationController
  before_action :set_scenario, only: [
    :show, :edit, :update, :destroy,
    :simulate, :explore, :apply_exploration,
    :snapshots, :income_timeline, :portfolio, :sweet_spot
  ]

  WIZARD_STEPS = %w[basics cashflow income portfolio].freeze

  def index
    @scenarios = Current.family.retirement_scenarios.order(is_primary: :desc, created_at: :desc)
    @primary_scenario = @scenarios.find(&:is_primary)
  end

  def show
    # Results are stored and only re-run on explicit user action (Simulate button)
  end

  def new
    @scenario = Current.family.retirement_scenarios.build(
      calculation_date: Date.today,
      portfolio_growth_rate: 7.0,
      portfolio_growth_std_dev: 15.0,
      inflation_rate: 3.0,
      simulation_count: 1000,
      target_age: Setting.retirement_target_age,
      name: "My Retirement Plan",
      scenario_type: params[:scenario_type] || "household"
    )

    build_scenario_persons(@scenario)
    @scenario.build_pension_sources_for_accounts
    @persons = Current.family.persons.ordered
    @analysis = build_cash_flow_analysis
    @step = validated_step
    render layout: "wizard"
  end

  def create
    @scenario = Current.family.retirement_scenarios.build(scenario_params)
    @scenario.calculation_date = Date.today

    if @scenario.save
      @scenario.build_auto_milestones
      @scenario.enqueue_monte_carlo!
      redirect_to retirement_scenario_path(@scenario), notice: t(".success")
    else
      @step = params[:step] || "basics"
      @analysis = build_cash_flow_analysis
      @persons = Current.family.persons.ordered
      render :new, status: :unprocessable_entity, layout: "wizard"
    end
  end

  def edit
    build_scenario_persons(@scenario)
    @scenario.build_pension_sources_for_accounts
    @persons = Current.family.persons.ordered
    @analysis = build_cash_flow_analysis
    @step = validated_step
    render layout: "wizard"
  end

  def update
    if @scenario.update(scenario_params)
      @scenario.enqueue_monte_carlo!
      redirect_to retirement_scenario_path(@scenario), notice: t(".success")
    else
      @step = "basics"
      @analysis = build_cash_flow_analysis
      @persons = Current.family.persons.ordered
      render :edit, status: :unprocessable_entity, layout: "wizard"
    end
  end

  def destroy
    @scenario.destroy
    redirect_to retirement_scenarios_path, notice: t(".success")
  end

  # Run Monte Carlo simulation + take snapshot (explicit user action — always enqueue)
  def simulate
    @scenario.build_auto_milestones
    @scenario.update_columns(monte_carlo_status: "pending")
    RunMonteCarloJob.perform_later(@scenario.id)
    @scenario.create_snapshot_if_needed!(notes: "Manual simulation")
    redirect_to retirement_scenario_path(@scenario), notice: "Simulation started"
  end

  # Interactive exploration: quick Monte Carlo with overridden params (no save)
  def explore
    explorer = RetirementScenario::Explorer.new(@scenario, explore_params)
    @explored_results = explorer.explore

    respond_to do |format|
      format.turbo_stream
    end
  end

  # Persist explored params and re-simulate
  def apply_exploration
    @scenario.apply_exploration!(explore_params)
    redirect_to retirement_scenario_path(@scenario), notice: t(".success")
  rescue => e
    redirect_to retirement_scenario_path(@scenario), alert: t(".failure")
  end

  # Snapshot history page
  def snapshots
    @snapshots = @scenario.snapshots.reverse_chronological
    @chart_data = RetirementScenario::SnapshotHistoryBuilder.new(@scenario).build_chart_data
  end

  # Income timeline page
  def income_timeline
    if params[:run] == "true" || (@scenario.parsed_income_timeline_results.nil? && !@scenario.income_timeline_running?)
      @scenario.enqueue_income_timeline!
    end
    @chart_data = @scenario.parsed_income_timeline_results
  end

  # Portfolio projection page
  def portfolio
    @chart_data = RetirementScenario::PortfolioProjectionBuilder.new(@scenario).build_chart_data
  end

  # Sweet spot analysis page
  def sweet_spot
    if params[:run] == "true" || (@scenario.parsed_sweet_spot_results.nil? && !@scenario.sweet_spot_running?)
      @scenario.enqueue_sweet_spot!
    end
    @analysis = @scenario.parsed_sweet_spot_results
  end

  private

    def set_scenario
      @scenario = Current.family.retirement_scenarios.find(params[:id])
    end

    def scenario_params
      params.require(:retirement_scenario).permit(
        :name, :description, :is_primary, :scenario_type, :person_id,
        :retirement_monthly_expenses,
        :portfolio_growth_rate, :portfolio_growth_std_dev, :inflation_rate,
        :simulation_count, :target_age,
        :monthly_contribution, :after_tax_monthly_income, :monthly_living_expenses,
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
        :retirement_monthly_expenses, :monthly_contribution,
        :portfolio_growth_rate, :inflation_rate, :target_age,
        person_retirement_dates: {},
        pension_payout_dates: {}
      )
    end

    def validated_step
      step = params[:step] || "basics"
      WIZARD_STEPS.include?(step) ? step : "basics"
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
      Current.family.persons.ordered.each do |person|
        unless scenario.retirement_scenario_persons.any? { |rsp| rsp.person_id == person.id }
          scenario.retirement_scenario_persons.build(person: person)
        end
      end
    end
end
