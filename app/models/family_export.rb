class FamilyExport < ApplicationRecord
  belongs_to :family

  has_one_attached :export_file

  enum :status, {
    pending: "pending",
    processing: "processing",
    completed: "completed",
    failed: "failed"
  }, default: :pending, validate: true

  enum :export_type, {
    csv: "csv",
    full_backup: "full_backup"
  }, default: :csv

  scope :ordered, -> { order(created_at: :desc) }

  def filename
    if full_backup?
      "maybe_backup_#{created_at.strftime('%Y%m%d_%H%M%S')}.sql"
    else
      "maybe_export_#{created_at.strftime('%Y%m%d_%H%M%S')}.zip"
    end
  end

  def downloadable?
    completed? && export_file.attached?
  end
end
