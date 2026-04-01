class Current < ActiveSupport::CurrentAttributes
  attribute :user_agent, :ip_address

  attribute :session

  delegate :family, to: :user, allow_nil: true

  def user
    impersonated_user || session&.user
  end

  def impersonated_user
    session&.active_impersonator_session&.impersonated
  end

  def true_user
    session&.user
  end

  # Returns the currently filtered person, or nil for "Everyone" view
  def person
    return nil unless session&.data&.dig("person_id")
    family&.persons&.find_by(id: session.data["person_id"])
  end
end
