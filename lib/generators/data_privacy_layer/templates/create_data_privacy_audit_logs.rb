# frozen_string_literal: true

class CreateDataPrivacyAuditLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :data_privacy_audit_logs do |t|
      t.references :organization, null: false, foreign_key: true, index: true
      t.string :action, null: false, comment: 'Action performed (dry_run, processed)'
      t.string :table_name, null: false, comment: 'Table that was processed'
      t.string :column_name, null: false, comment: 'Column that was anonymized'
      t.integer :records_count, null: false, default: 0, comment: 'Number of records processed'
      t.string :strategy, null: false, comment: 'Anonymization strategy used (delete, hash, mask)'
      t.datetime :performed_at, null: false, comment: 'When the action was performed'
      t.timestamps

      # Add indexes for common queries
      t.index [:organization_id, :performed_at], name: 'idx_data_privacy_audit_logs_org_time'
      t.index [:table_name, :column_name], name: 'idx_data_privacy_audit_logs_table_column'
      t.index :action, name: 'idx_data_privacy_audit_logs_action'
    end

    # Add comments to the table
    change_table_comment :data_privacy_audit_logs, 'Audit log for PDPL compliance data anonymization activities'
  end
end
