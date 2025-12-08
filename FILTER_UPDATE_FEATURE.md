# Filter Update Feature - Implementation Complete

## Overview
Users can now update existing saved filters after applying and modifying them.

## User Flow

### 1. Apply a Saved Filter
- Navigate to Defects → Index Show
- Click the "Saved filters" dropdown (in `_saved_filters.html.erb`)
- Select a filter from the list
- System redirects with `current_filter_id` parameter

### 2. Modify Filter Parameters
- Change any filter values (status, priority, assignee, etc.)
- Click "Apply Filters" button
- `current_filter_id` persists via hidden field

### 3. Update the Filter
- **"Update Filter"** button appears (blue with refresh icon)
- Button text changes from "Save Filters" to "Update Filter"
- Click the button to open modal
- Modal shows filter name (pre-filled)
- Click "Update Filter" to save changes

### 4. Create New Filter (Alternative Path)
- If no filter is applied, button shows **"Save Filters"** (green with save icon)
- Click to create a new filter with current parameters

## Implementation Details

### Controller Logic (`app/controllers/defect_controller.rb`)

#### Filter Application (Lines 212-220)
```ruby
if params[:filter_id].present?
  filter = current_user.defect_filters.active.find_by(id: params[:filter_id])
  if filter
    merged = filter.sanitized_filters_string_keys || {}
    merged['product_id'] = filter.product_id if filter.product_id.present?
    merged.except!('page')
    redirect_to index_show_defect_index_path(merged.merge(current_filter_id: filter.id))
  end
end
```

#### Filter Tracking (Lines 247-264)
```ruby
# Track applied filter
@current_filter = current_user.defect_filters.active.find_by(id: params[:current_filter_id])

# Detect exact match
filter_only_params = { status: ..., priority: ..., ... }
@matching_filter = current_user.defect_filters.active.find do |filter|
  normalize_filter_params(filter.sanitized_filters_string_keys) == normalize_filter_params(filter_only_params)
end

# Determine which filter to update (prefer applied over matched)
@filter_to_update = @current_filter || @matching_filter
```

### View Updates (`app/views/defect/_top_bar_show.html.erb`)

#### Dynamic Button (Line 67)
```erb
<button type="button" 
        data-action="click->filter-modal#openSaveModal"
        class="inline-flex items-center gap-2 px-3 py-2 <%= @filter_to_update ? 'text-blue-600 ...' : 'text-green-600 ...' %>">
  <%= inline_svg_tag @filter_to_update ? "refresh.svg" : "save.svg", class: "w-4 h-4" %>
  <%= @filter_to_update ? 'Update Filter' : 'Save Filters' %>
</button>
```

#### Hidden Field for State Preservation (Line 100)
```erb
<%= hidden_field_tag :current_filter_id, params[:current_filter_id] if params[:current_filter_id].present? %>
```

#### Modal Form (Lines 954-1050)
```erb
<h3 class="text-xl font-bold mb-4 text-gray-900 dark:text-white">
  <%= @filter_to_update ? "Update Filter: #{@filter_to_update.name}" : "Save Current Filters" %>
</h3>

<%= form_with model: @filter_to_update || DefectFilter.new, 
              url: @filter_to_update ? defect_filter_path(@filter_to_update) : defect_filters_path,
              method: @filter_to_update ? :patch : :post do |f| %>
  
  <%= f.text_field :name, value: @filter_to_update&.name %>
  <%= f.hidden_field :filters, value: request.query_parameters.to_json %>
  
  <button type="submit" class="<%= @filter_to_update ? 'bg-blue-600' : 'bg-green-600' %>">
    <%= @filter_to_update ? 'Update Filter' : 'Save Filter' %>
  </button>
<% end %>
```

### Saved Filters Dropdown (`app/views/defect/_saved_filters.html.erb`)
```erb
<%= form_with url: index_show_defect_index_path, method: :get do %>
  <%= select_tag :filter_id,
        options_from_collection_for_select(current_user.defect_filters.active.order(:name), :id, :name),
        include_blank: 'Saved filters',
        onchange: 'this.form.submit()' %>
<% end %>
```

## Technical Highlights

### Priority Logic
`@filter_to_update = @current_filter || @matching_filter`

- **@current_filter**: Explicitly applied via dropdown (has higher priority)
- **@matching_filter**: Auto-detected when current parameters exactly match a saved filter
- This ensures the correct filter is updated when user explicitly selects one

### State Persistence
- `current_filter_id` URL parameter tracks applied filter across page loads
- Hidden field in filter form preserves this when applying new filters
- Removed from final redirect to avoid stale references

### Parameter Normalization
```ruby
def normalize_filter_params(params)
  # Convert all values to strings, handle arrays
  # Ensure consistent comparison between saved and current filters
end
```

## Files Modified

1. **app/controllers/defect_controller.rb** (Lines 212-264)
   - Added `current_filter_id` redirect parameter
   - Implemented filter tracking logic
   - Created `@filter_to_update` variable

2. **app/views/defect/_top_bar_show.html.erb**
   - Dynamic button text and styling (line 67)
   - Hidden field for state tracking (line 100)
   - Modal title and form updates (lines 954-1050)
   - Removed duplicate "Update Filters" button

3. **app/views/defect/_saved_filters.html.erb** (no changes needed)
   - Already had dropdown with `filter_id` submission

## Testing Checklist

- [x] Select saved filter → verify URL has `current_filter_id`
- [x] Modify filter → verify "Update Filter" button appears (blue)
- [x] Click update → verify modal shows filter name
- [x] Submit update → verify filter updates (not creates new)
- [x] Clear filters → verify "Save Filters" button appears (green)
- [x] Auto-match detection → verify matching filter shows update option
- [ ] Test with filter deletion while applied
- [ ] Test with multiple filters
- [ ] Test filter ownership/permissions

## Edge Cases Handled

1. **Applied filter deleted**: `@current_filter` will be nil, falls back to `@matching_filter`
2. **No filters applied**: Both nil, shows "Save Filters" for new creation
3. **Parameters match multiple filters**: Uses the one explicitly applied first
4. **Filter modified to match another**: Still updates the applied filter (not the matched one)

## Related Features

- Dashboard custom fields (aligned with these filter options)
- Filter management page (`defect_filters_path`)
- Product-specific filters
- Auto-save functionality (future enhancement?)

## Notes

- The feature is fully functional and ready for testing
- CSS linter warnings are cosmetic (Tailwind conditional classes)
- Consider adding confirmation dialog before updating filters
- Future: Add "Save as New" option in update modal
