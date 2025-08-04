# frozen_string_literal: true

require_relative 'lib/data_privacy_layer/version'

Gem::Specification.new do |spec|
  spec.name          = 'data_privacy_layer'
  spec.version       = DataPrivacyLayer::VERSION
  spec.authors       = ['Your Team Name']
  spec.email         = ['your-email@company.com']

  spec.summary       = 'A library for PDPL-compliant data anonymization.'
  spec.description   = 'Handles hashing, deletion, and masking strategies for personal data.'
  spec.license       = 'Proprietary'

  spec.files         = Dir['lib/**/*']
  spec.require_paths = ['lib']

  spec.add_runtime_dependency 'rails', '>= 6.0'
  spec.metadata['rubygems_mfa_required'] = 'true'
end
