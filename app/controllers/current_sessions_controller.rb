class CurrentSessionsController < ApplicationController
  def update
    if session_params[:tab_key].present? && session_params[:tab_value].present?
      Current.session.set_preferred_tab(session_params[:tab_key], session_params[:tab_value])
    end

    if params[:person_id].present?
      Current.session.data["person_id"] = params[:person_id]
      Current.session.save!
      redirect_back(fallback_location: root_path)
      return
    elsif params[:clear_person].present?
      Current.session.data.delete("person_id")
      Current.session.save!
      redirect_back(fallback_location: root_path)
      return
    end

    head :ok
  end

  private
    def session_params
      params.fetch(:current_session, {}).permit(:tab_key, :tab_value)
    end
end
