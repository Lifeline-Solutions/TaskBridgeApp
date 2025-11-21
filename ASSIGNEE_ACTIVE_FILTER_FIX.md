# Assignee Active Filter Display Fix

## Issue Description
When users selected Assignee filters, they would:
- ✅ Be saved correctly in the filter
- ✅ Apply correctly when filtering defects
- ❌ **NOT appear in the "Active Filters" display section**

Meanwhile, Reporter filters would show correctly in the Active Filters display.

## Root Cause

### The Problem Code
**File**: `app/views/defect/_top_bar_show.html.erb` (Line ~997)

**Assignee Display (BROKEN)**:
```erb
<% Array(params[:user_id]).each do |user_id| %>
  <% if user = @assignees&.find { |u| u.id.to_s == user_id.to_s } %>
    <%= render_filter_chip("Assignee", user_display_name(user), 
        remove_filter_path(:user_id, user_id), filter_type: :assignee) %>
  <% end %>
<% end %>
```

**Reporter Display (WORKING)**:
```erb
<% Array(params[:reporter_id]).each do |reporter_id| %>
  <% if reporter = User.find_by(id: reporter_id) %>
    <%= render_filter_chip("Reporter", user_display_name(reporter), 
        remove_filter_path(:reporter_id, reporter_id), filter_type: :reporter) %>
  <% end %>
<% end %>
```

### Why It Failed

The assignee display relied on the `@assignees` instance variable, which is populated like this:

```ruby
# app/controllers/defect_controller.rb
@assignees = User.joins(:defects)
  .where(defects: { id: filtered_ids })
  .distinct
  .order(:first_name, :last_name)
```

**The Problem**: `@assignees` only contains users who are assigned to defects **in the current filtered result set**.

### Failure Scenarios

#### Scenario 1: Empty Result Set
```
1. User selects Assignee: "John Doe"
2. No defects match this filter yet
3. @assignees is EMPTY (no defects = no assignees)
4. Active Filters: Assignee chip doesn't appear ❌
```

#### Scenario 2: Different Assignee in Results
```
1. User selects Assignee: "John Doe"  
2. Filter returns defects assigned to "Jane Smith" (overlapping with other filters)
3. @assignees = ["Jane Smith"] (only from result set)
4. @assignees.find { id == "john-doe-id" } returns nil
5. Active Filters: John Doe chip doesn't appear ❌
```

#### Scenario 3: Loaded from Saved Filter
```
1. User loads saved filter with Assignee: "John Doe"
2. Page loads before defects are filtered
3. @assignees might be empty or incomplete
4. Active Filters: Assignee chip doesn't appear ❌
```

### Why Reporter Worked

Reporter display used a direct database query:
```erb
<% if reporter = User.find_by(id: reporter_id) %>
```

This **always** finds the user regardless of the current result set, so it always displays correctly.

## The Fix

Change the assignee display to use the same approach as reporter:

### Before (BROKEN):
```erb
<% Array(params[:user_id]).each do |user_id| %>
  <% if user = @assignees&.find { |u| u.id.to_s == user_id.to_s } %>
    <%= render_filter_chip("Assignee", user_display_name(user), 
        remove_filter_path(:user_id, user_id), filter_type: :assignee) %>
  <% end %>
<% end %>
```

### After (FIXED):
```erb
<% Array(params[:user_id]).each do |user_id| %>
  <% if user = User.find_by(id: user_id) %>
    <%= render_filter_chip("Assignee", user_display_name(user), 
        remove_filter_path(:user_id, user_id), filter_type: :assignee) %>
  <% end %>
<% end %>
```

### Changes:
- ❌ **Removed**: `@assignees&.find { |u| u.id.to_s == user_id.to_s }`
- ✅ **Added**: `User.find_by(id: user_id)`

## Why This Works

### Direct Database Query
```ruby
User.find_by(id: user_id)
```

**Benefits**:
1. ✅ **Always finds the user** - regardless of current result set
2. ✅ **Works with saved filters** - loads user even if not in current results
3. ✅ **Works with empty results** - displays filter even with 0 matching defects
4. ✅ **Consistent with Reporter** - uses same pattern for both filter types
5. ✅ **Handles deleted users gracefully** - returns `nil` if user doesn't exist

### Performance Considerations

**Question**: Won't this cause N+1 queries?

**Answer**: Minimal impact because:
1. **Small number of iterations** - Users typically select 1-5 assignees per filter
2. **Simple query** - `WHERE id = ?` is indexed and extremely fast
3. **Cached by Rails** - Same user lookups may be cached
4. **Only in display** - Not in the main defect query loop

**Example**:
```
Scenario: 3 assignees selected
Queries: 3 x User.find_by(id: X)
Total time: ~3ms (1ms each)
Impact: Negligible
```

## Testing

### Test Case 1: Empty Result Set
1. Go to Defects page
2. Select Assignee: "John Doe"
3. Select Priority: "SEVERITY 5" (probably no results)
4. **Expected**: "Assignee: John Doe" chip appears in Active Filters ✅

### Test Case 2: Saved Filter
1. Create and save filter with Assignee selected
2. Navigate away from the page
3. Load the saved filter
4. **Expected**: Assignee filter chip appears immediately ✅

### Test Case 3: Multiple Assignees
1. Select 3 different assignees
2. Apply filters
3. **Expected**: All 3 assignee chips appear in Active Filters ✅

### Test Case 4: Assignee with No Defects
1. Select an assignee who has 0 defects in the current product
2. **Expected**: Assignee chip still appears (even though result is empty) ✅

## Comparison with Other Filters

Let's check how other filters handle this:

| Filter Type | Display Method | Works with Empty Results? |
|-------------|---------------|---------------------------|
| **Product** | `@qa_products&.find` | ❌ May fail |
| **Status** | Direct value display | ✅ Always works |
| **Priority** | Direct value display | ✅ Always works |
| **Assignee** | ~~`@assignees&.find`~~ → `User.find_by` | ✅ **NOW FIXED** |
| **Reporter** | `User.find_by` | ✅ Always works |
| **Module** | `@qa_modules&.find` | ❌ May fail |
| **Submodule** | `@submodules&.find` | ❌ May fail |
| **Banking Type** | `@banking_types&.find` | ❌ May fail |
| **Label** | `@labels&.find` | ❌ May fail |

### Should We Fix Others Too?

**Recommendation**: YES, for consistency and reliability.

The same fix should be applied to:
- Products: Use `Product.find_by(id: product_id)`
- Modules: Use `QaModule.find_by(id: module_id)`
- Submodules: Use `QaModule.find_by(id: submodule_id)`
- Banking Types: Use `BankingType.find_by(id: banking_type_id)`
- Labels: Use `Label.find_by(id: label_id)`

**Why**: All of these can fail in the same scenarios:
1. Empty result sets
2. Loaded from saved filters
3. Overlapping filters with different values

## Files Modified

1. ✅ `app/views/defect/_top_bar_show.html.erb` - Fixed assignee active filter display

## Benefits

1. ✅ **Consistent Display** - Assignee filters always show in Active Filters
2. ✅ **Better UX** - Users can see what filters are active
3. ✅ **Saved Filters Work** - Assignee filters from saved filters display correctly
4. ✅ **Matches Reporter Pattern** - Consistency between similar filter types
5. ✅ **Handles Edge Cases** - Works with empty results, deleted users, etc.

## Related Issues Fixed

This fix is part of a series of fixes for filter persistence:
1. ✅ **Reporter parameter not saved** - Fixed in `FILTER_PERSISTENCE_BUG_FIX.md`
2. ✅ **Assignee not showing in Active Filters** - **THIS FIX**
3. ✅ **Username column error** - Fixed in `USERNAME_COLUMN_FIX.md`
4. ✅ **Filter parameter display showing IDs** - Fixed in `DASHBOARD_FILTER_DISPLAY_FIX.md`

## Date
November 21, 2025
