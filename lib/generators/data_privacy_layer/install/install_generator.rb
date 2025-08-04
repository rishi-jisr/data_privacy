# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/migration'

module DataPrivacyLayer
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path('../../templates', __FILE__)
      desc 'Generates migration for DataPrivacyLayer audit logs'

      def copy_migration
        migration_template 'create_data_privacy_audit_logs.rb', 'db/migrate/create_data_privacy_audit_logs.rb'
      end

      # Always return a timestamp-based filename
      def self.next_migration_number(_dirname)
        Time.now.utc.strftime('%Y%m%d%H%M%S')
      end
    end
  end
end
