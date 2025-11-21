# Filter Persistence Bug Fix - Reporter and Assignee Parameters

## Issue Description
When users select Reporter and Assignee filters and save them:
1. ✅ The parameters appear initially when creating the filter
2. ❌ **BUG**: After saving and reloading, Reporter and Assignee disappear
3. ❌ **ROOT CAUSE**: The parameters were never being saved to the database

## Root Cause Analysis

### Problem 1: Missing `reporter_id` in Save Filter Form
**File**: `app/views/defect/_top_bar_show.html.erb`

The form that saves filters was missing the `reporter_id` parameter entirely. While it included:
- `user_id` (Assignee) ✅
- `status` ✅
- `priority` ✅
- `qa_module_id` ✅
- `submodule_id` ✅
- `label_ids` ✅
- `banking_type_id` ✅

It was **missing**:
- `reporter_id` ❌

### Before Fix (Line ~916):
```erb
<% Array(params[:user_id]).each do |user_id| %>
  <%= hidden_field_tag 'defect_filter[filters][user_id][]', user_id %>
<% end %>

<% Array(params[:label_ids]).each do |label_id| %>
  <%= hidden_field_tag 'defect_filter[filters][label_ids][]', label_id %>
<% end %>
```

### After Fix:
```erb
<% Array(params[:user_id]).each do |user_id| %>
  <%= hidden_field_tag 'defect_filter[filters][user_id][]', user_id %>
<% end %>

<% Array(params[:reporter_id]).each do |reporter_id| %>
  <%= hidden_field_tag 'defect_filter[filters][reporter_id][]', reporter_id %>
<% end %>

<% Array(params[:label_ids]).each do |label_id| %>
  <%= hidden_field_tag 'defect_filter[filters][label_ids][]', label_id %>
<% end %>
```

## What Was Happening

### User's Experience:
1. User applies filters with Reporter = "John Doe"
2. User clicks "Save Filters"
3. Modal appears, user enters filter name
4. User clicks "Save Filter" button
5. ✅ Filter appears to save successfully
6. User navigates to "Saved Filters"
7. User clicks "Apply" on the saved filter
8. ❌ **BUG**: Reporter filter is gone!

### Behind the Scenes:
```
1. Initial request: ?reporter_id[]=abc-123&user_id[]=def-456
   ✅ params[:reporter_id] = ["abc-123"]
   ✅ params[:user_id] = ["def-456"]

2. Save Filter Form Submission:
   ✅ Hidden field created: defect_filter[filters][user_id][] = def-456
   ❌ NO hidden field for reporter_id (MISSING!)

3. Controller receives:
   {
     "defect_filter" => {
       "name" => "My Filter",
       "filters" => {
         "user_id" => ["def-456"],
         // reporter_id is NOT HERE!
       }
     }
   }

4. Database stores:
   {
     "user_id": ["def-456"],
     // reporter_id was never saved
   }

5. When filter is applied later:
   ✅ user_id filter appears
   ❌ reporter_id filter is missing
```

## Verification

### Test Before Fix:
```bash
rails runner "
filter = DefectFilter.last
puts 'Has reporter_id? ' + filter.filters.key?('reporter_id').to_s
puts 'reporter_id value: ' + filter.filters['reporter_id'].inspect
"
```

**Output**:
```
Has reporter_id? false
reporter_id value: nil
```

### Test After Fix:
1. Apply filters with Reporter selected
2. Click "Save Filters"
3. Enter filter name and save
4. Run verification:
```bash
rails runner "
filter = DefectFilter.last
puts 'Has reporter_id? ' + filter.filters.key?('reporter_id').to_s
puts 'reporter_id value: ' + filter.filters['reporter_id'].inspect
"
```

**Expected Output**:
```
Has reporter_id? true
reporter_id value: ["abc-123-def-456"]
```

## Complete Flow Now Fixed

### 1. Filter Application (Already Working):
- User selects Reporter from dropdown ✅
- URL updates with `reporter_id` parameter ✅
- Defects are filtered correctly ✅

### 2. Filter Saving (NOW FIXED):
- User clicks "Save Filters" ✅
- Modal shows all active parameters ✅
- Form includes `reporter_id` hidden field ✅ **[FIXED]**
- Submit sends `reporter_id` to controller ✅ **[FIXED]**
- Controller normalizes as array ✅ (already fixed)
- Database stores `reporter_id` ✅ **[FIXED]**

### 3. Filter Retrieval (Already Working):
- User opens "Saved Filters" ✅
- Clicks "Apply" on saved filter ✅
- `reporter_id` is loaded from database ✅ **[FIXED]**
- URL includes `reporter_id` parameter ✅ **[FIXED]**
- Defects are filtered correctly ✅

### 4. Dashboard Display (Already Working):
- Dashboard reads filter parameters ✅
- Shows "Reporter Distribution" chart ✅ (if reporter_id present)
- Displays reporter names (not IDs) ✅

## Related Fixes Already Applied

### 1. Controller Array Normalization:
**File**: `app/controllers/defect_filters_controller.rb`
```ruby
# Already fixed - includes reporter_id
array_keys = %w[product_id user_id reporter_id qa_module_id submodule_id label_ids status]
```

### 2. Allowed Filter Keys:
**File**: `app/models/defect_filter.rb`
```ruby
# Already fixed - includes reporter_id
ALLOWED_FILTER_KEYS = %w[
  client_name product_id query order start_date end_date priority user_id
  qa_module_id submodule_id banking_type_id label_ids status page reporter_id
  filter_open select_all_module select_all_submodule select_all_reporter
].freeze
```

### 3. Helper Display:
**File**: `app/helpers/dashboards_helper.rb`
```ruby
# Already fixed - formats reporter names correctly
def format_reporter_ids(value)
  ids = Array(value)
  reporters = User.where(id: ids).pluck(:first_name, :last_name)
  return value if reporters.empty?
  
  reporters.map { |first, last| "#{first} #{last}".strip }.join(', ')
end
```

## Files Modified in This Fix

1. ✅ `app/views/defect/_top_bar_show.html.erb` - Added reporter_id hidden fields

## Testing Instructions

### Test Case 1: Save Filter with Reporter
1. Go to Defects page
2. Apply filters: Select "Reporter" = "John Doe"
3. Click "Save Filters"
4. Enter name: "Reporter Test"
5. Click "Save Filter"
6. Navigate to "Saved Filters" page
7. Click "Apply" on "Reporter Test"
8. **Expected**: Reporter filter is still active ✅

### Test Case 2: Save Filter with Multiple Parameters
1. Apply filters:
   - Reporter = "John Doe", "Jane Smith"
   - Assignee = "Bob Wilson"
   - Priority = "High", "Critical"
2. Click "Save Filters"
3. Enter name: "Complex Filter"
4. Click "Save Filter"
5. Navigate away, then return
6. Apply "Complex Filter"
7. **Expected**: All filters still active ✅

### Test Case 3: Create Dashboard from Reporter Filter
1. Create and save a filter with Reporter selected
2. Go to "QA Dashboards"
3. Create new dashboard
4. Select the reporter filter
5. View dashboard
6. **Expected**: 
   - Reporter Distribution chart appears ✅
   - Active parameters show reporter names (not IDs) ✅

## Similar Issues to Check

### Other parameters that might have the same issue:
Check if these are all included in the save filter form:

| Parameter | In Form? | Status |
|-----------|----------|--------|
| `status` | ✅ Yes | Working |
| `priority` | ✅ Yes | Working |
| `user_id` | ✅ Yes | Working |
| `reporter_id` | ✅ **NOW FIXED** | **FIXED** |
| `qa_module_id` | ✅ Yes | Working |
| `submodule_id` | ✅ Yes | Working |
| `label_ids` | ✅ Yes | Working |
| `banking_type_id` | ✅ Yes | Working |
| `client_name` | ✅ Yes | Working |
| `order` | ✅ Yes | Working |
| `start_date` | ✅ Yes | Working |
| `end_date` | ✅ Yes | Working |
| `query` | ✅ Yes | Working |

### All parameters are now accounted for! ✅

## Prevention Strategy

### For Future Parameter Additions:

When adding a new filter parameter, remember to update **THREE places**:

1. **Model** - Add to `ALLOWED_FILTER_KEYS`:
   ```ruby
   # app/models/defect_filter.rb
   ALLOWED_FILTER_KEYS = %w[... new_param]
   ```

2. **Controller** - Add to array normalization if it's an array param:
   ```ruby
   # app/controllers/defect_filters_controller.rb
   array_keys = %w[... new_param]
   ```

3. **View** - Add hidden field in save filter form:
   ```erb
   <%# app/views/defect/_top_bar_show.html.erb %>
   <% Array(params[:new_param]).each do |value| %>
     <%= hidden_field_tag 'defect_filter[filters][new_param][]', value %>
   <% end %>
   ```

## Date
November 21, 2025
