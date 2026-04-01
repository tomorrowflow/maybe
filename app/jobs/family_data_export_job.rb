class FamilyDataExportJob < ApplicationJob
  queue_as :default

  def perform(family_export)
    family_export.update!(status: :processing)

    if family_export.full_backup?
      generate_full_backup(family_export)
    else
      generate_csv_export(family_export)
    end

    family_export.update!(status: :completed)
  rescue => e
    Rails.logger.error "Family export failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    family_export.update!(status: :failed)
  end

  private

    def generate_csv_export(family_export)
      exporter = Family::DataExporter.new(family_export.family)
      zip_file = exporter.generate_export

      family_export.export_file.attach(
        io: zip_file,
        filename: family_export.filename,
        content_type: "application/zip"
      )
    end

    def generate_full_backup(family_export)
      backup = Family::DatabaseBackup.new(family_export.family)
      dump_data = backup.generate_backup

      family_export.export_file.attach(
        io: StringIO.new(dump_data),
        filename: family_export.filename,
        content_type: "application/octet-stream"
      )
    end
end
