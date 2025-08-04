# frozen_string_literal: true

module DataPrivacyLayer
  module Adapters
    class RailsAdapter < BaseAdapter
      def connection
        ApplicationRecord.connection
      end

      def logger
        Rails.logger
      end

      def table_exists?(table_name)
        ApplicationRecord.connection.table_exists?(table_name)
      end

      def model_exists?(model_name)
        model_class = Object.const_get(model_name)
        model_class.is_a?(Class) && model_class < ApplicationRecord
      rescue NameError
        false
      end

      def get_table_name(model_name)
        model_class = Object.const_get(model_name)
        if model_class.respond_to?(:table_name)
          model_class.table_name
        else
          model_name.underscore.pluralize
        end
      rescue NameError => e
        logger.error("[PDPL] Error getting table name for #{model_name}: #{e.message}")
        model_name.underscore.pluralize
      end

      def organization_id_column?(table_name)
        connection.columns(table_name).any? { |column| column.name == 'organization_id' }
      rescue StandardError => e
        logger.error("[PDPL] Error checking organization_id column for #{table_name}: #{e.message}")
        false
      end
    end
  end
end
