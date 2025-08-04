# PDPL - Personal Data Protection Layer

> A comprehensive data privacy system for handling sensitive information in JSON metadata and database columns with field-level precision and configurable anonymization strategies.

## 🚀 Quick Start

```bash
# 1. Configure your team's data privacy rules
vim lib/data_privacy_layer/team_configs/your_team.json

# 2. Test your configuration (dry-run)
bundle exec rails runner "DataPrivacyLayer::Processor.new(dry_run: true, team: 'your_team').process_all"

# 3. Execute privacy processing
bundle exec rails runner "DataPrivacyLayer::Processor.new(dry_run: false, team: 'your_team').process_all"
```

## 📋 Table of Contents

- [Features](#features)
- [Strategy Types](#strategy-types)
- [Configuration Examples](#configuration-examples)
- [JSON Metadata Processing](#json-metadata-processing)
- [Team Management](#team-management)
- [Usage](#usage)
- [Testing](#testing)
- [Documentation](#documentation)
- [Contributing](#contributing)

## ✨ Features

| Feature | Description | Example |
|---------|-------------|---------|
| **📁 Team-Based Configuration** | Isolated privacy rules per team | `attendance.json`, `finance.json` |
| **🎯 Field-Level Precision** | Target specific JSON fields | `"options.employee_id": {"type": "hash"}` |
| **🔧 Multiple Strategies** | Hash, mask, delete, keep | Mix strategies within same JSON |
| **📊 Dot-Notation Paths** | Clean nested field access | `"user.profile.email": {"type": "mask"}` |
| **🏗️ Array Support** | Index-specific processing | `"employees.0.email": {"type": "mask"}` |
| **🛡️ Error Resilience** | Graceful failure handling | Continues processing on errors |
| **📈 Performance Optimized** | Batch processing support | Configurable batch sizes |
| **🔍 Dry-Run Testing** | Safe configuration testing | No data changes during testing |

## 🎛️ Strategy Types

### Core Strategies

```json
{
    "hash": "Deterministic anonymization - HASH_a1b2c3d4e5f6...",
    "mask": "Partial visibility - jo***@company.com", 
    "delete": "Complete removal - null",
    "keep": "Preserve unchanged - original_value"
}
```

### Strategy Selection Guide

| Data Type | Strategy | Reasoning |
|-----------|----------|-----------|
| **User IDs** | `hash` | Consistent identification for analytics |
| **Email Addresses** | `mask` | Recognition while preserving privacy |
| **Phone Numbers** | `mask` or `delete` | Contact verification or complete removal |
| **Personal Notes** | `delete` | Complete privacy protection |
| **System IDs** | `keep` | Business functionality preservation |
| **Timestamps** | `keep` | Audit and compliance requirements |

## 🔧 Configuration Examples

### Simple Column Processing
```json
{
    "tables": {
        "Employee": {
            "columns": {
                "email": {
                    "strategy": "mask",
                    "mask_config": {
                        "pattern": "{first_2}***@{last_4}"
                    },
                    "reason": "PII - Email addresses (masked for recognition)"
                },
                "personal_notes": {
                    "strategy": "delete",
                    "reason": "PII - Personal comments (not needed for business)"
                }
            }
        }
    }
}
```

### JSON Metadata Processing
```json
{
    "tables": {
        "Automation": {
            "columns": {
                "metadata": {
                    "strategy": "json",
                    "json_config": {
                        "field_strategies": {
                            "employee_id": {"type": "hash"},
                            "options.user_email": {"type": "mask"},
                            "payload.recipients": {"type": "hash"},
                            "personal_notes": {"type": "delete"},
                            "workflow_id": {"type": "keep"}
                        }
                    },
                    "reason": "PII - JSON metadata with mixed personal and business data"
                }
            }
        }
    }
}
```

## 📦 JSON Metadata Processing

### Dot-Notation Path Syntax

| Path Type | Syntax | Example | Description |
|-----------|--------|---------|-------------|
| **Root Field** | `field` | `"employee_id"` | Top-level field |
| **Nested Object** | `parent.child` | `"options.user_id"` | Object property |
| **Array Element** | `array.0` | `"employees.0"` | Specific array index |
| **Deep Nesting** | `a.b.c.d` | `"data.user.profile.email"` | Multi-level nesting |

### Before/After Examples

#### Original JSON
```json
{
    "employee_id": "emp_12345",
    "options": {
        "user_email": "john.doe@company.com",
        "personal_note": "Confidential feedback"
    },
    "recipients": ["hr@company.com", "manager@company.com"]
}
```

#### After Processing
```json
{
    "employee_id": "HASH_a1b2c3d4e5f6...",
    "options": {
        "user_email": "jo***m.com",
        "personal_note": null
    },
    "recipients": ["HASH_x7y8z9w0...", "HASH_m3n4o5p6..."]
}
```

## 👥 Team Management

### Team Configuration Structure
```
lib/data_privacy_layer/team_configs/
├── common.json           # Shared/common data
├── attendance.json       # Time tracking team
├── finance.json          # Finance team  
├── payroll.json          # Payroll team
├── recruiting.json       # Recruiting team
└── your_team.json        # Your team's config
```

### Team Configuration Template
```json
{
    "team": "your_team_name",
    "description": "What data this team manages",
    "table_level_actions": {
        "OldDataTable": {
            "reason": "PDPL - Delete old records for organization cleanup"
        }
    },
    "tables": {
        "YourTable": {
            "description": "What this table contains",
            "columns": {
                "sensitive_field": {
                    "strategy": "hash",
                    "reason": "PII - Why this strategy is needed"
                }
            }
        }
    }
}
```

## 🎯 Usage

### Command Line Interface

```bash
# Process all tables for a team
bundle exec rails runner "DataPrivacyLayer::Processor.new(dry_run: false, team: 'finance').process_all"

# Process specific table
bundle exec rails runner "DataPrivacyLayer::Processor.new(dry_run: false, team: 'hr').process_table('Employee')"

# Dry-run testing (no changes)
bundle exec rails runner "DataPrivacyLayer::Processor.new(dry_run: true, team: 'payroll').process_all"

# Custom batch size for large datasets
bundle exec rails runner "DataPrivacyLayer::Processor.new(dry_run: false, team: 'analytics', batch_size: 500).process_table('LargeTable')"
```

### Programmatic Usage

```ruby
# Initialize processor
processor = DataPrivacyLayer::Processor.new(
  dry_run: true,
  team: 'your_team',
  organization_id: 123,
  batch_size: 100
)

# Process specific table
results = processor.process_table('Employee')

# Process all configured tables
processor.process_all

# Check configuration
config = DataPrivacyLayer::Configuration.pdpl_config
strategy = DataPrivacyLayer::Configuration.strategy_for_column('Employee', 'email')
```

## 🧪 Testing

### Configuration Validation
```bash
# Validate JSON syntax and schema
bundle exec rails runner "
config = JSON.parse(File.read('lib/data_privacy_layer/team_configs/your_team.json'))
errors = DataPrivacyLayer::JsonSchema.validate(config)
puts errors.empty? ? '✅ Configuration valid!' : '❌ Errors: ' + errors.join(', ')
"
```

### Dry-Run Testing
```bash
# Test without making changes
bundle exec rails runner "
processor = DataPrivacyLayer::Processor.new(dry_run: true, team: 'your_team')
results = processor.process_table('YourTable')
puts 'Processed: ' + results.length.to_s + ' records'
"
```

### Sample Data Testing
```ruby
# Test JSON strategy with sample data
test_data = {
  "employee_id" => "emp_123",
  "options" => {"email" => "test@company.com"}
}.to_json

strategy = DataPrivacyLayer::Strategies::JsonStrategy.new(
  table_name: "test_table",
  column_name: "metadata",
  json_config: {"field_strategies" => {"employee_id" => {"type" => "hash"}}}
)

result = strategy.anonymize_value(test_data)
puts JSON.pretty_generate(JSON.parse(result))
```

## 📚 Documentation

### Core Documentation
- **[JSON Metadata Guide](JSON_METADATA_GUIDE.md)** - Comprehensive guide for JSON field processing
- **[Team Configs README](team_configs/README.md)** - Team configuration structure and examples

### Quick References

#### Available Strategies
```ruby
DataPrivacyLayer::Configuration::STRATEGIES
# => {delete: "delete", hash: "hash", mask: "mask", json: "json"}
```

#### Mask Patterns
```json
{
    "{first_n}": "First n characters",
    "{last_n}": "Last n characters", 
    "custom": "Fixed text with placeholders"
}
```

#### Common Configurations
```json
{
    "email": {"strategy": "mask", "mask_config": {"pattern": "{first_2}***@{last_4}"}},
    "user_id": {"strategy": "hash"},
    "personal_notes": {"strategy": "delete"},
    "system_config": {"strategy": "keep"}
}
```

## 🔒 Security & Compliance

### Data Classification Matrix

| Sensitivity | Strategy | Examples |
|-------------|----------|----------|
| **🔴 Critical** | `delete` | SSN, credentials, personal notes |
| **🟡 High** | `hash` | User IDs, employee numbers |
| **🟠 Medium** | `mask` | Emails, phone numbers |
| **🟢 Low** | `keep` | Department, role, timestamps |

### Compliance Support

```json
{
    "GDPR": {
        "right_to_be_forgotten": "delete strategy",
        "pseudonymization": "hash strategy", 
        "data_minimization": "targeted field processing"
    },
    "PCI_DSS": {
        "payment_data": "delete strategy",
        "cardholder_data": "complete removal"
    }
}
```

## 🛠️ Development

### Adding New Strategies

1. Create strategy class in `strategies/`
2. Extend `BaseStrategy`
3. Implement `anonymize_value` method
4. Register in `Configuration::STRATEGIES`
5. Update JSON schema validation

### Configuration Schema

```ruby
# Validate configuration
DataPrivacyLayer::JsonSchema.validate(config_hash)

# Check strategy compatibility
DataPrivacyLayer::ConstraintDetector.validate_model_configuration(model, config)
```

## 🚨 Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| **Path not found** | Verify JSON structure matches configuration paths |
| **Array index out of bounds** | Use array.length or process entire array |
| **JSON parse errors** | System falls back to hash strategy automatically |
| **Unknown strategy type** | Use valid types: hash, mask, delete, keep, json |

### Debug Commands
```bash
# Check loaded configuration
bundle exec rails runner "puts DataPrivacyLayer::Configuration.pdpl_config.inspect"

# Test specific strategy
bundle exec rails runner "puts DataPrivacyLayer::Configuration.strategy_for_column('Employee', 'email')"

# Validate team config
bundle exec rails runner "puts JSON.pretty_generate(DataPrivacyLayer::Configuration.load_config['your_team'])"
```

## 📋 Best Practices

### ✅ DO
- Use dot-notation for nested JSON fields
- Start with dry-run testing
- Document reasons for each strategy choice
- Regular quarterly configuration reviews
- Version control configuration changes

### ❌ DON'T
- Process unnecessary data (principle of least privilege)
- Use complex nested configurations when dot-notation works
- Skip dry-run testing before production
- Leave sensitive data without explicit strategy
- Make configuration changes without team notification

## 🤝 Contributing

### Configuration Updates
1. Edit team configuration file
2. Validate with dry-run
3. Test with sample data
4. Update documentation if needed
5. Notify team of changes

### Code Contributions
1. Follow existing patterns
2. Add comprehensive tests
3. Update documentation
4. Consider backward compatibility
5. Follow security best practices

## 📞 Support

- **Technical Questions**: Data Privacy Team
- **Configuration Help**: See [JSON Metadata Guide](JSON_METADATA_GUIDE.md)
- **Security Concerns**: Security Team
- **Business Questions**: Product Team

---

**Version**: 2.0.0  
**Last Updated**: January 2025  
**Maintained By**: Data Privacy Team  
**License**: Internal Use

## 🔗 Quick Links

- [📖 Detailed JSON Guide](JSON_METADATA_GUIDE.md) - Complete documentation
- [⚙️ Team Configs](team_configs/) - Configuration examples
- [🧪 Testing Guide](JSON_METADATA_GUIDE.md#testing--validation) - Testing procedures
- [🚀 Performance Tips](JSON_METADATA_GUIDE.md#performance-considerations) - Optimization guide
- [🔧 Troubleshooting](JSON_METADATA_GUIDE.md#troubleshooting) - Common issues & solutions 