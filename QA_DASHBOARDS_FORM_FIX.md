# QA Dashboards Form Fix - Dynamic Widget Fields

## Issue
When clicking "Create Dashboard" in the QA Dashboards section, encountered error:
```
NoMethodError in QaDashboards#new
undefined method `label' for nil
```

This occurred in `app/views/qa_dashboards/_widget_fields.html.erb` at line 12.

## Root Cause
The `qa_dashboards` form uses JavaScript to dynamically add widget fields. The JavaScript was attempting to render an ERB partial with `f: nil`:

```javascript
newWidget.innerHTML = `
  <%= render 'widget_fields', f: nil %>
`.replace(/\[widgets\]\[\d+\]/g, `[widgets][${widgetIndex}]`)
```

This approach doesn't work because:
1. ERB templates are rendered server-side, not client-side
2. Passing `f: nil` means the form builder is nil, causing `f.label` to fail
3. JavaScript string replacement can't modify already-rendered ERB

## Solution

### 1. Updated `_form.html.erb` JavaScript
Replaced the ERB rendering approach with pure HTML generation:

```javascript
newWidget.innerHTML = `
  <div class="flex items-start justify-between mb-3">
    <h3 class="text-sm font-medium text-gray-900 dark:text-white">Widget Configuration</h3>
    <button type="button" class="remove-widget-btn">...</button>
  </div>
  
  <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
    <!-- Widget Name -->
    <div>
      <label>Widget Name</label>
      <input type="text" 
             name="dashboard[widgets_attributes][${widgetIndex}][name]"
             ...>
    </div>
    
    <!-- Group By Field -->
    <div>
      <label>Data Source</label>
      <select name="dashboard[widgets_attributes][${widgetIndex}][group_by_field]">
        <option value="">Select field...</option>
        <option value="priority">Priority</option>
        <option value="status">Status</option>
        <option value="module">Module</option>
        <option value="assignee">Assignee</option>
        <option value="created_date">Created Date</option>
      </select>
    </div>
    
    <!-- Visualization Type -->
    <div>
      <label>Visualization</label>
      <select name="dashboard[widgets_attributes][${widgetIndex}][visualization_type]">
        <option value="">Select type...</option>
        <option value="0">Pie Chart</option>
        <option value="1">Bar Chart</option>
        <option value="2">Line Chart</option>
        <option value="3">Table</option>
        <option value="4">Count</option>
      </select>
    </div>
  </div>
  
  <input type="hidden" name="dashboard[widgets_attributes][${widgetIndex}][position]" value="${widgetIndex}">
`;
```

**Key Changes:**
- Generate pure HTML instead of trying to render ERB
- Use template literals with `${widgetIndex}` for dynamic field names
- Hardcode the options based on `Dashboard::GROUPABLE_FIELDS` and `Dashboard::VISUALIZATION_TYPES`
- Properly increment `widgetIndex` for each new widget

### 2. Updated `_widget_fields.html.erb` Partial
Changed from using the safe navigation operator (`&.`) to `try()` method:

```ruby
# Before:
f.object&.[]('group_by_field')

# After:
f.object.try(:[], 'group_by_field')
```

**Rationale:**
- `f.object` might not be a Hash in all cases
- `try()` is safer and won't fail if object doesn't respond to `[]`
- Handles both new and existing widgets properly

### 3. Enhanced Widget Removal Logic
Updated the removal handler to support both new and persisted widgets:

```javascript
container.addEventListener('click', function(e) {
  if (e.target.closest('.remove-widget-btn')) {
    const widgetGroup = e.target.closest('.widget-field-group');
    if (widgetGroup) {
      // Check if this is a persisted widget
      const destroyInput = widgetGroup.querySelector('input[name*="_destroy"]');
      if (destroyInput) {
        // Mark for destruction instead of removing
        destroyInput.value = '1';
        widgetGroup.style.display = 'none';
      } else {
        // Remove from DOM if it's a new widget
        widgetGroup.remove();
      }
    }
  }
});
```

## Technical Details

### QA Dashboards System Structure
Unlike `dashboard_widgets`, the `qa_dashboards` system uses:
- **Dashboard** model with JSONB `widgets` column
- Multiple widgets per dashboard (array of hashes)
- Each widget has: `name`, `group_by_field`, `visualization_type`, `position`

### Widget Attributes Structure
```ruby
{
  name: "By Priority",
  group_by_field: "priority",
  visualization_type: 0,  # pie_chart
  position: 0
}
```

### Form Parameter Structure
When submitted, parameters look like:
```ruby
dashboard: {
  name: "My Dashboard",
  defect_filter_id: 123,
  widgets_attributes: {
    0 => { name: "Widget 1", group_by_field: "priority", visualization_type: "0" },
    1 => { name: "Widget 2", group_by_field: "status", visualization_type: "1" }
  }
}
```

## Files Modified

1. **app/views/qa_dashboards/_form.html.erb**
   - Replaced ERB template rendering with pure HTML generation
   - Fixed dynamic widget field name generation
   - Enhanced widget removal logic

2. **app/views/qa_dashboards/_widget_fields.html.erb**
   - Changed `&.[]` to `.try(:[], ...)` for safer object access
   - Ensures compatibility with both Hash and non-Hash objects

## Testing

- [ ] Navigate to QA Dashboards
- [ ] Click "Create Dashboard"
- [ ] Fill in dashboard name and select filter
- [ ] Click "Add Widget" button
- [ ] Verify widget fields appear correctly
- [ ] Fill in widget details (name, data source, visualization)
- [ ] Add multiple widgets
- [ ] Remove a widget
- [ ] Submit form and verify dashboard is created with widgets
- [ ] Edit existing dashboard
- [ ] Verify existing widgets load correctly
- [ ] Add/remove widgets and save

## Related Systems

Note: Your application has TWO separate dashboard systems:

1. **dashboard_widgets** (recently refactored)
   - Single table: `dashboard_widgets`
   - Multi-chart automatic generation
   - Filter-driven visualizations
   - Located in `app/controllers/dashboard_widgets_controller.rb`

2. **qa_dashboards** (this fix)
   - Single table: `dashboards`
   - Manual widget configuration
   - JSONB widgets column
   - Located in `app/controllers/qa_dashboards_controller.rb`

## Date
November 21, 2025
