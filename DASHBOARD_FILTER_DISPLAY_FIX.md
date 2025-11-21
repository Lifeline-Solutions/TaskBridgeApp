# Dashboard Filter Display Fix - Show Names Instead of IDs

## Issue
The "Active Filter Parameters" section on dashboard pages was displaying raw UUID values instead of human-readable names for:
- **Qa Module** - Showing UUID instead of module name
- **Label Ids** - Showing UUID instead of label names
- **User Id** (Assignees) - Would show UUID instead of usernames
- **Reporter Id** - Would show UUID instead of usernames
- Other ID-based filters

### Example Before Fix:
```
Active Filter Parameters
Client Name: Vision Fund Service Desk
Qa Module: a6d7efce-2baa-4ccc-b532-09e5fc8385e4  ❌
Label Ids: b2942e12-4aff-4b3a-b3a9-75b03c1ebe19  ❌
```

### Example After Fix:
```
Active Filter Parameters
Client Name: Vision Fund Service Desk
Qa Module: Backend APIs  ✅
Label Ids: bug, critical  ✅
```

## Solution

### 1. Created Helper Method
**File**: `app/helpers/dashboards_helper.rb`

Added a comprehensive helper method that converts IDs to names based on the parameter type:

```ruby
def format_filter_value(key, value)
  return value if value.blank?

  case key.to_s
  when 'qa_module_id'
    format_qa_module_ids(value)
  when 'submodule_id'
    format_submodule_ids(value)
  when 'label_ids'
    format_label_ids(value)
  when 'user_id'
    format_user_ids(value)
  when 'reporter_id'
    format_reporter_ids(value)
  when 'product_id'
    format_product_ids(value)
  when 'banking_type_id'
    format_banking_type_ids(value)
  when 'priority', 'status'
    format_array_value(value)
  else
    value.is_a?(Array) ? value.join(', ') : value
  end
end
```

### 2. Private Helper Methods
Each ID type has its own formatter method that:
1. Converts the value to an array (handles both single and multiple selections)
2. Queries the database to get the names
3. Joins the names with commas
4. Falls back to the original value if no records found

#### Example Methods:
```ruby
def format_qa_module_ids(value)
  ids = Array(value)
  modules = QaModule.where(id: ids).pluck(:name)
  modules.any? ? modules.join(', ') : value
end

def format_label_ids(value)
  ids = Array(value)
  labels = Label.where(id: ids).pluck(:name)
  labels.any? ? labels.join(', ') : value
end

def format_user_ids(value)
  ids = Array(value)
  users = User.where(id: ids).pluck(:first_name, :last_name)
  return value if users.empty?
  
  users.map { |first, last| "#{first} #{last}".strip }.join(', ')
end
```

**Note**: For User-related filters (assignees, reporters), the method retrieves both `first_name` and `last_name` columns and combines them into full names.

### 3. Updated Views
Updated both dashboard view files to use the helper method:

#### File: `app/views/qa_dashboards/show.html.erb`
**Before:**
```erb
<%= value.is_a?(Array) ? value.join(', ') : value %>
```

**After:**
```erb
<%= format_filter_value(key, value) %>
```

#### File: `app/views/dashboard_widgets/show.html.erb`
**Before:**
```erb
<%= format_filter_value(value) %>
```

**After:**
```erb
<%= format_filter_value(key, value) %>
```

## Filter Parameters Handled

| Parameter | Display Format | Example |
|-----------|---------------|---------|
| `qa_module_id` | Module name(s) | "Backend APIs, Frontend" |
| `submodule_id` | Submodule name(s) | "User Authentication, Payment Processing" |
| `label_ids` | Label name(s) | "bug, critical, security" |
| `user_id` | Full name(s) | "John Doe, Jane Smith" |
| `reporter_id` | Full name(s) | "Alice Johnson, Bob Williams" |
| `product_id` | Product name(s) | "Vision Fund Service Desk" |
| `banking_type_id` | Banking type name(s) | "Retail, Corporate" |
| `priority` | Priority values | "High, Critical" |
| `status` | Status values | "Open, In Progress" |
| `client_name` | Client name | "Vision Fund Service Desk" |

## Benefits

### 1. ✅ **Improved User Experience**
- Dashboard now displays human-readable information
- Users can quickly understand what filters are active
- No need to look up UUIDs in the database

### 2. ✅ **Consistent Display**
- All ID-based parameters are formatted consistently
- Works for single and multiple selections
- Handles arrays automatically

### 3. ✅ **Maintainable Code**
- Single helper method handles all parameter types
- Easy to add new parameter types
- Centralized formatting logic

### 4. ✅ **Performance Optimized**
- Uses `.pluck()` for minimal database queries
- Only queries when IDs are present
- Falls back gracefully if records not found

### 5. ✅ **Defensive Programming**
- Returns original value if no records found
- Handles nil/blank values
- Works with both single values and arrays

## Testing

### Test Case 1: Module Filter
1. Create a filter with a specific module selected
2. Create a dashboard from that filter
3. View the dashboard
4. **Expected**: "Qa Module: [Module Name]" instead of UUID

### Test Case 2: Label Filter
1. Create a filter with multiple labels
2. Create a dashboard from that filter
3. View the dashboard
4. **Expected**: "Label Ids: label1, label2, label3" instead of UUIDs

### Test Case 3: Reporter Filter
1. Create a filter with reporters selected
2. Create a dashboard from that filter
3. View the dashboard
4. **Expected**: "Reporter Id: username1, username2" instead of UUIDs

### Test Case 4: Multiple Filters
1. Create a filter with module, labels, and assignees
2. Create a dashboard from that filter
3. View the dashboard
4. **Expected**: All parameters show names instead of IDs

## Files Modified

1. ✅ `app/helpers/dashboards_helper.rb` - Added format_filter_value method
2. ✅ `app/views/qa_dashboards/show.html.erb` - Updated to use helper
3. ✅ `app/views/dashboard_widgets/show.html.erb` - Updated to use helper

## Technical Details

### Database Models Used
- `QaModule` - For module/submodule names (uses `name` column)
- `Label` - For label names (uses `name` column)
- `User` - For assignee/reporter full names (uses `first_name` and `last_name` columns)
- `Product` - For product names (uses `name` column)
- `BankingType` - For banking type names (uses `name` column)

### Query Strategy
- Uses `.pluck(:name)` for single-column lookups (modules, labels, products, etc.)
- Uses `.pluck(:first_name, :last_name)` for User model to get full names
- Returns array of tuples for multi-column plucks, then maps to combine names
- Single query per parameter type
- No N+1 query issues

### Array Handling
```ruby
ids = Array(value)  # Converts single value or array to array
```
This ensures the code works whether the parameter is:
- A single ID: `"abc-123"`
- An array of IDs: `["abc-123", "def-456"]`

### User Name Handling
```ruby
users = User.where(id: ids).pluck(:first_name, :last_name)
users.map { |first, last| "#{first} #{last}".strip }.join(', ')
```
This retrieves both name columns and combines them with proper spacing.

## Future Enhancements

### Possible Additions:
1. Add caching for frequently accessed names
2. Add tooltips showing both ID and name
3. Add icons next to different parameter types
4. Add color coding by parameter category
5. Add "Clear filter" buttons for individual parameters

## Date
November 21, 2025
