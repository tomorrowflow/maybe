class RetirementScenario
  class Explorer
    attr_reader :scenario, :result

    def initialize(scenario, params = {})
      @scenario = scenario
      @params = params.to_h.with_indifferent_access
    end

    def explore
      @result = scenario.dup

      # Preserve id for dom_id calls in partials
      @result.id = scenario.id

      apply_date_overrides
      apply_person_overrides
      apply_pension_overrides
      delegate_associations

      @result.calculate_retirement_metrics
      @result
    end

    private

      def apply_date_overrides
        if @params[:salary_end_date].present?
          @result.salary_end_date = Date.parse(@params[:salary_end_date])
        end

        if @params[:gesetzliche_rente_start_date].present?
          @result.gesetzliche_rente_start_date = Date.parse(@params[:gesetzliche_rente_start_date])
        end
      end

      def apply_person_overrides
        return unless @params[:person_retirement_dates].present?

        overrides = @params[:person_retirement_dates]
        explored_persons = scenario.retirement_scenario_persons.includes(:person).map do |rsp|
          if overrides[rsp.id.to_s].present?
            clone = rsp.dup
            clone.id = rsp.id
            new_date = Date.parse(overrides[rsp.id.to_s])
            clone.salary_end_date = new_date
            clone.target_retirement_date = new_date
            # Preserve the person association on the clone
            clone.define_singleton_method(:person) { rsp.person }
            clone
          else
            rsp
          end
        end

        @result.define_singleton_method(:retirement_scenario_persons) do
          RetirementScenarioPersonsProxy.new(explored_persons)
        end
      end

      def apply_pension_overrides
        return unless @params[:pension_payout_dates].present?

        overrides = @params[:pension_payout_dates]
        cloned_sources = scenario.pension_sources.includes(:account).map do |ps|
          if overrides[ps.id.to_s].present?
            clone = ps.dup
            clone.id = ps.id
            clone.payout_start_date = Date.parse(overrides[ps.id.to_s])
            clone.define_singleton_method(:account) { ps.account }
            clone
          else
            ps
          end
        end

        @result.define_singleton_method(:pension_sources) do
          PensionSourcesProxy.new(cloned_sources)
        end
      end

      def delegate_associations
        original = scenario
        explored_retirement_date = determine_explored_retirement_date

        # Delegate family and portfolio methods to the original persisted scenario
        @result.define_singleton_method(:family) { original.family }
        @result.define_singleton_method(:scoped_portfolio_value) { original.scoped_portfolio_value }
        @result.define_singleton_method(:scoped_accounts) { original.scoped_accounts }

        # Only override pension_sources if not already overridden
        unless @params[:pension_payout_dates].present?
          @result.define_singleton_method(:pension_sources) { original.pension_sources }
        end

        # Only override retirement_scenario_persons if not already overridden
        unless @params[:person_retirement_dates].present?
          @result.define_singleton_method(:retirement_scenario_persons) { original.retirement_scenario_persons }
        end

        # Override cashout events: auto-cash cashable pensions at the explored retirement date
        # if they don't have an explicit early_cashout_date
        if explored_retirement_date
          fallback_rate = original.portfolio_growth_rate || 7.0
          @result.define_singleton_method(:build_cashout_events) do |rate|
            events = []
            original.family.accounts.active.where(accountable_type: "Investment").includes(:accountable).each do |account|
              inv = account.accountable
              next unless inv.respond_to?(:allows_early_cashout?) && inv.allows_early_cashout?

              # Use explicit date if set, otherwise use the explored retirement date
              cashout_date = inv.early_cashout_date.presence || explored_retirement_date
              next unless cashout_date > Date.current

              amount = inv.projected_value_at(cashout_date, fallback_growth_rate: rate)
              next unless amount > 0

              events << { date: cashout_date, amount: amount, account_name: account.name, account_id: account.id }
            end
            events
          end
        end
      end

      def determine_explored_retirement_date
        if @params[:salary_end_date].present?
          Date.parse(@params[:salary_end_date])
        elsif @params[:person_retirement_dates].present?
          # Use the earliest person retirement date
          dates = @params[:person_retirement_dates].values.compact.reject(&:blank?).map { |d| Date.parse(d) }
          dates.min
        end
      end
  end

  # Lightweight proxy that quacks like an ActiveRecord collection for pension sources
  class PensionSourcesProxy
    include Enumerable

    def initialize(sources)
      @sources = sources
    end

    def each(&block)
      @sources.each(&block)
    end

    def with_payout
      self.class.new(@sources.select { |ps| ps.expected_monthly_payout.present? && ps.expected_monthly_payout > 0 })
    end

    def includes(*_args)
      self # Already loaded
    end

    def sum(field = nil, &block)
      if block_given?
        @sources.sum(&block)
      elsif field
        @sources.sum { |ps| ps.send(field) || 0 }
      else
        @sources.sum
      end
    end

    def any?(&block)
      block_given? ? @sources.any?(&block) : @sources.any?
    end

    def none?(&block)
      block_given? ? @sources.none?(&block) : @sources.none?
    end

    def joins(*_args)
      self
    end

    def where(conditions = {})
      # Support simple hash conditions for has_pension_source_of_type?
      filtered = @sources.select do |ps|
        conditions.all? do |key, value|
          if key == :accounts
            value.all? { |attr, val| ps.account&.send(attr) == val }
          else
            ps.send(key) == value
          end
        end
      end
      self.class.new(filtered)
    end

    def exists?
      @sources.any?
    end

    def count
      @sources.count
    end

    def size
      @sources.size
    end

    def map(&block)
      @sources.map(&block)
    end

    def select(&block)
      @sources.select(&block)
    end

    def to_a
      @sources
    end
  end

  # Lightweight proxy that quacks like an ActiveRecord collection for retirement scenario persons
  class RetirementScenarioPersonsProxy
    include Enumerable

    def initialize(persons)
      @persons = persons
    end

    def each(&block)
      @persons.each(&block)
    end

    def includes(*_args)
      self
    end

    def any?(&block)
      block_given? ? @persons.any?(&block) : @persons.any?
    end

    def none?(&block)
      block_given? ? @persons.none?(&block) : @persons.none?
    end

    def sum(&block)
      @persons.sum(&block)
    end

    def pluck(field)
      @persons.map { |p| p.send(field) }
    end

    def flat_map(&block)
      @persons.flat_map(&block)
    end

    def map(&block)
      @persons.map(&block)
    end

    def size
      @persons.size
    end

    def count
      @persons.count
    end

    def to_a
      @persons
    end
  end
end
