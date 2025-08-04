# frozen_string_literal: true

module DataPrivacyLayer
  module Adapters
    class BaseAdapter
      def connection
        raise(NotImplementedError, 'Subclasses must implement #connection')
      end

      def logger
        raise(NotImplementedError, 'Subclasses must implement #logger')
      end

      def table_exists?(table_name)
        raise(NotImplementedError, 'Subclasses must implement #table_exists?')
      end

      def model_exists?(model_name)
        raise(NotImplementedError, 'Subclasses must implement #model_exists?')
      end

      def get_table_name(model_name)
        raise(NotImplementedError, 'Subclasses must implement #get_table_name')
      end

      def organization_id_column?(table_name)
        raise(NotImplementedError, 'Subclasses must implement #organization_id_column?')
      end
    end
  end
end
