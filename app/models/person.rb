class Person < ApplicationRecord
  self.table_name = "persons"

  belongs_to :family
  belongs_to :joint_partner, class_name: "Person", optional: true
  has_one :user, dependent: :nullify
  has_many :account_persons, dependent: :destroy
  has_many :accounts, through: :account_persons
  has_many :retirement_scenarios, dependent: :nullify
  has_many :retirement_scenario_persons, dependent: :destroy

  validates :first_name, presence: true

  after_save :sync_joint_partner

  scope :primary, -> { where(primary: true) }
  scope :ordered, -> { order(:created_at) }

  def display_name
    [ first_name, last_name ].compact.join(" ").presence || "Unknown"
  end

  def age
    return nil unless date_of_birth.present?
    today = Date.current
    age = today.year - date_of_birth.year
    age -= 1 if today < date_of_birth + age.years
    age
  end

  def estimated_retirement_date
    return nil unless date_of_birth.present? && retirement_age.present?
    date_of_birth + retirement_age.years
  end

  def years_until_retirement
    target = estimated_retirement_date
    return nil unless target.present?
    ((target - Date.current) / 365.25).round(1)
  end

  # Transfer all account associations to replacement person (or to household), then destroy
  def replace_and_destroy!(replacement)
    transaction do
      if replacement
        # Transfer personal account_persons to the replacement
        account_persons.each do |ap|
          if ap.account.personal?
            ap.update!(person: replacement)
          elsif ap.account.joint?
            # For joint accounts, replace this person's slot with the replacement
            ap.update!(person: replacement)
          end
        end

        # Transfer retirement scenarios owned by this person
        retirement_scenarios.update_all(person_id: replacement.id)
        retirement_scenario_persons.update_all(person_id: replacement.id)
      else
        # No replacement: set personal accounts to household and remove person links
        account_persons.includes(:account).each do |ap|
          account = ap.account
          ap.destroy!
          # If this was the only person on a personal account, make it household
          account.update!(ownership_type: "household") if account.account_persons.reload.empty?
        end

        retirement_scenarios.update_all(person_id: nil, scenario_type: "household")
        retirement_scenario_persons.destroy_all
      end

      # Clear joint partner reference
      if joint_partner.present?
        joint_partner.update_column(:joint_partner_id, nil)
      end

      destroy!
    end
  end

  private

    # Keep joint partnership bidirectional: if A picks B, B should also point to A
    def sync_joint_partner
      if joint_partner_id.present?
        joint_partner.update_column(:joint_partner_id, id) unless joint_partner.joint_partner_id == id
      elsif saved_change_to_joint_partner_id? && joint_partner_id_before_last_save.present?
        old_partner = Person.find_by(id: joint_partner_id_before_last_save)
        old_partner&.update_column(:joint_partner_id, nil) if old_partner&.joint_partner_id == id
      end
    end
end
