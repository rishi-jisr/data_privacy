# frozen_string_literal: true

require 'data_privacy_layer/version'
require_relative 'data_privacy_layer/abstract'
require_relative 'data_privacy_layer/configuration'
require_relative 'data_privacy_layer/errors'
require_relative 'data_privacy_layer/adapters/base_adapter'
require_relative 'data_privacy_layer/adapters/rails_adapter'
require_relative 'data_privacy_layer/json_schema'
require_relative 'data_privacy_layer/constraint_detector'
require_relative 'data_privacy_layer/strategies/base_strategy'
require_relative 'data_privacy_layer/strategies/delete_strategy'
require_relative 'data_privacy_layer/strategies/hash_strategy'
require_relative 'data_privacy_layer/strategies/mask_strategy'
require_relative 'data_privacy_layer/strategies/json_strategy'
require_relative 'data_privacy_layer/base'
require_relative 'data_privacy_layer/processor'
# Note: audit_log is now in app/models/data_privacy/

module DataPrivacyLayer
  class << self
    def configure
      yield(configuration)
    end

    def configuration
      @configuration ||= Configuration.new
    end

    def reset_configuration!
      @configuration = nil
    end
  end
end
