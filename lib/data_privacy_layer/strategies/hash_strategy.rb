# frozen_string_literal: true

module DataPrivacyLayer
  module Strategies
    class HashStrategy < BaseStrategy
      def anonymize_value(original_value)
        return nil if original_value.blank?

        # Create a deterministic hash with prefix to indicate it's hashed
        "HASH_#{generate_deterministic_hash(original_value.to_s.strip)}"
      end
    end
  end
end
