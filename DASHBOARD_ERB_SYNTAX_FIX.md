# Dashboard Show View ERB Syntax Fix

## Issue
When viewing a dashboard, the following ERB syntax error occurred:

```
ActionView::SyntaxErrorInTemplate: syntax error, unexpected instance variable, expecting `when'
```

Error occurred at line 99 in `app/views/dashboard_widgets/show.html.erb`.

## Root Cause
In ERB templates, when using `case/when` statements, you cannot have HTML comments or blank lines between the ERB tags. The original code had:

```erb
<% case @dashboard.visualization_type %>

<!-- Table View -->
<% when 'table' %>
```

This creates invalid Ruby syntax because the HTML comment `<!-- Table View -->` appears outside the ERB tags, causing the parser to encounter content between the `case` and `when` statements.

## Solution
Fixed the `case/when` structure by:
1. Combining the `case` statement with the first `when` on a continuous line
2. Converting HTML comments to ERB comments using `<%# ... %>`

### Before (Incorrect):
```erb
<% case @dashboard.visualization_type %>

<!-- Table View -->
<% when 'table' %>
  ...
<!-- Count View -->
<% when 'count' %>
  ...
<!-- Chart Views (Pie, Bar, Line) -->
<% when 'pie_chart' %>
```

### After (Correct):
```erb
<% case @dashboard.visualization_type
# Table View
when 'table' %>
  ...
<%# Count View %>
<% when 'count' %>
  ...
<%# Chart Views (Pie, Bar, Line) %>
<% when 'pie_chart' %>
```

## Technical Explanation

### ERB Case/When Syntax Rules
1. **Continuous ERB blocks**: When using `case/when`, all the case logic must be within ERB tags
2. **No HTML between case and when**: You cannot have HTML comments or content between the `case` and first `when`
3. **ERB comments**: Use `<%# comment %>` for comments within the case statement, not `<!-- comment -->`

### Valid Patterns

**Pattern 1 - Inline first when:**
```erb
<% case variable
when 'value1' %>
  content
<% when 'value2' %>
  content
<% end %>
```

**Pattern 2 - Separate case statement:**
```erb
<% case variable %>
<% when 'value1' %>
  content
<% when 'value2' %>
  content
<% end %>
```

**Pattern 3 - With ERB comments:**
```erb
<% case variable
<%# Comment about value1 %>
when 'value1' %>
  content
<% end %>
```

## Files Modified

### app/views/dashboard_widgets/show.html.erb
- Line 98: Combined `case` with first `when` statement
- Line 164: Changed `<!-- Count View -->` to `<%# Count View %>`
- Line 177: Changed `<!-- Chart Views (Pie, Bar, Line) -->` to `<%# Chart Views (Pie, Bar, Line) %>`

## Impact
- Dashboard show page now renders correctly without syntax errors
- All visualization types (table, count, pie_chart, bar_chart, line_chart) display properly
- ERB template follows Ruby syntax rules

## Related Files
- `app/controllers/dashboard_widgets_controller.rb` - Controller that renders this view
- `app/services/dashboard_data_generator.rb` - Service that generates the data for visualization

## Date
November 21, 2025
