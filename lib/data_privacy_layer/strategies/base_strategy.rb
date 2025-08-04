# frozen_string_literal: true

module DataPrivacyLayer
  module Strategies
    class BaseStrategy
      extend DataPrivacyLayer::Abstract
      abstract_methods :anonymize_value

      attr_reader :column_name, :table_name

      def initialize(table_name:, column_name:)
        @table_name = table_name
        @column_name = column_name
      end

      def process_records(records, dry_run: false)
        return [] if records.empty?

        processed_records = []

        records.each do |record|
          original_value = record[column_name]
          next if original_value.nil?

          anonymized_value = anonymize_value(original_value)

          if dry_run
            processed_records << {
              id: record['id'],
              original: original_value,
              anonymized: anonymized_value,
              column: column_name
            }
          else
            update_record(record['id'], anonymized_value)
            processed_records << { id: record['id'], updated: true }
          end
        end

        processed_records
      end

      protected

      def update_record(record_id, new_value)
        query = "UPDATE #{table_name} SET #{column_name} = $1 WHERE id = $2"
        ApplicationRecord.connection.exec_query(query, 'PDPL Update', [new_value, record_id])
      end

      def generate_deterministic_hash(value)
        # Use a consistent salt for deterministic hashing
        salt = Rails.application.secret_key_base[0..31]
        Digest::SHA256.hexdigest("#{salt}#{value}")
      end
    end
  end
end
