# frozen_string_literal: true

module DataPrivacyLayer
  module Strategies
    class DeleteStrategy < BaseStrategy
      def anonymize_value(_original_value)
        nil
      end

      protected

      def update_record(record_id, _new_value)
        query = "UPDATE #{table_name} SET #{column_name} = NULL WHERE id = $1"
        ApplicationRecord.connection.exec_query(query, 'PDPL Delete', [record_id])
      end
    end
  end
end
