class AddJointPartnerToPersons < ActiveRecord::Migration[7.2]
  def change
    add_reference :persons, :joint_partner, type: :uuid, foreign_key: { to_table: :persons }, null: true
  end
end
