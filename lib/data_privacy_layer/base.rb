# frozen_string_literal: true

module DataPrivacyLayer
  class Base
    extend DataPrivacyLayer::Abstract
    abstract_methods :process

    attr_reader :organization_id, :dry_run, :batch_size

    def initialize(organization_id:, dry_run: false, batch_size: 10_000)
      @organization_id = organization_id
      @dry_run = dry_run
      @batch_size = batch_size
    end

    def call
      return unless valid_organization?

      log_start
      result = process
      log_completion(result)
      result
    rescue StandardError => e
      log_error(e)
      raise
    end

    private

    def valid_organization?
      organization_id.present? && Organization.exists?(id: organization_id)
    end

    def log_start
      Rails.logger.info("[PDPL] Starting #{self.class.name} for organization #{organization_id}")
    end

    def log_completion(result)
      Rails.logger.info("[PDPL] Completed #{self.class.name} for organization #{organization_id}. Result: #{result}")
    end

    def log_error(error)
      Rails.logger.error("[PDPL] Error in #{self.class.name} for organization #{organization_id}: #{error.message}")
    end

    def audit_log(action:, table_name:, column_name:, records_count:, strategy:, batches_processed: 1)
      return if dry_run

      # Enhanced logging with batch information
      log_message = "[PDPL] #{action.upcase}: #{table_name}.#{column_name} - #{records_count} records"
      log_message += " in #{batches_processed} batches" if batches_processed > 1
      log_message += " (strategy: #{strategy})"
      Rails.logger.info(log_message)

      DataPrivacyLayer::AuditLog.create!(
        organization_id: organization_id,
        action: action,
        table_name: table_name,
        column_name: column_name,
        records_count: records_count,
        strategy: strategy,
        performed_at: Time.current
      )
    end
  end
end
