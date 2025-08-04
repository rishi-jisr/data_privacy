# JSON Metadata Privacy Processing Guide

A comprehensive guide for handling complex JSON metadata fields with nested structures using the `json` strategy in the PDPL (Personal Data Protection Layer) system.

## Table of Contents

1. [Quick Start](#quick-start)
2. [Overview](#overview)
3. [Strategy Types](#strategy-types)
4. [Path Syntax Reference](#path-syntax-reference)
5. [Configuration Examples](#configuration-examples)
6. [Advanced Features](#advanced-features)
7. [Migration Guide](#migration-guide)
8. [Testing & Validation](#testing--validation)
9. [Performance Considerations](#performance-considerations)
10. [Troubleshooting](#troubleshooting)
11. [Best Practices](#best-practices)
12. [Security Considerations](#security-considerations)

---

## Quick Start

### Simple JSON Field Processing
```json
{
    "tables": {
        "YourTable": {
            "columns": {
                "metadata": {
                    "strategy": "json",
                    "json_config": {
                        "field_strategies": {
                            "employee_id": {"type": "hash"},
                            "personal_notes": {"type": "delete"},
                            "options.user_email": {"type": "mask"}
                        }
                    },
                    "reason": "PII - JSON metadata with personal information"
                }
            }
        }
    }
}
```

### Run Processing
```bash
# Test first (dry-run)
bundle exec rails runner "DataPrivacyLayer::Processor.new(dry_run: true, team: 'your_team').process_table('YourTable')"

# Execute actual processing
bundle exec rails runner "DataPrivacyLayer::Processor.new(dry_run: false, team: 'your_team').process_table('YourTable')"
```

---

## Overview

The `json` strategy enables **field-level privacy processing** within JSON metadata columns, supporting:

| **Feature** | **Description** | **Example** |
|-------------|-----------------|-------------|
| **Dot-Notation Paths** | Access nested fields cleanly | `"options.employee_id"` |
| **Array Index Access** | Target specific array elements | `"employees.0.email"` |
| **Mixed Data Types** | Handle objects, arrays, primitives | All JSON types supported |
| **Multiple Strategies** | Different strategies per field | Hash, mask, delete, keep |
| **Deep Nesting** | Unlimited nesting depth | `"a.b.c.d.e.field"` |
| **Error Resilience** | Graceful failure handling | Continues on errors |

### Why Use JSON Strategy?

✅ **Precision**: Target specific sensitive fields  
✅ **Flexibility**: Mix different strategies in one JSON  
✅ **Maintainability**: Clean, readable configurations  
✅ **Performance**: Process only what needs processing  
✅ **Safety**: Preserve business-critical data  

---

## Strategy Types

### 1. `hash` - Deterministic Anonymization
**Purpose**: Create consistent, irreversible identifiers

```json
"employee_id": {"type": "hash"}
```

| **Input** | **Output** | **Use Case** |
|-----------|------------|--------------|
| `"12345"` | `"HASH_a1b2c3d4e5f6..."` | User IDs, references |
| `["id1", "id2"]` | `["HASH_...", "HASH_..."]` | ID arrays |

**Benefits**: Consistent across records, suitable for analytics

### 2. `mask` - Partial Visibility
**Purpose**: Show partial data while hiding sensitive parts

```json
"email": {
    "type": "mask",
    "mask_config": {
        "pattern": "{first_2}***@{last_4}",
        "mask_char": "*"
    }
}
```

| **Input** | **Output** | **Pattern** |
|-----------|------------|-------------|
| `"john.doe@company.com"` | `"jo***m.com"` | `{first_2}***@{last_4}` |
| `"1234567890"` | `"12****7890"` | `{first_2}****{last_4}` |
| `"secret123"` | `"se***123"` | Default (first 2, last 2) |

**Available Patterns**:
- `{first_n}` - First n characters
- `{last_n}` - Last n characters  
- Custom patterns with fixed text

### 3. `delete` - Complete Removal
**Purpose**: Remove sensitive data completely

```json
"personal_notes": {"type": "delete"}
```

| **Input** | **Output** |
|-----------|------------|
| `"Confidential info"` | `null` |
| `["note1", "note2"]` | `null` |

**Use Case**: Comments, notes, temporary data

### 4. `keep` - Preserve Data
**Purpose**: Explicitly preserve business-critical data

```json
"workflow_id": {"type": "keep"}
```

| **Input** | **Output** |
|-----------|------------|
| `"wf_123"` | `"wf_123"` |
| `42` | `42` |

**Use Case**: System IDs, configuration values

### 5. `nested` - Legacy Support
**Purpose**: Handle nested objects (legacy - use dot-notation instead)

```json
"review_data": {
    "type": "nested",
    "nested_strategies": {
        "reviewer_id": {"type": "hash"},
        "comments": {"type": "delete"}
    }
}
```

⚠️ **Deprecated**: Use dot-notation paths for cleaner configuration

---

## Path Syntax Reference

### Basic Syntax

| **Path Type** | **Syntax** | **Description** | **Example** |
|---------------|------------|-----------------|-------------|
| **Root Field** | `field` | Top-level field | `"employee_id"` |
| **Nested Object** | `parent.child` | Object property | `"options.user_id"` |
| **Deep Nesting** | `a.b.c.d` | Multi-level nesting | `"data.user.profile.email"` |
| **Array Element** | `array.0` | Specific array index | `"employees.0"` |
| **Array Object** | `array.0.field` | Field in array object | `"employees.0.email"` |

### Advanced Paths

```json
// Complex nested structure paths
"metadata.request.payload.recipients.0.email": {"type": "mask"},
"audit.trail.2.user.credentials": {"type": "delete"},
"settings.permissions.admin.users": {"type": "hash"}
```

### Array Handling Strategies

#### Option 1: Index-Specific (Precise)
```json
"employee_list.0.id": {"type": "hash"},
"employee_list.1.id": {"type": "hash"},
"employee_list.2.id": {"type": "hash"}
```

#### Option 2: Entire Array (Simple)
```json
"employee_ids": {"type": "hash"}  // Processes all elements
```

#### Option 3: Mixed Approach
```json
"employees": {"type": "hash"},           // All employee objects
"employees.0.special_note": {"type": "delete"}  // First employee's note
```

---

## Configuration Examples

### Example 1: Simple Employee Data
```json
// Original JSON
{
    "employee_id": "emp_12345",
    "first_name": "John",
    "email": "john.doe@company.com",
    "department": "Engineering"
}
```

**Configuration:**
```json
"metadata": {
    "strategy": "json",
    "json_config": {
        "field_strategies": {
            "employee_id": {"type": "hash"},
            "first_name": {"type": "hash"},
            "email": {"type": "mask", "mask_config": {"pattern": "{first_2}***@{last_4}"}},
            "department": {"type": "keep"}
        }
    },
    "reason": "PII - Employee personal data with business context"
}
```

**Result:**
```json
{
    "employee_id": "HASH_a1b2c3d4...",
    "first_name": "HASH_x7y8z9w0...",
    "email": "jo***com",
    "department": "Engineering"
}
```

### Example 2: Automation Workflow Metadata
```json
// Original complex JSON
{
    "trigger": {
        "employee_id": "emp_456",
        "event_type": "onboarding"
    },
    "actions": [
        {
            "type": "send_email",
            "recipients": ["hr@company.com", "manager@company.com"],
            "template_id": "welcome_template"
        },
        {
            "type": "create_task",
            "assignee": "hr_specialist",
            "description": "Personal onboarding checklist"
        }
    ],
    "metadata": {
        "created_by": "admin_user",
        "personal_notes": "New hire from referral program"
    }
}
```

**Dot-Notation Configuration:**
```json
"metadata": {
    "strategy": "json",
    "json_config": {
        "field_strategies": {
            "trigger.employee_id": {"type": "hash"},
            "trigger.event_type": {"type": "keep"},
            "actions.0.recipients": {"type": "mask", "mask_config": {"pattern": "{first_2}***@{last_4}"}},
            "actions.0.template_id": {"type": "keep"},
            "actions.1.assignee": {"type": "hash"},
            "actions.1.description": {"type": "delete"},
            "metadata.created_by": {"type": "hash"},
            "metadata.personal_notes": {"type": "delete"}
        }
    },
    "reason": "PII - Automation workflow with employee and email data"
}
```

### Example 3: Performance Review Data
```json
// Original review data
{
    "review_cycle": "2024-Q1",
    "employee": {
        "id": "emp_789",
        "evaluations": [
            {
                "reviewer_id": "mgr_123",
                "scores": {"technical": 4.5, "communication": 4.0},
                "comments": "Excellent technical skills, needs improvement in presentations"
            },
            {
                "reviewer_id": "peer_456", 
                "scores": {"collaboration": 5.0, "reliability": 4.8},
                "comments": "Great team player, always reliable"
            }
        ]
    },
    "final_rating": 4.3,
    "promotion_eligible": true
}
```

**Configuration:**
```json
"metadata": {
    "strategy": "json",
    "json_config": {
        "field_strategies": {
            "review_cycle": {"type": "keep"},
            "employee.id": {"type": "hash"},
            "employee.evaluations.0.reviewer_id": {"type": "hash"},
            "employee.evaluations.0.scores": {"type": "keep"},
            "employee.evaluations.0.comments": {"type": "delete"},
            "employee.evaluations.1.reviewer_id": {"type": "hash"},
            "employee.evaluations.1.scores": {"type": "keep"},
            "employee.evaluations.1.comments": {"type": "delete"},
            "final_rating": {"type": "keep"},
            "promotion_eligible": {"type": "keep"}
        }
    },
    "reason": "PII - Performance review with personal comments"
}
```

---

## Advanced Features

### Dynamic Array Processing

For arrays with unknown length, combine strategies:

```json
// Process entire arrays
"all_employee_ids": {"type": "hash"},

// Plus specific sensitive elements
"employees.0.personal_email": {"type": "delete"},
"employees.1.personal_email": {"type": "delete"}
```

### Conditional Processing

Use `keep` strategically to preserve business logic:

```json
"user.role": {"type": "keep"},           // Business requirement
"user.permissions": {"type": "keep"},    // System functionality  
"user.personal_email": {"type": "mask"}, // Privacy requirement
"user.work_email": {"type": "keep"}      // Business requirement
```

### Mixed Strategies Example

```json
"field_strategies": {
    // Direct field processing
    "top_level_employee_id": {"type": "hash"},
    
    // Nested object processing  
    "config.user.id": {"type": "hash"},
    "config.user.preferences": {"type": "keep"},
    
    // Array processing
    "recipients": {"type": "mask"},
    "recipients.0.personal_note": {"type": "delete"},
    
    // Deep nesting
    "audit.history.3.user.credentials": {"type": "delete"}
}
```

---

## Migration Guide

### From Ruby Migration Code

**Before (Ruby code):**
```ruby
def mapping_metadata(row, association_mapping)
  metadata = row['metadata']
  return metadata if metadata.blank?

  metadata = JSON.parse(metadata)
  
  # Complex conditional processing
  metadata.each do |key, value|
    metadata[key] = case key
    when 'employee_id', 'employee_ids'
      value.map { |id| association_mapping['employee_id'][id.to_s].to_i }
    when 'email_recipients'
      value.map { |email| mask_email(email) }
    when 'personal_notes'
      nil  # Delete sensitive data
    when 'options'
      process_nested_options(value, association_mapping)
    else
      value
    end
  end
  
  metadata.to_json
end
```

**After (JSON configuration):**
```json
"metadata": {
    "strategy": "json",
    "json_config": {
        "field_strategies": {
            "employee_id": {"type": "hash"},
            "employee_ids": {"type": "hash"},
            "email_recipients": {"type": "mask", "mask_config": {"pattern": "{first_2}***@{last_4}"}},
            "personal_notes": {"type": "delete"},
            "options.employee_id": {"type": "hash"},
            "options.request_id": {"type": "hash"}
        }
    },
    "reason": "PII - Employee references and communication data"
}
```

### Migration Benefits

| **Aspect** | **Ruby Code** | **JSON Configuration** |
|------------|---------------|------------------------|
| **Maintainability** | Complex logic | Declarative rules |
| **Testing** | Unit tests required | Configuration validation |
| **Team Updates** | Code changes | Config file updates |
| **Auditability** | Code review | Clear field mapping |
| **Performance** | Custom processing | Optimized engine |

---

## Testing & Validation

### Configuration Validation

```bash
# Validate JSON syntax and schema
bundle exec rails runner "
config = JSON.parse(File.read('lib/data_privacy_layer/team_configs/your_team.json'))
errors = DataPrivacyLayer::JsonSchema.validate(config)
puts errors.empty? ? 'Configuration valid!' : errors.join('\n')
"
```

### Dry-Run Testing

```bash
# Test specific table
bundle exec rails runner "
processor = DataPrivacyLayer::Processor.new(dry_run: true, team: 'your_team')
results = processor.process_table('YourTable')
puts 'Dry-run completed: ' + results.length.to_s + ' records processed'
"

# Test all tables
bundle exec rails runner "
DataPrivacyLayer::Processor.new(dry_run: true, team: 'your_team').process_all
"
```

### Sample Data Testing

Create test data to validate your configuration:

```ruby
# test_json_processing.rb
test_data = {
  "employee_id" => "emp_123",
  "options" => {
    "email" => "test@company.com",
    "personal_note" => "Sensitive information"
  }
}.to_json

strategy = DataPrivacyLayer::Strategies::JsonStrategy.new(
  table_name: "test_table",
  column_name: "metadata",
  json_config: your_config
)

result = strategy.anonymize_value(test_data)
puts JSON.pretty_generate(JSON.parse(result))
```

---

## Performance Considerations

### Optimization Strategies

| **Factor** | **Impact** | **Optimization** |
|------------|------------|------------------|
| **JSON Size** | High | Limit processed fields |
| **Nesting Depth** | Medium | Use dot-notation efficiently |
| **Array Length** | High | Process specific indexes |
| **Field Count** | Medium | Group related strategies |

### Performance Tips

1. **Limit Processing Scope**
   ```json
   // Instead of processing everything
   "large_data_object": {"type": "hash"}
   
   // Process only sensitive fields
   "large_data_object.personal_info.email": {"type": "mask"}
   ```

2. **Batch Processing**
   ```bash
   # Process in smaller batches
   bundle exec rails runner "
   DataPrivacyLayer::Processor.new(dry_run: false, team: 'your_team', batch_size: 100).process_table('LargeTable')
   "
   ```

3. **Array Optimization**
   ```json
   // For large arrays, target specific elements
   "employees.0.sensitive_field": {"type": "delete"},
   "employees.1.sensitive_field": {"type": "delete"}
   
   // Rather than processing entire array
   "employees": {"type": "hash"}
   ```

### Memory Management

- **Large JSONs**: Consider chunked processing
- **Deep Nesting**: Monitor memory usage during processing
- **Array Processing**: Use index-specific paths for large arrays

---

## Troubleshooting

### Common Issues

#### 1. Path Not Found
**Error**: Field path doesn't exist in JSON
```
Current value not found for path: options.non_existent_field
```

**Solution**: Verify path exists in your data
```json
// Check actual JSON structure first
{
    "options": {
        "employee_id": "123",  // ✓ options.employee_id exists
        "user_id": "456"       // ✓ options.user_id exists
    }
}
```

#### 2. Array Index Out of Bounds
**Error**: Array index doesn't exist
```
Array index 5 not found in array of length 3
```

**Solution**: Use conditional paths or process entire array
```json
// Instead of fixed indexes
"employees.5.email": {"type": "mask"}

// Use entire array processing
"employees": {"type": "hash"}
```

#### 3. JSON Parse Errors
**Error**: Malformed JSON in metadata field

**Solution**: System automatically falls back to hash strategy
```json
// Malformed JSON → entire field gets hashed
"invalid_json_string" → "HASH_a1b2c3d4e5f6..."
```

#### 4. Strategy Type Errors
**Error**: Unknown strategy type

**Solution**: Use valid strategy types
```json
// Invalid
"field": {"type": "encrypt"}  // ❌

// Valid  
"field": {"type": "hash"}     // ✅
"field": {"type": "mask"}     // ✅
"field": {"type": "delete"}   // ✅
"field": {"type": "keep"}     // ✅
```

### Debugging Commands

```bash
# Check configuration loading
bundle exec rails runner "puts DataPrivacyLayer::Configuration.pdpl_config.inspect"

# Test specific strategy
bundle exec rails runner "
strategy = DataPrivacyLayer::Configuration.strategy_for_column('YourTable', 'metadata')
puts 'Strategy: ' + strategy.to_s
"

# Validate team configuration
bundle exec rails runner "
config = DataPrivacyLayer::Configuration.load_config['your_team']
puts JSON.pretty_generate(config)
"
```

---

## Best Practices

### 1. Configuration Design

✅ **DO:**
```json
// Use descriptive field paths
"user.personal.email": {"type": "mask"},
"employee.contact.phone": {"type": "delete"},

// Group related strategies
"audit.user_id": {"type": "hash"},
"audit.action": {"type": "keep"},
"audit.timestamp": {"type": "keep"}
```

❌ **DON'T:**
```json
// Overly complex nesting
"data": {
    "type": "nested",
    "nested_strategies": {
        "user": {
            "type": "nested",
            "nested_strategies": {
                "email": {"type": "mask"}
            }
        }
    }
}
```

### 2. Strategy Selection

| **Data Type** | **Recommended Strategy** | **Reasoning** |
|---------------|-------------------------|---------------|
| **User IDs** | `hash` | Consistent identification |
| **Emails** | `mask` | Recognition + privacy |
| **Phone Numbers** | `mask` or `delete` | Contact preference |
| **Personal Notes** | `delete` | Complete privacy |
| **System IDs** | `keep` | Business functionality |
| **Timestamps** | `keep` | Audit requirements |

### 3. Team Collaboration

```json
{
    "team": "your_team",
    "description": "Clear description of data ownership",
    "tables": {
        "TableName": {
            "description": "What this table contains",
            "columns": {
                "metadata": {
                    "strategy": "json",
                    "json_config": {
                        "field_strategies": {
                            // Document each field's purpose
                            "employee_id": {
                                "type": "hash",
                                "reason": "User identification for analytics"
                            }
                        }
                    },
                    "reason": "Comprehensive explanation"
                }
            }
        }
    }
}
```

### 4. Change Management

1. **Version Control**: Track configuration changes
2. **Testing**: Always test with dry-run first
3. **Documentation**: Update reasons when changing strategies
4. **Communication**: Notify team of configuration changes
5. **Rollback**: Keep backup configurations

### 5. Security Guidelines

- **Principle of Least Privilege**: Only process what's necessary
- **Data Retention**: Delete data that's not needed
- **Audit Trail**: Document all strategy decisions
- **Regular Review**: Quarterly configuration reviews

---

## Security Considerations

### Data Classification

| **Sensitivity Level** | **Recommended Strategy** | **Examples** |
|----------------------|-------------------------|--------------|
| **High** | `delete` or `hash` | SSN, personal notes, credentials |
| **Medium** | `mask` or `hash` | Emails, phone numbers, names |
| **Low** | `keep` or `mask` | Department, role, timestamps |
| **Public** | `keep` | System IDs, configuration values |

### Compliance Requirements

#### GDPR Compliance
```json
// Right to be forgotten
"personal_data": {"type": "delete"},

// Pseudonymization
"user_identifiers": {"type": "hash"},

// Data minimization
"unnecessary_fields": {"type": "delete"}
```

#### Industry Standards
```json
// PCI DSS - Payment data
"payment.card_number": {"type": "delete"},
"payment.cvv": {"type": "delete"},

// HIPAA - Health data  
"medical.records": {"type": "delete"},
"patient.notes": {"type": "delete"}
```

### Risk Assessment

| **Risk Level** | **Strategy** | **Action** |
|----------------|--------------|------------|
| **Critical** | Immediate deletion | `{"type": "delete"}` |
| **High** | Strong anonymization | `{"type": "hash"}` |
| **Medium** | Partial masking | `{"type": "mask"}` |
| **Low** | Preserve with monitoring | `{"type": "keep"}` |

---

## Quick Reference

### Strategy Summary
```json
{
    "hash": "Deterministic anonymization",
    "mask": "Partial visibility with patterns",
    "delete": "Complete removal (null)",
    "keep": "Preserve unchanged",
    "nested": "Legacy nested processing"
}
```

### Path Examples
```json
{
    "simple": "field_name",
    "nested": "parent.child",
    "array": "list.0",
    "complex": "data.users.0.profile.email"
}
```

### Common Patterns
```json
{
    "employee_id": {"type": "hash"},
    "email": {"type": "mask", "mask_config": {"pattern": "{first_2}***@{last_4}"}},
    "personal_notes": {"type": "delete"},
    "system_id": {"type": "keep"}
}
```

---

**Last Updated**: January 2025  
**Version**: 2.0.0  
**Maintained By**: Data Privacy Team  
**Review Cycle**: Quarterly

For questions or support, contact: data-privacy-team@company.com 