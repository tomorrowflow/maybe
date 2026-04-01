class Settings::PersonsController < ApplicationController
  layout "settings"

  before_action :set_person, only: :update

  def create
    @person = Current.family.persons.build(person_params)

    if @person.save
      redirect_to settings_profile_path, notice: "Person added successfully."
    else
      redirect_to settings_profile_path, alert: @person.errors.full_messages.join(", ")
    end
  end

  def update
    if @person.update(person_params)
      redirect_to settings_profile_path, notice: "Person updated successfully."
    else
      redirect_to settings_profile_path, alert: @person.errors.full_messages.join(", ")
    end
  end

  private

    def set_person
      @person = Current.family.persons.find(params[:id])
    end

    def person_params
      params.require(:person).permit(:first_name, :last_name, :date_of_birth, :retirement_age, :gender, :country, :joint_partner_id)
    end
end
