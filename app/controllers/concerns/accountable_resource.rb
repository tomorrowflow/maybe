module AccountableResource
  extend ActiveSupport::Concern

  included do
    include Periodable

    before_action :set_account, only: [ :show, :edit, :update ]
    before_action :set_link_options, only: :new
  end

  class_methods do
    def permitted_accountable_attributes(*attrs)
      @permitted_accountable_attributes = attrs if attrs.any?
      @permitted_accountable_attributes ||= [ :id ]
    end
  end

  def new
    @account = Current.family.accounts.build(
      currency: Current.family.currency,
      accountable: accountable_type.new
    )
  end

  def show
    @chart_view = params[:chart_view] || "balance"
    @q = params.fetch(:q, {}).permit(:search)
    entries = @account.entries.search(@q).reverse_chronological

    @pagy, @entries = pagy(entries, limit: params[:per_page] || "10")
  end

  def edit
  end

  def create
    resolved = resolved_account_params
    @account = Current.family.accounts.create_and_sync(resolved.except(:return_to))
    assign_account_persons(@account, resolved)
    @account.lock_saved_attributes!

    redirect_to resolved[:return_to].presence || @account, notice: t("accounts.create.success", type: accountable_type.name.underscore.humanize)
  end

  def update
    resolved = resolved_account_params

    # Handle balance update if provided
    if resolved[:balance].present?
      result = @account.set_current_balance(resolved[:balance].to_d)
      unless result.success?
        @error_message = result.error
        render :edit, status: :unprocessable_entity
        return
      end
      @account.sync_later
    end

    # Update remaining account attributes
    update_params = resolved.except(:return_to, :balance, :currency)
    unless @account.update(update_params)
      @error_message = @account.errors.full_messages.join(", ")
      render :edit, status: :unprocessable_entity
      return
    end

    assign_account_persons(@account, resolved)
    @account.lock_saved_attributes!
    redirect_back_or_to account_path(@account), notice: t("accounts.update.success", type: accountable_type.name.underscore.humanize)
  end

  private
    def set_link_options
      @show_us_link = Current.family.can_connect_plaid_us?
      @show_eu_link = Current.family.can_connect_plaid_eu?
    end

    def accountable_type
      controller_name.classify.constantize
    end

    def set_account
      @account = Current.family.accounts.find(params[:id])
    end

    def account_params
      params.require(:account).permit(
        :name, :balance, :subtype, :currency, :accountable_type, :return_to,
        :ownership_type, :ownership_selection, person_ids: [],
        accountable_attributes: self.class.permitted_accountable_attributes
      )
    end

    # Translate ownership_selection dropdown value into ownership_type + person_ids
    def resolved_account_params
      resolved = account_params.to_h
      selection = resolved.delete("ownership_selection")
      return resolved unless selection.present?

      if selection == "household"
        resolved["ownership_type"] = "household"
        resolved["person_ids"] = []
      elsif selection == "joint"
        resolved["ownership_type"] = "joint"
        # Find the joint partner pair
        joint_pair = Current.family.persons.where.not(joint_partner_id: nil).limit(2).pluck(:id)
        resolved["person_ids"] = joint_pair
      elsif selection.start_with?("personal_")
        resolved["ownership_type"] = "personal"
        resolved["person_ids"] = [ selection.delete_prefix("personal_") ]
      end

      resolved
    end

    def assign_account_persons(account, resolved)
      person_ids = resolved["person_ids"] || []
      account.account_persons.destroy_all
      person_ids.each do |pid|
        account.account_persons.create(person_id: pid)
      end
    end
end
