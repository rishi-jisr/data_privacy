# frozen_string_literal: true

module DataPrivacyLayer
  class Processor < Base
    def initialize(organization_id:, dry_run: false, batch_size: 10_000)
      super
    end

    def process
      # Always validate configuration constraints before processing
      validate_configuration_constraints

      results = {
        column_processing: {},
        table_processing: {}
      }

      # Process column anonymization
      results[:column_processing] = process_column_anonymization

      # Process table-level deletions
      results[:table_processing] = process_table_deletions

      results
    end

    private

    def process_column_anonymization
      results = {}

      DataPrivacyLayer::Configuration.tables_to_process.each do |model_name|
        table_name = model_name_to_table_name(model_name)
        next unless table_name && table_exists?(table_name)

        table_results = process_table_columns(model_name, table_name)
        results[model_name] = table_results unless table_results.empty?
      end

      results
    end

    def process_table_deletions
      results = {}
      table_actions = DataPrivacyLayer::Configuration.all_table_level_actions

      if table_actions.empty?
        return { message: 'No table-level actions configured' }
      end

      table_actions.each do |model_name, action_config|
        table_name = model_name_to_table_name(model_name)
        next unless table_name && table_exists?(table_name)
        next unless DataPrivacyLayer.configuration.adapter.organization_id_column?(table_name)

        table_results = process_table_deletion(model_name, table_name, action_config)
        results[model_name] = table_results
      end

      results
    end

    def process_table_columns(model_name, table_name)
      table_results = {}
      columns = DataPrivacyLayer::Configuration.columns_for_table(model_name)

      columns.each do |column_name|
        next unless column_exists?(table_name, column_name)

        column_results = process_column(model_name, table_name, column_name)
        table_results[column_name] = column_results
      end

      table_results
    end

    def process_table_deletion(_model_name, table_name, action_config)
      reason = action_config['reason']
      team = action_config['team']

      if dry_run
        # In dry-run mode, just count records that would be deleted
        count = count_records_for_deletion(table_name)

        return {
          action: 'delete_organization_records',
          would_delete: count,
          reason: reason,
          team: team,
          dry_run: true
        }
      end

      # Execute the actual deletion
      deleted_count = delete_organization_records(table_name)

      # Log the action
      audit_log(
        action: 'delete_organization_records',
        table_name: table_name,
        column_name: nil, # Table-level action, no specific column
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

    def count_records_for_deletion(table_name)
      query = "SELECT COUNT(*) as count FROM #{table_name} WHERE organization_id = $1"
      result = DataPrivacyLayer.configuration.adapter.connection.exec_query(query, 'PDPL Count', [organization_id])
      result.first['count']
    end

    def delete_organization_records(table_name)
      # Use parameterized query for security
      query = "DELETE FROM #{table_name} WHERE organization_id = $1"
      DataPrivacyLayer.configuration.adapter.connection.exec_delete(query, 'PDPL Delete', [organization_id])

      # exec_delete returns the number of affected rows
    end

    def model_name_to_table_name(model_name)
      # Convert model name to table name using Rails conventions

      model_class = model_name.constantize
      model_class.table_name
    rescue NameError => e
      DataPrivacyLayer.configuration.logger.warn("[PDPL] Model #{model_name} not found: #{e.message}")
      nil
    rescue StandardError => e
      DataPrivacyLayer.configuration.logger.warn("[PDPL] Error getting table name for #{model_name}: #{e.message}")
      nil
    end

    def process_column(model_name, table_name, column_name)
      strategy_name = DataPrivacyLayer::Configuration.strategy_for_column(model_name, column_name)
      strategy = create_strategy(strategy_name, table_name, column_name, model_name)

      total_processed = 0
      batch_results = []
      sample_details = []
      batch_count = 0

      # Process records in batches for better memory management
      process_records_in_batches(table_name, column_name) do |batch_records|
        batch_count += 1
        DataPrivacyLayer.configuration.logger.info("Processing #{table_name}.#{column_name} batch #{batch_count}: #{batch_records.length} records (#{dry_run ? 'DRY RUN' : 'LIVE'})")

        result = strategy.process_records(batch_records, dry_run: dry_run)
        batch_results.concat(result)
        total_processed += result.length

        # Collect sample details for dry run (first batch only)
        if dry_run && sample_details.empty?
          sample_details = result.first(5)
        end
      end

      if total_processed.zero?
        return { processed: 0, message: 'No records to process' }
      end

      # Log the action with total counts
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
        details: dry_run ? sample_details : nil # Show sample in dry run
      }
    end

    def create_strategy(strategy_name, table_name, column_name, model_name = nil)
      # Get column configuration for additional parameters
      # Use model_name if provided, otherwise fall back to table_name for backward compatibility
      config_key = model_name || table_name
      column_config = DataPrivacyLayer::Configuration.pdpl_config.dig(config_key, 'columns', column_name) || {}

      case strategy_name
      when :delete
        Strategies::DeleteStrategy.new(table_name: table_name, column_name: column_name)
      when :hash
        Strategies::HashStrategy.new(table_name: table_name, column_name: column_name)
      when :mask
        mask_config = column_config['mask_config'] || {}
        Strategies::MaskStrategy.new(table_name: table_name, column_name: column_name, mask_config: mask_config)
      when :json
        json_config = column_config['json_config'] || {}
        Strategies::JsonStrategy.new(table_name: table_name, column_name: column_name, json_config: json_config)
      else
        raise(ArgumentError, "Unknown strategy: #{strategy_name}")
      end
    end

    def process_records_in_batches(table_name, column_name)
      # Try to get the model class for ActiveRecord batching
      model_class = table_name.classify.constantize

      # Build the scope for records that need processing
      scope = model_class.select(:id, column_name).
                where("#{column_name} IS NOT NULL")

      # Add organization filter if the table has organization_id
      if column_exists?(table_name, 'organization_id')
        scope = scope.where(organization_id: organization_id)
      end

      # Process in batches using find_in_batches for memory efficiency
      scope.find_in_batches(batch_size: batch_size) do |batch|
        # Convert to hash format expected by strategies
        batch_records = batch.map do |record|
          {
            'id' => record.id,
            column_name => record.send(column_name)
          }
        end

        yield(batch_records) unless batch_records.empty?
      end
    rescue NameError => e
      DataPrivacyLayer.configuration.logger.warn("Could not find model class for table #{table_name}: #{e.message}. Falling back to raw SQL.")
      # Fallback to raw SQL if model class doesn't exist
      fetch_records_with_raw_sql(table_name, column_name) do |batch_records|
        yield(batch_records) unless batch_records.empty?
      end
    end

    # Fallback method for tables without corresponding model classes
    def fetch_records_with_raw_sql(table_name, column_name)
      offset = 0

      loop do
        # Base query - only fetch records that need processing
        base_query = "SELECT id, #{column_name} FROM #{table_name} WHERE #{column_name} IS NOT NULL"

        # Add organization filter if the table has organization_id
        if column_exists?(table_name, 'organization_id')
          base_query += " AND organization_id = #{organization_id}"
        end

        # Add pagination
        base_query += " LIMIT #{batch_size} OFFSET #{offset}"

        batch_records = DataPrivacyLayer.configuration.adapter.connection.exec_query(base_query).to_a

        break if batch_records.empty?

        yield(batch_records)
        offset += batch_size

        # Safety break to prevent infinite loops
        break if batch_records.length < batch_size
      end
    end

    def table_exists?(table_name)
      DataPrivacyLayer.configuration.adapter.connection.table_exists?(table_name)
    end

    def column_exists?(table_name, column_name)
      return false unless table_exists?(table_name)

      DataPrivacyLayer.configuration.adapter.connection.column_exists?(table_name, column_name)
    end

    # Validate that all configured strategies are compatible with database constraints
    def validate_configuration_constraints
      errors = []

      DataPrivacyLayer::Configuration.pdpl_config.each do |model_name, model_config|
        model_errors = ConstraintDetector.validate_model_configuration(model_name, model_config)
        errors.concat(model_errors)
      end

      unless errors.empty?
        raise(ConfigurationError, "Configuration validation failed:\n#{errors.join("\n")}")
      end
    end

    # Validate a specific column strategy against database constraints
    def validate_column_strategy(table_name, column_name, strategy)
      unless ConstraintDetector.strategy_compatible_with_constraints?(table_name, column_name, strategy)
        if ConstraintDetector.column_has_not_null_constraint?(table_name, column_name)
          suggested_strategy = ConstraintDetector.suggest_strategy_for_column(table_name, column_name)

          raise(NotNullConstraintError.new(
                  model_name: table_name,
                  column_name: column_name,
                  strategy: strategy,
                  suggested_strategy: suggested_strategy
                ))
        else
          raise(ConstraintError, "Strategy '#{strategy}' is not compatible with #{table_name}.#{column_name}")
        end
      end
    end

    # Enhanced process_column method with constraint validation
    def process_column_with_validation(model_name, table_name, column_name)
      strategy_name = DataPrivacyLayer::Configuration.strategy_for_column(model_name, column_name)

      # Validate strategy compatibility before processing
      validate_column_strategy(table_name, column_name, strategy_name)

      # Proceed with normal processing
      process_column(model_name, table_name, column_name)
    end

    def delete_versions_for(model_class, record_ids)
      PaperTrail::Version.where(item_type: model_class.name, item_id: record_ids).delete_all
    end
  end
end
