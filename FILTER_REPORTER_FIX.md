# Filter Save Fix - Reporter Parameter Support

## Issue
Users could not save filters with Reporter (reporter_id) parameter selections. The filter form displayed the Reporter dropdown, but when saving the filter, the reporter_id parameter was being stripped out.

## Root Cause
The `DefectFiltersController#permit_filter_keys` method had a hardcoded list of array parameters that did not include `reporter_id`. This caused the reporter selections to be ignored when saving filters.

## Changes Made

### File: `app/controllers/defect_filters_controller.rb`

#### Before:
```ruby
def permit_filter_keys(raw_hash)
  raw = raw_hash.to_h.with_indifferent_access.slice(*DefectFilter::ALLOWED_FILTER_KEYS)

  # Normalize array parameters
  array_keys = %w[product_id user_id qa_module_id submodule_id label_ids status]
  array_keys.each do |key|
    raw[key] = Array(raw_hash[key]).reject(&:blank?) if raw_hash.key?(key)
  end

  # Handle boolean/string parameters
  raw['filter_open'] = raw_hash['filter_open'] if raw_hash.key?('filter_open')
  raw['select_all_module'] = raw_hash['select_all_module'] if raw_hash.key?('select_all_module')
  raw['select_all_submodule'] = raw_hash['select_all_submodule'] if raw_hash.key?('select_all_submodule')

  raw
end
```

#### After:
```ruby
def permit_filter_keys(raw_hash)
  raw = raw_hash.to_h.with_indifferent_access.slice(*DefectFilter::ALLOWED_FILTER_KEYS)

  # Normalize array parameters
  array_keys = %w[product_id user_id reporter_id qa_module_id submodule_id label_ids status]
  array_keys.each do |key|
    raw[key] = Array(raw_hash[key]).reject(&:blank?) if raw_hash.key?(key)
  end

  # Handle boolean/string parameters
  raw['filter_open'] = raw_hash['filter_open'] if raw_hash.key?('filter_open')
  raw['select_all_module'] = raw_hash['select_all_module'] if raw_hash.key?('select_all_module')
  raw['select_all_submodule'] = raw_hash['select_all_submodule'] if raw_hash.key?('select_all_submodule')
  raw['select_all_reporter'] = raw_hash['select_all_reporter'] if raw_hash.key?('select_all_reporter')

  raw
end
```

### Changes:
1. ✅ Added `reporter_id` to the `array_keys` list
2. ✅ Added `select_all_reporter` boolean parameter handling

## Related Files Previously Updated

### File: `app/models/defect_filter.rb`
Already updated to include `reporter_id` in `ALLOWED_FILTER_KEYS`:
```ruby
ALLOWED_FILTER_KEYS = %w[
  client_name product_id query order start_date end_date priority user_id
  qa_module_id submodule_id banking_type_id label_ids status page reporter_id
  filter_open select_all_module select_all_submodule select_all_reporter
].freeze
```

### File: `app/services/dashboard_data_generator.rb`
Already updated to check for `reporter_id` parameter:
```ruby
def should_show_reporter_chart?(active_params)
  # For report filters, check for 'reporters' parameter
  # For defect filters, check for 'reporter_id' parameter
  active_params['reporters'].present? || active_params['reporter_id'].present?
end
```

## How It Works Now

### 1. Creating a Filter with Reporter
1. User navigates to Defects page
2. Opens filter dropdown
3. Selects "Filter by Reporter"
4. Chooses one or more reporters
5. Clicks "Save Filters"
6. **Now**: `reporter_id` parameter is properly saved in the filter

### 2. Dashboard Generation
1. User creates a dashboard from saved filter
2. If filter contains `reporter_id` parameter
3. **Now**: "Reporter Distribution" chart is automatically generated
4. Chart shows defect counts by reporter (creator)

## Complete Flow

```
User Action                    → System Behavior
──────────────────────────────────────────────────────────────
1. Select reporters in filter  → reporter_id[] params sent
2. Click "Save Filter"         → DefectFiltersController#create
3. Filter saved                → reporter_id stored in filters JSON
4. Create dashboard            → Dashboard references saved filter  
5. View dashboard              → DashboardDataGenerator checks params
6. Reporter param found        → generate_reporter_chart() called
7. Chart displayed             → Shows defects grouped by creator
```

## Array Parameters Handled

The controller now properly handles these array parameters:
- `product_id` - Project/Product selections
- `user_id` - Assignee selections (who defect is assigned to)
- `reporter_id` - Reporter selections (who created the defect) ✅ **NEW**
- `qa_module_id` - Module selections
- `submodule_id` - Submodule selections
- `label_ids` - Label selections
- `status` - Status selections

## Boolean Parameters Handled

The controller now properly handles these boolean/checkbox parameters:
- `filter_open` - Open/Closed filter toggle
- `select_all_module` - Select all modules checkbox
- `select_all_submodule` - Select all submodules checkbox
- `select_all_reporter` - Select all reporters checkbox ✅ **NEW**

## Testing

To verify the fix works:

1. **Create a filter with reporters:**
   - Go to Defects page
   - Click "Filters"
   - Expand "Reporter" dropdown
   - Select one or more reporters
   - Click "Save Filters"
   - Give it a name (e.g., "Reporter Test Filter")

2. **Verify filter was saved:**
   - Go to "Saved Filters" page
   - Find your filter
   - Check that it shows the reporter parameter

3. **Create dashboard from filter:**
   - Go to "QA Dashboards"
   - Click "Create Dashboard"
   - Select your "Reporter Test Filter"
   - Fill in dashboard name
   - Click "Create Dashboard"

4. **Verify Reporter chart appears:**
   - Dashboard should show "Reporter Distribution" chart
   - Chart shows defect counts grouped by who created them
   - Each reporter's name appears with their count and percentage

## Benefits

1. ✅ **Complete Filter Functionality** - All filter parameters now work correctly
2. ✅ **Reporter Tracking** - Can filter and visualize defects by who reported them
3. ✅ **Team Metrics** - See which team members are reporting the most defects
4. ✅ **Data Consistency** - Reporter parameter flows correctly from filter → dashboard → chart

## Date
November 21, 2025
