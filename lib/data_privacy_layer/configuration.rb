# frozen_string_literal: true

require 'data_privacy_layer/errors'

module DataPrivacyLayer
  class Configuration
    attr_accessor :adapter_type, :config_path, :logger, :delete_paper_trail_versions

    def initialize
      @adapter_type = :rails # Default for current setup
      @config_path = Rails.root.join('lib/data_privacy_layer/team_configs')
      @logger = Rails.logger
      @delete_paper_trail_versions = false
    end

    def adapter
      @adapter ||= case adapter_type
                   when :rails
                     Adapters::RailsAdapter.new
                   else
                     raise(ConfigurationError, "Unknown adapter type: #{adapter_type}")
                   end
    end
    # Define anonymization strategies (simplified to 3 core strategies)
    STRATEGIES = {
      delete: 'delete', # Delete the data completely (set to NULL)
      hash: 'hash',              # Replace with SHA256 hash
      mask: 'mask',              # Partial masking/redaction
      json: 'json'               # JSON field-specific processing
    }.freeze

    # Table-level actions: Simple organization-based deletion
    # All table-level actions delete records where organization_id = ?
    # Only requires 'reason' attribute in configuration

    # Path to team configuration directory (dynamic method)
    def self.team_configs_path
      Rails.root.join('lib/data_privacy_layer/team_configs')
    end

    class << self
      # Load configuration from team config files
      def load_config
        @load_config ||= begin
          team_configs = {}

          Dir.glob(File.join(team_configs_path, '*.json')).each do |file_path|
            next if File.basename(file_path) == 'README.md'

            begin
              team_config = JSON.parse(File.read(file_path))
              team_name = team_config['team']

              if team_name
                team_configs[team_name] = team_config
              end
            rescue JSON::ParserError => e
              Rails.logger.error("Invalid JSON in team config file #{file_path}: #{e.message}")
              next
            end
          end

          if team_configs.empty?
            raise(ConfigurationError, "No valid team configuration files found in #{team_configs_path}")
          end

          team_configs
        end
      end

      # Reload configuration (useful for testing or after config changes)
      def reload_config!
        @config = nil
        @pdpl_config = nil
        @load_config = nil
        load_config
      end

      # Get the models configuration (merged from all teams)
      def pdpl_config
        @pdpl_config ||= begin
          merged_models = {}

          load_config.each_value do |team_config|
            if team_config['tables']
              merged_models.merge!(team_config['tables'])
            end
          end

          merged_models
        end
      end

      def tables_to_process
        pdpl_config.keys
      end

      def columns_for_table(model_name)
        model_config = pdpl_config[model_name]
        return [] unless model_config

        model_config['columns']&.keys || []
      end

      def strategy_for_column(model_name, column_name)
        column_config = pdpl_config.dig(model_name, 'columns', column_name)
        return nil unless column_config

        column_config['strategy']&.to_sym
      end

      def reason_for_column(model_name, column_name)
        column_config = pdpl_config.dig(model_name, 'columns', column_name)
        return nil unless column_config

        column_config['reason']
      end

      def description_for_table(model_name)
        model_config = pdpl_config[model_name]
        return nil unless model_config

        model_config['description']
      end

      def valid_strategy?(strategy)
        STRATEGIES.key?(strategy.to_sym)
      end

      # Enhanced validation methods with constraint checking
      def validate_config!
        config = load_config
        errors = []

        # Validate each team configuration
        config.each do |team_name, team_config|
          # Check required team-level keys
          required_keys = %w[team tables]
          required_keys.each do |key|
            errors << "Team '#{team_name}' missing required key: #{key}" unless team_config.key?(key)
          end

          # Validate tables structure
          if team_config['tables'].is_a?(Hash)
            team_config['tables'].each do |table_name, table_config|
              errors.concat(validate_table_config(table_name, table_config))

              # Add constraint validation using ConstraintDetector
              constraint_errors = ConstraintDetector.validate_model_configuration(table_name, table_config)
              errors.concat(constraint_errors)
            end
          else
            errors << "Team '#{team_name}' tables must be a hash/object"
          end
        end

        unless errors.empty?
          raise(ConfigurationError, "Configuration validation failed:\n#{errors.join("\n")}")
        end

        true
      end

      # Validate strategy for a specific column against database constraints
      def validate_strategy_for_column(model_name, column_name, strategy)
        # If no strategy provided, check if column is configured
        if strategy.nil?
          configured_strategy = strategy_for_column(model_name, column_name)
          return nil unless configured_strategy

          strategy_name = configured_strategy
        else
          # Strategy is provided, validate it regardless of configuration
          strategy_name = strategy
        end

        table_name = ConstraintDetector.model_name_to_table_name(model_name)
        return nil unless table_name

        ConstraintDetector.strategy_compatible_with_constraints?(table_name, column_name, strategy_name)
      end

      # Suggest appropriate strategies for all columns in a model
      def suggest_strategies_for_model(model_name)
        table_name = ConstraintDetector.model_name_to_table_name(model_name)
        return {} unless table_name

        # Check if table exists
        return {} unless ApplicationRecord.connection.table_exists?(table_name)

        suggestions = {}

        # Get all columns for the table
        columns = ApplicationRecord.connection.columns(table_name)
        columns.each do |column|
          suggested_strategy = ConstraintDetector.suggest_strategy_for_column(table_name, column.name)
          suggestions[column.name] = suggested_strategy.to_sym
        end

        suggestions
      end

      # Analyze columns that are not configured but might need privacy processing
      def analyze_unconfigured_columns(model_name)
        table_name = ConstraintDetector.model_name_to_table_name(model_name)
        return [] unless table_name

        # Check if table exists
        return [] unless ApplicationRecord.connection.table_exists?(table_name)

        # Get configured columns
        configured_columns = columns_for_table(model_name)

        # Get all columns from database
        all_columns = ApplicationRecord.connection.columns(table_name).map(&:name)

        # Find unconfigured columns (excluding common system columns)
        system_columns = %w[id created_at updated_at organization_id]
        all_columns - configured_columns - system_columns
      end

      def config_summary
        config = load_config
        {
          total_teams: config.keys.count,
          total_tables: pdpl_config.keys.count,
          total_columns: pdpl_config.values.sum { |table| table['columns']&.keys&.count || 0 },
          strategies_used: pdpl_config.values.flat_map do |table|
            table['columns']&.values&.pluck('strategy') || []
          end.uniq.compact,
          teams: config.keys,
          tables: pdpl_config.keys
        }
      end

      # Get table-level actions for a specific team
      def table_level_actions_for_team(team_name)
        team_config = load_config[team_name]
        return {} unless team_config

        team_config['table_level_actions'] || {}
      end

      # Get all table-level actions (merged from all teams)
      def all_table_level_actions
        actions = {}

        load_config.each do |team_name, team_config|
          next unless team_config['table_level_actions']

          team_config['table_level_actions'].each do |table_name, action_config|
            actions[table_name] = action_config.merge('team' => team_name)
          end
        end

        actions
      end

      # Helper method to add new configuration (for future use)
      def add_table_configuration(team_name, table_name, table_config)
        # This method can be used to dynamically add configurations
        # Implementation would involve reading, modifying, and writing the team JSON file
        raise(NotImplementedError, "Dynamic configuration updates not yet implemented. Please edit team config files in #{team_configs_path} directly.")
      end

      # Export current config for backup/sharing
      def export_config
        load_config.to_json
      end

      private

      def validate_table_config(table_name, table_config)
        errors = []

        unless table_config.is_a?(Hash)
          errors << "Table '#{table_name}' configuration must be a hash/object"
          return errors
        end

        # Check columns structure
        unless table_config['columns'].is_a?(Hash)
          errors << "Table '#{table_name}' must have 'columns' as a hash/object"
          return errors
        end

        # Validate each column
        table_config['columns'].each do |column_name, column_config|
          errors.concat(validate_column_config(table_name, column_name, column_config))
        end

        errors
      end

      def validate_column_config(table_name, column_name, column_config)
        errors = []

        unless column_config.is_a?(Hash)
          errors << "Column '#{table_name}.#{column_name}' configuration must be a hash/object"
          return errors
        end

        # Check required fields
        if column_config['strategy'].blank?
          errors << "Column '#{table_name}.#{column_name}' missing required 'strategy'"
        end

        if column_config['reason'].blank?
          errors << "Column '#{table_name}.#{column_name}' missing required 'reason'"
        end

        # Validate strategy
        if column_config['strategy'].present? && !valid_strategy?(column_config['strategy'])
          valid_strategies = STRATEGIES.keys.join(', ')
          errors << "Column '#{table_name}.#{column_name}' has invalid strategy '#{column_config['strategy']}'. Valid strategies: #{valid_strategies}"
        end

        errors
      end
    end
  end
end
