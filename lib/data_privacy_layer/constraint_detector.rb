# frozen_string_literal: true

module DataPrivacyLayer
  class ConstraintDetector
    # Cache for database constraint information to avoid repeated queries
    @constraint_cache = {}
    @cache_mutex = Mutex.new

    # Prohibited columns that cannot be configured for PDPL processing
    PROHIBITED_COLUMNS = %w[id].freeze

    class << self
      # Check if column has NOT NULL constraint
      def not_null_constraint?(table_name, column_name)
        # Handle dot-notation paths for JSON fields
        if json_path?(column_name)
          return handle_json_path_constraint(table_name, column_name, :not_null)
        end

        column_info = get_cached_column_info(table_name, column_name)
        return false unless column_info

        # column.null returns true if NULL allowed, false if NOT NULL
        !column_info.null
      end

      # Alias method for backward compatibility with processor
      def column_has_not_null_constraint?(table_name, column_name)
        not_null_constraint?(table_name, column_name)
      end

      # Check if column has UNIQUE constraint
      def unique_constraint?(table_name, column_name)
        # Handle dot-notation paths for JSON fields
        if json_path?(column_name)
          return handle_json_path_constraint(table_name, column_name, :unique)
        end

        # Check if column is primary key (primary keys are inherently unique)
        if primary_key?(table_name, column_name)
          return true
        end

        # Get all indexes for the table (cached)
        indexes = get_cached_indexes(table_name)

        # Check if any unique index includes this column
        indexes.any? do |index|
          index.unique && index.columns.include?(column_name.to_s)
        end
      end

      # Check if strategy is compatible with column constraints
      def strategy_compatible_with_constraints?(table_name, column_name, strategy)
        # DELETE strategy not allowed on NOT NULL columns
        return false if strategy.to_s == 'delete' && not_null_constraint?(table_name, column_name)

        # UNIQUE columns can only use HASH strategy
        return false if unique_constraint?(table_name, column_name) && strategy.to_s != 'hash'

        true
      end

      # Suggest appropriate strategy for a column based on constraints
      def suggest_strategy_for_column(table_name, column_name)
        # Handle JSON path fields
        if json_path?(column_name)
          # JSON paths are more flexible - suggest based on data sensitivity
          return 'hash' # Conservative default for JSON fields
        end

        # If column is UNIQUE, only HASH is allowed
        return 'hash' if unique_constraint?(table_name, column_name)

        # If column is NOT NULL, avoid DELETE
        return 'hash' if not_null_constraint?(table_name, column_name)

        # For nullable, non-unique columns, any strategy works
        'hash' # Default to hash as it's safest
      end

      # Validate strategy against constraints
      def validate_strategy(model_name, column_name, strategy)
        table_name = model_name_to_table_name(model_name)

        # Check NOT NULL constraint - reject DELETE strategy
        if strategy.to_s == 'delete' && not_null_constraint?(table_name, column_name)
          return {
            valid: false,
            error: "Cannot use DELETE strategy on NOT NULL column #{model_name}.#{column_name}",
            suggested_strategy: 'hash'
          }
        end

        # Check UNIQUE constraint - only allow HASH strategy
        if unique_constraint?(table_name, column_name) && strategy.to_s != 'hash'
          return {
            valid: false,
            error: "UNIQUE column #{model_name}.#{column_name} can only use HASH strategy",
            suggested_strategy: 'hash'
          }
        end

        {
          valid: true,
          table_name: table_name
        }
      end

      # Validate entire model configuration
      def validate_model_configuration(model_name, configuration)
        errors = []

        model_name_to_table_name(model_name)
        columns_config = configuration['columns'] || {}

        columns_config.each do |column_name, column_config|
          # Check for prohibited columns first (case-insensitive)
          if PROHIBITED_COLUMNS.include?(column_name.to_s.downcase)
            errors << "Column '#{model_name}.#{column_name}' is prohibited - '#{column_name}' columns cannot be configured for PDPL processing. ID columns are system-managed primary keys that must remain unchanged."
            next
          end

          strategy = column_config['strategy']

          validation = validate_strategy(model_name, column_name, strategy)
          next if validation[:valid]

          error_msg = validation[:error]
          if validation[:suggested_strategy]
            error_msg += ". Suggested: #{validation[:suggested_strategy]}"
          end
          errors << error_msg
        end

        errors
      end

      # Get constraint information for a column
      def get_column_constraints(table_name, column_name)
        {
          not_null: not_null_constraint?(table_name, column_name),
          unique: unique_constraint?(table_name, column_name),
          allowed_strategies: get_allowed_strategies(table_name, column_name)
        }
      end

      # Get allowed strategies for a column (including JSON paths)
      def get_allowed_strategies(table_name, column_name)
        # Handle JSON path fields
        if json_path?(column_name)
          # JSON paths have more flexibility since they don't have DB constraints
          return %w[hash mask delete keep]
        end

        strategies = %w[hash mask] # These are generally safe

        # Only allow DELETE if column allows NULL
        unless not_null_constraint?(table_name, column_name)
          strategies << 'delete'
        end

        # If column is UNIQUE, only allow HASH
        if unique_constraint?(table_name, column_name)
          strategies = ['hash']
        end

        strategies
      end

      # Convert model name to table name (public method)
      def model_name_to_table_name(model_name)
        model_class = model_name.constantize
        model_class.table_name
      rescue NameError
        # Fallback to Rails convention
        model_name.underscore.pluralize
      rescue StandardError => e
        DataPrivacyLayer.configuration.logger.error("[PDPL] Error getting table name for #{model_name}: #{e.message}")
        nil
      end

      # Clear constraint cache (useful for testing or schema changes)
      def clear_constraint_cache!
        @cache_mutex.synchronize do
          @constraint_cache.clear
        end
        DataPrivacyLayer.configuration.logger.info('[PDPL] Constraint cache cleared')
      end

      # Check if column name contains dot-notation (for JSON paths)
      def json_path?(column_name)
        column_name.to_s.include?('.')
      end

      # Extract base column name from dot-notation path
      def extract_base_column(column_path)
        column_path.to_s.split('.').first
      end

      # Extract JSON path from dot-notation
      def extract_json_path(column_path)
        parts = column_path.to_s.split('.')
        return nil if parts.length <= 1

        parts[1..].join('.')
      end

      # Check if column is a primary key
      def primary_key?(table_name, column_name)
        # Get primary key columns for the table
        primary_keys = get_cached_primary_keys(table_name)
        primary_keys.include?(column_name.to_s)
      end

      private

      # Get cached column information
      def get_cached_column_info(table_name, column_name)
        cache_key = "columns:#{table_name}"

        @cache_mutex.synchronize do
          @constraint_cache[cache_key] ||= DataPrivacyLayer.configuration.adapter.connection.columns(table_name)
        end

        @constraint_cache[cache_key].find { |col| col.name == column_name.to_s }
      end

      # Get cached index information
      def get_cached_indexes(table_name)
        cache_key = "indexes:#{table_name}"

        @cache_mutex.synchronize do
          @constraint_cache[cache_key] ||= DataPrivacyLayer.configuration.adapter.connection.indexes(table_name)
        end

        @constraint_cache[cache_key]
      end

      # Get cached primary key information
      def get_cached_primary_keys(table_name)
        cache_key = "primary_keys:#{table_name}"

        @cache_mutex.synchronize do
          @constraint_cache[cache_key] ||= DataPrivacyLayer.configuration.adapter.connection.primary_keys(table_name)
        end

        @constraint_cache[cache_key]
      end

      # Handle constraints for JSON path fields (dot-notation)
      def handle_json_path_constraint(_table_name, column_path, constraint_type)
        extract_base_column(column_path)
        extract_json_path(column_path)

        # For JSON paths, we check constraints on the base column
        # JSON nested fields don't have individual constraints
        case constraint_type
        when :not_null
          # JSON paths can be null even if the base column isn't
          # The base column constraint doesn't apply to nested paths
        when :unique
          # JSON paths cannot have unique constraints at the database level
          # Uniqueness would need to be enforced at the application level
        end
        false
      end
    end
  end
end
