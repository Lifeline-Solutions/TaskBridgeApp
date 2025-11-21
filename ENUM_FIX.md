# Dashboard Widget Enum Fix

## Issue
When trying to access the defect index page, got this error:
```
ArgumentError: You tried to define an enum named "visualization_type" on the model "DashboardWidget", 
but this will generate a instance method "pie_chart?", which is already defined by another enum.
```

## Root Cause
The enum was defined with **string values** instead of **integer values**:
```ruby
# ❌ WRONG - Using strings
enum visualization_type: {
  pie_chart: 'pie_chart',
  bar_chart: 'bar_chart',
  line_chart: 'line_chart',
  count: 'count',
  table: 'table'
}
```

This caused Rails to generate conflicting instance methods.

## Solution
Changed the enum to use **integer values** with `_prefix: true`:
```ruby
# ✅ CORRECT - Using integers
enum visualization_type: {
  pie_chart: 0,
  bar_chart: 1,
  line_chart: 2,
  count: 3,
  table: 4
}, _prefix: true
```

## Migration Change
Updated the migration from:
```ruby
t.string :visualization_type, null: false, default: 'pie_chart'
```

To:
```ruby
t.integer :visualization_type, null: false, default: 0
```

## What `_prefix: true` Does
The `_prefix: true` option changes the generated methods:
- Without prefix: `widget.pie_chart?` → conflicts possible
- With prefix: `widget.visualization_type_pie_chart?` → no conflicts

**Method names now generated:**
- `widget.visualization_type_pie_chart?` (instead of `widget.pie_chart?`)
- `widget.visualization_type_bar_chart?` (instead of `widget.bar_chart?`)
- etc.

## Database Changes
1. Rolled back migration: `rails db:rollback`
2. Re-ran migration: `rails db:migrate`
3. Table recreated with correct integer column type

## Usage
The usage remains the same:
```ruby
# Creating widgets
widget = DashboardWidget.create!(
  name: "My Widget",
  visualization_type: :pie_chart,  # Still use symbols!
  # ...
)

# Checking type
widget.visualization_type_pie_chart?  # true
widget.visualization_type              # "pie_chart"
widget.visualization_type_before_type_cast  # 0
```

## Status
✅ **FIXED** - Enum now works correctly with integer values
✅ Migration re-run successfully
✅ No more method conflicts
