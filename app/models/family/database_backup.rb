class Family::DatabaseBackup
  def initialize(family)
    @family = family
  end

  def generate_backup
    conn = ActiveRecord::Base.connection
    tables = conn.tables.sort - %w[schema_migrations ar_internal_metadata]

    sql_parts = []
    sql_parts << "-- Maybe Finance Full Backup"
    sql_parts << "-- Generated: #{Time.current.iso8601}"
    sql_parts << "-- Database: #{conn.current_database}"
    sql_parts << "-- Tables: #{tables.size}"
    sql_parts << ""
    sql_parts << "BEGIN;"
    sql_parts << ""

    tables.each do |table|
      columns = conn.columns(table)
      column_names = columns.map(&:name)
      rows = conn.select_all("SELECT * FROM #{conn.quote_table_name(table)}")

      next if rows.empty?

      sql_parts << "-- Table: #{table} (#{rows.count} rows)"

      # Generate INSERT statements in batches
      rows.each do |row|
        values = column_names.map do |col|
          val = row[col]
          if val.nil?
            "NULL"
          elsif val.is_a?(String)
            conn.quote(val)
          elsif val.is_a?(TrueClass) || val.is_a?(FalseClass)
            val.to_s
          elsif val.is_a?(Time) || val.is_a?(DateTime)
            conn.quote(val.iso8601(6))
          elsif val.is_a?(Date)
            conn.quote(val.to_s)
          elsif val.is_a?(Hash) || val.is_a?(Array)
            conn.quote(val.to_json)
          else
            val.to_s
          end
        end

        sql_parts << "INSERT INTO #{conn.quote_table_name(table)} (#{column_names.map { |c| conn.quote_column_name(c) }.join(", ")}) VALUES (#{values.join(", ")}) ON CONFLICT DO NOTHING;"
      end

      sql_parts << ""
    end

    sql_parts << "COMMIT;"
    sql_parts << ""

    # Also include schema for reference
    sql_parts << "-- Schema version: #{ActiveRecord::Migrator.current_version}"

    sql_parts.join("\n")
  end
end
