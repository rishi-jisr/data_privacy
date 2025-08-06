# frozen_string_literal: true

module DataPrivacyLayer
  module Strategies
    class JsonStrategy < BaseStrategy
      def initialize(table_name:, column_name:, json_config: {})
        super(table_name: table_name, column_name: column_name)
        @json_config = json_config.with_indifferent_access
      end

      def anonymize_value(original_value)
        return nil if original_value.blank?

        begin
          json_data = original_value
          return original_value if json_data.blank?

          anonymized_data = process_json_fields(json_data, @json_config['field_strategies'] || {})
          anonymized_data.to_json
        rescue JSON::ParserError => e
          Rails.logger.error("Failed to parse JSON for #{table_name}.#{column_name}: #{e.message}")
          # Fallback to hash strategy for malformed JSON
          "HASH_#{generate_deterministic_hash(original_value)}"
        end
      end

      private

      def process_json_fields(data, field_strategies)
        # Process dot-notation paths first
        process_dot_notation_paths(data, field_strategies)

        # Then process regular nested structures
        case data
        when Hash
          data.each do |key, value|
            strategy = field_strategies[key]
            if strategy
              data[key] = apply_field_strategy(value, strategy)
            elsif value.is_a?(Hash) || value.is_a?(Array)
              # Recursively process nested structures
              data[key] = process_json_fields(value, field_strategies)
            end
          end
        when Array
          data.map! { |item| process_json_fields(item, field_strategies) }
        end

        data
      end

      def process_dot_notation_paths(data, field_strategies)
        return unless data.is_a?(Hash)

        # Find all dot-notation paths in strategies
        dot_paths = field_strategies.keys.select { |key| key.include?('.') }

        dot_paths.each do |path|
          strategy = field_strategies[path]
          current_value = get_nested_value(data, path)

          if current_value != :not_found
            new_value = apply_field_strategy(current_value, strategy)
            set_nested_value(data, path, new_value)
          end
        end
      end

      def get_nested_value(data, path)
        path_parts = path.split('.')
        current = data

        path_parts.each do |part|
          if current.is_a?(Hash) && current.key?(part)
            current = current[part]
          elsif current.is_a?(Array) && part.match?(/^\d+$/)
            index = part.to_i
            return :not_found if index >= current.length

            current = current[index]
          else
            return :not_found
          end
        end

        current
      end

      def set_nested_value(data, path, value)
        path_parts = path.split('.')
        current = data

        # Navigate to the parent of the target
        path_parts[0..-2].each do |part|
          if current.is_a?(Hash)
            current[part] ||= {}
            current = current[part]
          elsif current.is_a?(Array) && part.match?(/^\d+$/)
            index = part.to_i
            current = current[index] if index < current.length
          end
        end

        # Set the final value
        last_part = path_parts.last
        if current.is_a?(Hash)
          current[last_part] = value
        elsif current.is_a?(Array) && last_part.match?(/^\d+$/)
          index = last_part.to_i
          current[index] = value if index < current.length
        end
      end

      def apply_field_strategy(value, strategy)
        case strategy['type']
        when 'delete'
          nil
        when 'hash'
          return nil if value.blank?

          if value.is_a?(Array)
            value.map { |v| "HASH_#{generate_deterministic_hash(v.to_s)}" }
          else
            "HASH_#{generate_deterministic_hash(value.to_s)}"
          end
        when 'mask'
          return nil if value.blank?

          mask_config = strategy['mask_config'] || {}
          if value.is_a?(Array)
            value.map { |v| mask_value(v.to_s, mask_config) }
          else
            mask_value(value.to_s, mask_config)
          end
        when 'nested'
          # Handle nested objects with their own strategies
          return nil if value.blank?

          nested_strategies = strategy['nested_strategies'] || {}
          process_json_fields(value, nested_strategies)
        when 'keep'
          value
        else
          # Default: hash for unknown strategies
          return nil if value.blank?

          "HASH_#{generate_deterministic_hash(value.to_s)}"
        end
      end

      def mask_value(value, mask_config)
        pattern = mask_config['pattern']
        mask_char = mask_config['mask_char'] || '*'

        if pattern.present?
          apply_custom_pattern(value, pattern, mask_char)
        else
          simple_mask(value, mask_char)
        end
      end

      def apply_custom_pattern(value, pattern, _mask_char)
        result = pattern.dup

        result.gsub!(/\{last_(\d+)\}/) do
          n = ::Regexp.last_match(1).to_i
          value.length >= n ? value[-n..] : value
        end

        result.gsub!(/\{first_(\d+)\}/) do
          n = ::Regexp.last_match(1).to_i
          value.length >= n ? value[0, n] : value
        end

        result
      end

      def simple_mask(value, mask_char)
        return value if value.length <= 4

        first_chars = value[0, 2]
        last_chars = value[-2, 2]
        middle_length = value.length - 4
        "#{first_chars}#{mask_char * middle_length}#{last_chars}"
      end
    end
  end
end
