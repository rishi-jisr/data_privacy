# frozen_string_literal: true

module DataPrivacyLayer
  # JSON Schema for validating PDPL configuration
  class JsonSchema
    SCHEMA = {
      type: 'object',
      required: %w[team tables],
      properties: {
        team: {
          type: 'string',
          minLength: 1,
          description: 'Team name (e.g., attendance, finance, payroll)'
        },
        description: {
          type: 'string',
          description: 'Description of what this team manages'
        },
        table_level_actions: {
          type: 'object',
          description: 'Organization-based table deletion actions (using Rails model names)',
          patternProperties: {
            '^[a-zA-Z_][a-zA-Z0-9_]*$' => {
              type: 'object',
              required: %w[reason],
              properties: {
                reason: {
                  type: 'string',
                  minLength: 10,
                  description: 'Why this table needs organization-level deletion'
                }
              },
              additionalProperties: false
            }
          },
          additionalProperties: false
        },
        tables: {
          type: 'object',
          description: 'Model configurations (using Rails model names)',
          patternProperties: {
            '^[a-zA-Z_][a-zA-Z0-9_]*$' => {
              type: 'object',
              required: %w[columns],
              properties: {
                description: {
                  type: 'string',
                  description: 'Description of what this table contains'
                },
                columns: {
                  type: 'object',
                  description: 'Column configurations',
                  patternProperties: {
                    '^[a-zA-Z_][a-zA-Z0-9_]*$' => {
                      type: 'object',
                      required: %w[strategy reason],
                      properties: {
                        strategy: {
                          type: 'string',
                          enum: %w[delete hash mask json],
                          description: 'Anonymization strategy to use'
                        },
                        reason: {
                          type: 'string',
                          minLength: 10,
                          description: 'Explanation of why this strategy is chosen'
                        },
                        mask_config: {
                          type: 'object',
                          description: 'Masking configuration for mask strategy'
                        },
                        json_config: {
                          type: 'object',
                          description: 'JSON field processing configuration for json strategy'
                        }
                      },
                      additionalProperties: false
                    }
                  },
                  additionalProperties: false
                }
              },
              additionalProperties: false
            }
          },
          additionalProperties: false
        },
        metadata: {
          type: 'object',
          description: 'Optional metadata about the team configuration',
          properties: {
            total_tables: { type: 'integer', minimum: 0 },
            total_columns: { type: 'integer', minimum: 0 },
            strategies_used: {
              type: 'array',
              items: { type: 'string', enum: %w[delete hash mask] }
            },
            notes: {
              type: 'array',
              items: { type: 'string' }
            }
          },
          additionalProperties: true
        }
      },
      additionalProperties: false
    }.freeze

    class << self
      # Validate JSON configuration against schema
      def validate(config_hash)
        errors = []
        validate_object(config_hash, SCHEMA, 'root', errors)
        errors
      end

      # Validate and return boolean
      def valid?(config_hash)
        validate(config_hash).empty?
      end

      # Get schema as JSON string
      def schema_json
        JSON.pretty_generate(SCHEMA)
      end

      private

      def validate_object(obj, schema, path, errors)
        return errors unless schema[:type] == 'object'

        # Check required properties
        schema[:required]&.each do |required_prop|
          unless obj.is_a?(Hash) && obj.key?(required_prop)
            errors << "Missing required property '#{required_prop}' at #{path}"
          end
        end

        return errors unless obj.is_a?(Hash)

        # Check properties
        schema[:properties]&.each do |prop_name, prop_schema|
          if obj.key?(prop_name)
            validate_value(obj[prop_name], prop_schema, "#{path}.#{prop_name}", errors)
          end
        end

        # Check pattern properties
        if schema[:patternProperties]
          obj.each do |key, value|
            next unless key.is_a?(String)

            schema[:patternProperties].each do |pattern, pattern_schema|
              if key.match?(Regexp.new(pattern))
                validate_value(value, pattern_schema, "#{path}.#{key}", errors)
                break
              end
            end
          end
        end

        # Check for additional properties
        if schema[:additionalProperties] == false
          allowed_props = (schema[:properties]&.keys || []) +
                          (schema[:patternProperties]&.keys || [])

          obj.each_key do |key|
            next if allowed_props.any? do |prop|
              prop.is_a?(String) ? prop == key : key.match?(Regexp.new(prop))
            end

            errors << "Additional property '#{key}' not allowed at #{path}"
          end
        end

        errors
      end

      def validate_value(value, schema, path, errors)
        # Type validation
        if schema[:type]
          case schema[:type]
          when 'string'
            unless value.is_a?(String)
              errors << "Expected string at #{path}, got #{value.class}"
              return
            end

            # String validations
            if schema[:minLength] && value.length < schema[:minLength]
              errors << "String too short at #{path} (minimum: #{schema[:minLength]})"
            end

            if schema[:pattern] && !value.match?(Regexp.new(schema[:pattern]))
              errors << "String doesn't match pattern at #{path}"
            end

            if schema[:enum]&.exclude?(value)
              errors << "Invalid value '#{value}' at #{path}. Allowed: #{schema[:enum].join(', ')}"
            end

          when 'integer'
            unless value.is_a?(Integer)
              errors << "Expected integer at #{path}, got #{value.class}"
              return
            end

            if schema[:minimum] && value < schema[:minimum]
              errors << "Integer too small at #{path} (minimum: #{schema[:minimum]})"
            end

          when 'array'
            unless value.is_a?(Array)
              errors << "Expected array at #{path}, got #{value.class}"
              return
            end

            # Validate array items
            if schema[:items]
              value.each_with_index do |item, index|
                validate_value(item, schema[:items], "#{path}[#{index}]", errors)
              end
            end

          when 'object'
            unless value.is_a?(Hash)
              errors << "Expected object at #{path}, got #{value.class}"
              return
            end

            validate_object(value, schema, path, errors)
          end
        end
      end
    end
  end
end
