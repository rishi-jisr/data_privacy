# frozen_string_literal: true

module DataPrivacyLayer
  # Base error class for all data privacy related errors
  class Error < StandardError; end

  # Raised when configuration is invalid
  class ConfigurationError < Error; end

  # Raised when a strategy is incompatible with database constraints
  class ConstraintError < Error; end

  # Raised when trying to use DELETE strategy on NOT NULL column
  class NotNullConstraintError < ConstraintError
    attr_reader :model_name, :column_name, :strategy, :suggested_strategy

    def initialize(model_name:, column_name:, strategy:, suggested_strategy: nil, message: nil)
      @model_name = model_name
      @column_name = column_name
      @strategy = strategy
      @suggested_strategy = suggested_strategy

      super(message || build_default_message)
    end

    private

    def build_default_message
      msg = "Cannot use '#{strategy}' strategy on #{model_name}.#{column_name}: Column has NOT NULL constraint."

      if suggested_strategy
        msg += " Suggested strategy: '#{suggested_strategy}'"
      end

      msg
    end
  end

  # Raised when model or table is not found
  class ModelNotFoundError < Error; end

  # Raised when trying to process data that doesn't exist
  class DataNotFoundError < Error; end
end
