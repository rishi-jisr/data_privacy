# frozen_string_literal: true

module DataPrivacyLayer
  module Abstract
    def abstract_methods(*method_names)
      method_names.each do |name|
        define_method(name) do |*_args, **_options|
          raise(NotImplementedError, "You must implement #{name}.")
        end
      end
    end
  end
end
