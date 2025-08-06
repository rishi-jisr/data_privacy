# frozen_string_literal: true

module DataPrivacyLayer
  class Processor < Base
    def initialize(organization_id:, dry_run: false, batch_size: 10_000)
      super
    end

    def process
      validate_configuration_constraints

      {
        column_processing: process_column_anonymization,
        table_processing: process_table_deletions
      }
    end

    private

    def process_column_anonymization
      DataPrivacyLayer::Configuration.tables_to_process.each_with_object({}) do |model_name, results|
        table_name = model_name_to_table_name(model_name)
        next unless table_name && table_exists?(table_name)

        table_results = process_table_columns(model_name, table_name)
        results[model_name] = table_results unless table_results.empty?
      end
    end

    def process_table_deletions
      table_actions = DataPrivacyLayer::Configuration.all_table_level_actions
      return { message: 'No table-level actions configured' } if table_actions.empty?

      table_actions.each_with_object({}) do |(model_name, action_config), results|
        table_name = model_name_to_table_name(model_name)
        next unless table_name && table_exists?(table_name)
        next unless DataPrivacyLayer.configuration.adapter.organization_id_column?(table_name)

        results[model_name] = process_table_deletion(model_name, table_name, action_config)
      end
    end

    def process_table_columns(model_name, table_name)
      DataPrivacyLayer::Configuration.columns_for_table(model_name).each_with_object({}) do |column_name, results|
        next unless column_exists?(table_name, column_name)

        results[column_name] = process_column(model_name, table_name, column_name)
      end
    end

    def process_table_deletion(_model_name, table_name, action_config)
      reason = action_config['reason']
      team = action_config['team']

      if dry_run
        {
          action: 'delete_organization_records',
          would_delete: count_records_for_deletion(table_name),
          reason: reason,
          team: team,
          dry_run: true
        }
      else
        deleted_count = delete_organization_records(table_name)

        audit_log(
          action: 'delete_organization_records',
          table_name: table_name,
          column_name: 'Full Table ',
          records_count: deleted_count,
          strategy: 'table_deletion'
        )

        {
          action: 'delete_organization_records',
          deleted: deleted_count,
          reason: reason,
          team: team,
          executed: true
        }
      end
    end

    def count_records_for_deletion(table_name)
      query = "SELECT COUNT(*) as count FROM #{table_name} WHERE organization_id = $1"
      result = DataPrivacyLayer.configuration.adapter.connection.exec_query(query, 'PDPL Count', [organization_id])
      result.first['count']
    end

    def delete_organization_records(table_name)
      query = "DELETE FROM #{table_name} WHERE organization_id = $1"
      DataPrivacyLayer.configuration.adapter.connection.exec_delete(query, 'PDPL Delete', [organization_id])
    end

    def model_name_to_table_name(model_name)
      model_name.constantize.table_name
    rescue NameError, StandardError => e
      DataPrivacyLayer.configuration.logger.warn("[PDPL] Failed to resolve #{model_name}: #{e.message}")
      nil
    end

    def process_column(model_name, table_name, column_name)
      strategy_name = DataPrivacyLayer::Configuration.strategy_for_column(model_name, column_name)
      strategy = create_strategy(strategy_name, table_name, column_name, model_name)

      total_processed = 0
      sample_details = []
      batch_count = 0

      process_records_in_batches(model_name, table_name, column_name) do |batch_records|
        batch_count += 1
        DataPrivacyLayer.configuration.logger.info("Processing #{table_name}.#{column_name} batch #{batch_count}: #{batch_records.size} records (#{dry_run ? "DRY RUN" : "LIVE"})")

        result = strategy.process_records(batch_records, dry_run: dry_run)
        total_processed += result.size

        cleanup_versions_for(model_name, batch_records.map { |r| r['id'] }) if delete_versions?
        sample_details = result.first(5) if dry_run && sample_details.empty?
      end

      return { processed: 0, message: 'No records to process' } if total_processed.zero?

      audit_log(
        action: dry_run ? 'dry_run' : 'processed',
        table_name: table_name,
        column_name: column_name,
        records_count: total_processed,
        strategy: strategy_name.to_s,
        batches_processed: batch_count
      )

      {
        processed: total_processed,
        strategy: strategy_name,
        batches_processed: batch_count,
        details: dry_run ? sample_details : nil
      }
    end

    def create_strategy(strategy_name, table_name, column_name, model_name = nil)
      config_key = model_name || table_name
      column_config = DataPrivacyLayer::Configuration.pdpl_config.dig(config_key, 'columns', column_name) || {}

      case strategy_name
      when :delete
        Strategies::DeleteStrategy.new(table_name:, column_name:)
      when :hash
        Strategies::HashStrategy.new(table_name:, column_name:)
      when :mask
        Strategies::MaskStrategy.new(table_name:, column_name:, mask_config: column_config['mask_config'] || {})
      when :json
        Strategies::JsonStrategy.new(table_name:, column_name:, json_config: column_config['json_config'] || {})
      else
        raise ArgumentError, "Unknown strategy: #{strategy_name}"
      end
    end

    def process_records_in_batches(model_name, table_name, column_name)
      model_class = model_name.constantize
      scope = model_class.select(:id, column_name).where.not(column_name => nil)
      scope = scope.where(organization_id: organization_id) if column_exists?(table_name, 'organization_id')

      scope.find_in_batches(batch_size: batch_size) do |batch|
        records = batch.map { |r| { 'id' => r.id, column_name => r.send(column_name) } }
        yield(records) unless records.empty?
      end
    rescue NameError => e
      DataPrivacyLayer.configuration.logger.warn("Fallback to raw SQL for #{table_name}: #{e.message}")
      fetch_records_with_raw_sql(table_name, column_name) { |records| yield(records) unless records.empty? }
    end

    def fetch_records_with_raw_sql(table_name, column_name)
      offset = 0

      loop do
        base_query = <<~SQL
          SELECT id, #{column_name}
          FROM #{table_name}
          WHERE #{column_name} IS NOT NULL
        SQL

        base_query += " AND organization_id = #{organization_id}" if column_exists?(table_name, 'organization_id')

        base_query += " LIMIT #{batch_size} OFFSET #{offset}"

        batch_records = DataPrivacyLayer.configuration.adapter.connection.exec_query(base_query).to_a
        break if batch_records.empty?

        yield(batch_records)
        offset += batch_size
        break if batch_records.size < batch_size
      end
    end

    def table_exists?(table_name)
      DataPrivacyLayer.configuration.adapter.connection.table_exists?(table_name)
    end

    def column_exists?(table_name, column_name)
      table_exists?(table_name) &&
        DataPrivacyLayer.configuration.adapter.connection.column_exists?(table_name, column_name)
    end

    def validate_configuration_constraints
      errors = DataPrivacyLayer::Configuration.pdpl_config.flat_map do |model_name, model_config|
        ConstraintDetector.validate_model_configuration(model_name, model_config)
      end

      raise ConfigurationError, "Configuration validation failed:\n#{errors.join("\n")}" if errors.any?
    end

    def validate_column_strategy(table_name, column_name, strategy)
      return if ConstraintDetector.strategy_compatible_with_constraints?(table_name, column_name, strategy)

      unless ConstraintDetector.column_has_not_null_constraint?(table_name, column_name)
        raise ConstraintError, "Strategy '#{strategy}' is not compatible with #{table_name}.#{column_name}"
      end

      suggested = ConstraintDetector.suggest_strategy_for_column(table_name, column_name)
      raise NotNullConstraintError.new(
        model_name: table_name,
        column_name: column_name,
        strategy: strategy,
        suggested_strategy: suggested
      )
    end

    def process_column_with_validation(model_name, table_name, column_name)
      strategy_name = DataPrivacyLayer::Configuration.strategy_for_column(model_name, column_name)
      validate_column_strategy(table_name, column_name, strategy_name)
      process_column(model_name, table_name, column_name)
    end

    def cleanup_versions_for(model_name, record_ids)
      PaperTrail::Version.where(item_type: model_name, item_id: record_ids).delete_all
    end

    def delete_versions?
      !dry_run && DataPrivacyLayer.configuration.delete_paper_trail_versions
    end
  end
end
