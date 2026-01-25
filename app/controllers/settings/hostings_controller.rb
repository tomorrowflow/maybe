class Settings::HostingsController < ApplicationController
  layout "settings"

  guard_feature unless: -> { self_hosted? }

  before_action :ensure_admin, only: [ :clear_cache, :import_mcc_codes ]

  def show
    synth_provider = Provider::Registry.get_provider(:synth)
    @synth_usage = synth_provider&.usage
    @mcc_codes_count = MccCode.count
  end

  def update
    if hosting_params.key?(:require_invite_for_signup)
      Setting.require_invite_for_signup = hosting_params[:require_invite_for_signup]
    end

    if hosting_params.key?(:require_email_confirmation)
      Setting.require_email_confirmation = hosting_params[:require_email_confirmation]
    end

    if hosting_params.key?(:synth_api_key)
      Setting.synth_api_key = hosting_params[:synth_api_key]
    end

    redirect_to settings_hosting_path, notice: t(".success")
  rescue ActiveRecord::RecordInvalid => error
    flash.now[:alert] = t(".failure")
    render :show, status: :unprocessable_entity
  end

  def clear_cache
    DataCacheClearJob.perform_later(Current.family)
    redirect_to settings_hosting_path, notice: t(".cache_cleared")
  end

  def import_mcc_codes
    file = params[:mcc_file]

    if file.blank?
      redirect_to settings_hosting_path, alert: "Please select a file to upload."
      return
    end

    result = case File.extname(file.original_filename).downcase
    when ".csv"
      MccCode.import_from_csv(file)
    when ".json"
      MccCode.import_from_json(file)
    else
      { imported: 0, errors: [ "Unsupported file format. Please upload a CSV or JSON file." ] }
    end

    if result[:errors].any?
      redirect_to settings_hosting_path, alert: "Imported #{result[:imported]} MCC codes with #{result[:errors].size} errors."
    else
      redirect_to settings_hosting_path, notice: "Successfully imported #{result[:imported]} MCC codes."
    end
  end

  private
    def hosting_params
      params.require(:setting).permit(:require_invite_for_signup, :require_email_confirmation, :synth_api_key)
    end

    def ensure_admin
      redirect_to settings_hosting_path, alert: t(".not_authorized") unless Current.user.admin?
    end
end
