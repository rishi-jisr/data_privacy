# frozen_string_literal: true

module DataPrivacyLayer
  module Strategies
    class MaskStrategy < BaseStrategy
      def initialize(table_name:, column_name:, mask_config: {})
        super(table_name: table_name, column_name: column_name)
        @mask_config = mask_config.with_indifferent_access
      end

      def anonymize_value(original_value)
        return nil if original_value.blank?

        # Get masking configuration from user input
        pattern = @mask_config['pattern']
        mask_char = @mask_config['mask_char'] || '*'

        if pattern.present?
          # Use custom pattern provided by user
          apply_custom_pattern(original_value, pattern, mask_char)
        else
          # Simple default: show first 2 and last 2 characters, mask the middle
          simple_mask(original_value, mask_char)
        end
      end

      private

      def apply_custom_pattern(value, pattern, _mask_char)
        # Support patterns like "***-***-{last_4}" or "{first_2}***{last_2}"
        result = pattern.dup

        # Replace {last_n} placeholders
        result.gsub!(/\{last_(\d+)\}/) do
          n = ::Regexp.last_match(1).to_i
          value.length >= n ? value[-n..] : value
        end

        # Replace {first_n} placeholders
        result.gsub!(/\{first_(\d+)\}/) do
          n = ::Regexp.last_match(1).to_i
          value.length >= n ? value[0, n] : value
        end

        result
      end

      def simple_mask(value, mask_char)
        return value if value.length <= 4

        # Show first 2 and last 2 characters, mask the middle
        first_chars = value[0, 2]
        last_chars = value[-2, 2]
        middle_length = value.length - 4
        "#{first_chars}#{mask_char * middle_length}#{last_chars}"
      end
    end
  end
end
