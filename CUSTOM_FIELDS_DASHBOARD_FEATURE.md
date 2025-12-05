# Custom Field Dashboard Feature - Implementation Summary

## Overview
Added custom field selection capability to QA dashboards, allowing users to display distribution charts for any selected fields alongside filter-based metrics.

## Feature Description
When creating a dashboard, users can now:
1. Select a saved filter as the data source (existing feature)
2. **NEW**: Choose which fields should have distribution charts displayed (status, reporter, assignee, labels, modules, submodules, banking types, priority, ageing)
3. View the dashboard with both:
   - **Filter-based distributions** (automatic charts based on active filter parameters)
   - **Custom field distributions** (user-selected fields showing distribution across all filtered data)

## Implementation Details

### 1. Database Migration
**File**: `db/migrate/20250102120000_add_custom_fields_to_dashboards.rb`

- Added `custom_fields` JSONB column to `dashboards` table
- Stores array of selected field names (e.g., `["status", "reporter", "banking_type"]`)
- Added GIN index for efficient querying

```sql
t.jsonb :custom_fields, default: [], comment: "Array of custom field names..."
add_index :dashboards, :custom_fields, using: :gin
```

### 2. Model Updates
**File**: `app/models/dashboard.rb`

- Added `custom_fields` JSONB attribute with default empty array
- Added validation method `validate_custom_fields` to ensure only valid fields are stored
- Validates against `GROUPABLE_FIELDS` constant

```ruby
attribute :custom_fields, :jsonb, default: []
validate :validate_custom_fields
```

### 3. New Service Class
**File**: `app/services/custom_field_chart_generator.rb`

Generates distribution charts for any custom field:
- **Status**: Distribution across status values
- **Priority**: Distribution by severity levels
- **Assignee**: Distribution across assigned users
- **Reporter**: Distribution across reporters
- **QA Module**: Distribution across modules
- **Submodule**: Distribution across submodules
- **Banking Type**: Distribution across banking types
- **Label**: Distribution across labels
- **Ageing**: Distribution by age groups (This Week, Last Week, This Month, etc.)

### 4. Controller Updates
**File**: `app/controllers/qa_dashboards_controller.rb`

- Updated `dashboard_params` to permit `custom_fields` array parameter
- Enhanced `show` action to:
  - Generate custom field charts via `generate_custom_field_charts` method
  - Pass `@custom_field_charts` to view for rendering

```ruby
def dashboard_params
  params.require(:dashboard).permit(
    :name,
    :description,
    :defect_filter_id,
    :auto_refresh_interval,
    custom_fields: [],  # NEW
    widgets: %i[name group_by_field visualization_type position]
  )
end
```

### 5. View Updates

#### Form (`app/views/qa_dashboards/_form.html.erb`)
Added new section "Custom Field Distributions (Optional)" with:
- Multi-select checkboxes for all available fields
- Blue-highlighted info box to distinguish from other form sections
- Responsive grid layout (2-3 columns depending on screen size)

#### Dashboard Show (`app/views/qa_dashboards/show.html.erb`)
Added new "Custom Field Distributions" section after filter-based charts:
- Green header section with icon for visual distinction
- Grid layout showing distribution charts for each selected field
- Each chart displays:
  - Pie chart visualization
  - Breakdown table with counts and percentages
  - Total count badge

## User Experience Flow

### Creating/Editing a Dashboard
1. User navigates to "Create Dashboard" or "Edit Dashboard"
2. Fills in Dashboard Name, Description, and selects Data Source (Saved Filter)
3. **NEW**: Scrolls to "Custom Field Distributions (Optional)" section
4. Selects fields that interest them (e.g., Status, Reporter, Banking Type)
5. Saves dashboard

### Viewing a Dashboard
1. Dashboard displays filter-based metrics (existing feature)
2. **NEW**: Below existing charts, displays custom field distributions
3. Each custom field shows its own pie chart and breakdown table
4. User can toggle field selection by editing the dashboard

## Available Custom Fields
All fields are based on the `Dashboard::GROUPABLE_FIELDS` constant:
- `priority` - Severity levels (1-4 and Unknown)
- `status` - Defect status values
- `assignee` - Users assigned to defects
- `reporter` - Users who created defects
- `qa_module` - QA modules
- `submodule` - Sub-modules
- `banking_type` - Banking types
- `label` - Labels applied to defects
- `ageing` - Age groups (This Week, Last Week, This Month, Last 3 Months, Older)

## Database Queries
The implementation uses efficient SQL queries with:
- Proper joins to related tables
- Group aggregation for counting
- GIN index on JSONB column for fast lookups

Example Status Distribution Query:
```ruby
defects
  .joins(:statuses)
  .group('statuses.name')
  .count
```

## Technical Specifications

### Classes Created
- `CustomFieldChartGenerator` - Service for generating distribution data

### Files Modified
- `app/models/dashboard.rb` - Added custom_fields attribute and validation
- `app/controllers/qa_dashboards_controller.rb` - Added parameter handling and chart generation
- `app/views/qa_dashboards/_form.html.erb` - Added custom field selection UI
- `app/views/qa_dashboards/show.html.erb` - Added custom field charts display

### Migration
- `db/migrate/20250102120000_add_custom_fields_to_dashboards.rb` - Database schema update

## Validation & Testing
✅ All components tested and working:
- Dashboard model has custom_fields attribute
- GROUPABLE_FIELDS constant properly defined
- CustomFieldChartGenerator successfully generates charts for all field types
- Forms correctly display checkboxes for field selection
- Dashboard display properly renders custom field sections

## Future Enhancements
- Customize chart colors per field
- Save and reuse custom chart configurations
- Export custom field data to CSV/Excel
- Comparison charts (trends over time)
- Custom field ordering/arrangement
