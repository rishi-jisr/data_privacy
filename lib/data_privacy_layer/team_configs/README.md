# PDPL Team Configuration Structure

## 📂 Overview

This folder contains **team-specific PDPL configuration files** that allow each team to manage their own data privacy settings without interfering with other teams' configurations.

## 🎯 Benefits of Team-Based Structure

### **✅ Clear Ownership**
- Each team owns their configuration file
- Easy to identify who is responsible for which data
- Clear contact points for questions and updates

### **✅ Isolated Changes**
- Teams can update their configurations independently
- No risk of accidentally affecting other teams' settings
- Smaller, focused configuration files are easier to manage

### **✅ Better Collaboration** 
- Teams understand exactly what data they need to protect
- Easier code reviews with team-specific files
- Faster decision-making within team boundaries

### **✅ Scalable Organization**
- Easy to add new teams as the company grows
- Simple to reorganize if team structures change
- Clear separation of concerns

## 📋 Available Team Configurations

| File | Team | Description | Contact |
|------|------|-------------|---------|
| `attendance.json` | Attendance Team | Time tracking and attendance data | attendance-team@company.com |
| `people_data.json` | People/HR Team | Employee personal information | hr-team@company.com |
| `finance.json` | Finance Team | Financial data and accounting | finance-team@company.com |
| `payroll.json` | Payroll Team | Salary and compensation data | payroll-team@company.com |
| `recruiting.json` | Recruiting Team | Candidate and recruitment data | recruiting-team@company.com |
| `customer_data.json` | Customer Team | Customer information and interactions | customer-team@company.com |

## 🛡️ Available Strategies

The system supports **3 core anonymization strategies** plus **table-level actions**:

### **Column-Level Strategies**

#### **1. Delete Strategy**
- **Purpose**: Completely remove data that's not needed
- **Use case**: Personal notes, comments, optional fields
- **Example**: `personal_notes: null`

#### **2. Hash Strategy** 
- **Purpose**: Create unique identifiers while hiding original data
- **Use case**: Names, IDs, references that need consistency
- **Example**: `john.doe@email.com` → `a1b2c3d4e5f6...`

#### **3. Mask Strategy**
- **Purpose**: Show partial data while hiding sensitive parts
- **Use case**: Emails, phone numbers, account numbers for recognition
- **Example**: `john.doe@company.com` → `jo***om` (first 2 + last 2 characters)
- **Simple**: Shows first 2 and last 2 characters, masks the middle with ***

### **Table-Level Actions**

#### **4. Organization-Based Table Deletion**
- **Purpose**: Remove all records from a table for a specific organization
- **Use case**: Organization cleanup, cancelled customers, data purging
- **Example**: Delete all records from `old_invoices` table where `organization_id = 123`
- **Simple**: Only requires a reason - organization_id is passed automatically

## 📝 Configuration File Format

Each team configuration file follows this structure:

```json
{
  "team": "team_name",
  "description": "Description of what this team manages",
  "table_level_actions": {
    "ModelName": {
      "reason": "Why this model's records need organization-level deletion"
    }
  },
  "tables": {
    "ModelName": {
      "description": "What this model contains",
      "columns": {
        "column_name": {
          "strategy": "delete|hash|mask",
          "reason": "Why this strategy is needed"
        }
      }
    }
  }
}
```

## 🚀 How to Add Your Team's Configuration

### **Step 1: Create Your Team File**
```bash
# Create new file: your_team_name.json
touch jisr-backend/lib/data_privacy_layer/team_configs/your_team.json
```

### **Step 2: Define Your Configuration**
Use the template above and fill in:
- Your team name and contact information
- Tables your team is responsible for
- Columns that contain personal data
- Appropriate anonymization strategy for each column

### **Step 3: Choose the Right Strategy**

#### **Column-Level Strategies:**

**Use DELETE when:**
- Data is not needed for business operations
- Personal notes, comments, temporary data
- Optional fields that can be removed

**Use HASH when:**
- You need consistent identification across records
- Names, IDs, references for analytics
- Data that needs to be linkable but not readable

**Use MASK when:**
- Users/staff need to recognize the data
- Support teams need partial information for verification
- Emails, phone numbers, account numbers

#### **Table-Level Actions:**

**Use Organization-Based Table Deletion when:**
- Need to remove all records for a specific organization
- Organization is cancelled and all data should be deleted
- Cleaning up organization-specific data across multiple tables
- Simple deletion with organization_id passed from calling class
- Examples: Delete all payroll records, attendance logs, or invoices for organization

### **Step 4: Test Your Configuration**
```bash
# Run dry-run to test your configuration
bundle exec rails runner "DataPrivacy::Processor.new(dry_run: true, team: 'your_team').process_all"
```

## 📞 Getting Help

### **Technical Questions**
- **Contact**: Technical Team
- **Documentation**: See main PDPL documentation in parent folder

### **Business Questions** 
- **Contact**: Product Management Team
- **PDPL Compliance**: Legal & Compliance Team

### **Team-Specific Questions**
- **Contact**: See contact email in your team's configuration file

## 🔧 Configuration Examples

### **Column-Level Strategy Examples**

#### **Example 1: Simple Email Masking**
```json
"personal_email": {
  "strategy": "mask",
  "reason": "PII - Email addresses (masked for user recognition)"
}
```

#### **Example 2: Hash for Consistent IDs**
```json
"employee_id": {
  "strategy": "hash", 
  "reason": "PII - Employee identification (hash for analytics)"
}
```

#### **Example 3: Delete Unnecessary Data**
```json
"personal_notes": {
  "strategy": "delete",
  "reason": "PII - Personal notes (not required for business operations)"
}
```

#### **Example 4: Account Number Masking**
```json
"account_number": {
  "strategy": "mask",
  "reason": "PII - Account numbers (masked for verification)"
}
```

### **Table-Level Action Examples**

#### **Example 5: Delete Organization Records from Model**
```json
"TempEmployeeData": {
  "reason": "PDPL - Remove all temporary employee data for organization"
}
```

#### **Example 6: Delete Old Records by Organization**
```json
"AttendanceLog": {
  "reason": "PDPL - Delete old attendance records for organization"
}
```

#### **Example 7: Delete Organization Financial Data**
```json
"Invoice": {
  "reason": "PDPL - Remove old invoices for organization"
}
```

#### **Example 8: Delete Organization Payroll Data**
```json
"PayrollHistory": {
  "reason": "PDPL - Remove old payroll records for organization"
}
```

## ⚠️ Important Guidelines

### **Data Classification**
- **High Risk**: Names, emails, phone numbers, IDs → **Hash or Mask**
- **Medium Risk**: Notes, comments, optional data → **Delete or Hash**  
- **Low Risk**: Non-personal business data → **No action needed**

### **Business Continuity**
- Test configurations with dry-run first
- Ensure business operations continue after anonymization
- Coordinate with other teams for shared tables

### **Compliance Requirements**
- All personal data must have a strategy defined
- Document the reason for each strategy choice
- Regular review and updates as data usage changes

---

**Last Updated**: January 2025  
**Maintained By**: Technical Team  
**Review Cycle**: Quarterly 