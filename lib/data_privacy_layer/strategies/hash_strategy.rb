# frozen_string_literal: true

module DataPrivacyLayer
  module Strategies
    class HashStrategy < BaseStrategy
      def anonymize_value(original_value)
        return nil if original_value.blank?

        # Create a deterministic hash with prefix to indicate it's hashed
        "UUID5_#{generate_deterministic_uuid(original_value)}"
      end
    end
  end
end
