class Settings::Person::DeletionsController < ApplicationController
  layout "settings"

  before_action :set_person
  before_action :set_replacement_person, only: :create

  def new
    @replacement_persons = Current.family.persons.where.not(id: @person.id).ordered
  end

  def create
    if Current.family.persons.count <= 1
      redirect_to settings_profile_path, alert: "Cannot remove the last household member."
      return
    end

    if @person.primary?
      redirect_to settings_profile_path, alert: "Cannot remove the primary household member."
      return
    end

    @person.replace_and_destroy!(@replacement_person)
    redirect_to settings_profile_path, notice: "#{@person.display_name} removed. Accounts transferred to #{@replacement_person&.display_name || 'household'}."
  end

  private

    def set_person
      @person = Current.family.persons.find(params[:person_id])
    end

    def set_replacement_person
      if params[:replacement_person_id].present?
        @replacement_person = Current.family.persons.find(params[:replacement_person_id])
      end
    end
end
