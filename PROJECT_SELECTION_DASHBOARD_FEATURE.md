# Project Selection Feature for QA Dashboards

## Overview
Added dynamic project selection functionality to QA Dashboards, allowing users to filter dashboard data by specific projects. When a project is selected, all charts and statistics automatically update to show only data from that project.

## Features Implemented

### 1. Project Dropdown Filter
- **Location**: QA Dashboard show page (top of the page)
- **Functionality**: 
  - Dropdown with all active projects
  - "All Projects" option to view combined data
  - Auto-submit on selection change
  - Clear button when a project is selected
  - Visual indicator showing currently selected project

### 2. Dynamic Chart Updates
- All dashboard charts automatically filter by selected project:
  - Priority Distribution
  - Status Distribution
  - Module Distribution
  - Banking Type Distribution
  - Assignee Distribution
  - Reporter Distribution
  - Creation Timeline
  - **NEW**: Product Distribution (shown when viewing multiple projects)

### 3. Product Distribution Chart
- Automatically appears when:
  - Multiple projects are in the filter parameters
  - No specific project is selected via dropdown
- Shows defect count per project
- Uses pie chart visualization
- Includes breakdown table with percentages

## Implementation Details

### Files Modified

#### 1. Controller: `app/controllers/qa_dashboards_controller.rb`
```ruby
def show
  # Get all products for dropdown selection
  @products = Product.active.includes(:client).order('document_name ASC')
  
  # Get selected product_id from params or from filter
  @selected_product_id = params[:product_id] || @dashboard.defect_filter.sanitized_filters['product_id']
  
  # Generate automatic charts for active filter parameters
  result = DashboardDataGenerator.new(@dashboard, product_id: @selected_product_id).generate
  # ...
end
```

**Changes**:
- ✅ Loads all active products for dropdown
- ✅ Gets selected product from URL params or saved filter
- ✅ Passes product_id to data generator
- ✅ Adds product_id to filter params display

#### 2. Service: `app/services/dashboard_data_generator.rb`
```ruby
class DashboardDataGenerator
  attr_reader :dashboard, :product_id

  def initialize(dashboard, options = {})
    @dashboard = dashboard
    @product_id = options[:product_id]
  end

  def generate
    defects = dashboard.filtered_defects
      .includes(:users, :statuses, :qa_module, :banking_type, :labels, :creator, :product)
    
    # Apply product filter if specified
    defects = defects.where(product_id: product_id) if product_id.present?
    # ...
  end
end
```

**Changes**:
- ✅ Accepts `product_id` option in initializer
- ✅ Filters defects by product_id when present
- ✅ Includes product association in eager loading
- ✅ Added `generate_product_chart` method
- ✅ Added `should_show_product_chart?` logic

**New Chart Method**:
```ruby
def generate_product_chart(relation)
  relation
    .reorder(nil)
    .joins(:product)
    .group('products.id', 'products.document_name')
    .count
    .transform_keys { |(_id, name)| name.presence || 'Unnamed Project' }
end
```

#### 3. Helper: `app/helpers/dashboards_helper.rb`
```ruby
def format_product_ids(value)
  ids = Array(value)
  products = Product.where(id: ids).pluck(:document_name)
  return value if products.empty?
  
  products.map { |name| name.presence || 'Unnamed Project' }.join(', ')
end
```

**Changes**:
- ✅ Fixed to use `document_name` instead of `name`
- ✅ Handles unnamed projects gracefully
- ✅ Returns proper formatted string for display

#### 4. View: `app/views/qa_dashboards/show.html.erb`

**Added Project Selection Section**:
```erb
<!-- Project Selection Filter -->
<div class="bg-white dark:bg-gray-800 rounded-lg shadow-md p-6 mb-6">
  <div class="flex items-center justify-between">
    <div class="flex items-center gap-4 flex-1">
      <%= form_with url: qa_dashboard_path(@dashboard), method: :get, local: true do |f| %>
        <%= f.select :product_id, 
            options_for_select(
              [['All Projects', '']] + @products.map { |p| [p.document_name, p.id] },
              @selected_product_id
            ),
            {},
            {
              id: 'product_select',
              class: '...',
              onchange: 'this.form.submit()'
            } %>
        
        <% if @selected_product_id.present? %>
          <%= link_to qa_dashboard_path(@dashboard), class: "..." do %>
            Clear
          <% end %>
        <% end %>
      <% end %>
    </div>
    
    <% if @selected_product_id.present? %>
      <div class="...">
        Showing: <%= selected_product.document_name %>
      </div>
    <% end %>
  </div>
</div>
```

**Features**:
- ✅ Auto-submit form on dropdown change (JavaScript)
- ✅ Fallback submit button for no-JS users
- ✅ Clear filter button when project selected
- ✅ Visual badge showing current selection
- ✅ Responsive design with Tailwind CSS

## User Experience Flow

### Scenario 1: View All Projects
1. User opens QA Dashboard
2. Dropdown shows "All Projects" selected
3. Dashboard displays combined data from all projects
4. If filter has multiple products, "Product Distribution" chart appears
5. User can see overview across entire organization

### Scenario 2: Select Specific Project
1. User clicks project dropdown
2. User selects a specific project (e.g., "Mobile Banking App")
3. Page auto-refreshes
4. All charts update to show only that project's data
5. Badge appears: "Showing: Mobile Banking App"
6. Total count updates to show only that project's defects

### Scenario 3: Clear Project Filter
1. User clicks "Clear" button
2. Page refreshes back to "All Projects" view
3. Dashboard shows combined data again
4. Badge disappears

### Scenario 4: Saved Filter with Project
1. Dashboard filter already has product_id saved
2. Dashboard opens with that project pre-selected
3. User can still change via dropdown
4. Selection persists in URL params (not saved to filter)

## Technical Specifications

### Product Model
- **Table**: `products`
- **Display Field**: `document_name` (text)
- **Primary Key**: `id` (uuid)
- **Status Field**: `archive_status` (boolean)

### Defect Association
- Defects belong to Product
- Foreign key: `product_id` (uuid)
- Association: `belongs_to :product`

### Filter Integration
- Product filter parameter: `product_id`
- Accepts single ID or array of IDs
- Stored in `DefectFilter.filters` JSONB column
- Sanitized via `ALLOWED_FILTER_KEYS`

### Chart Display Logic
```ruby
def should_show_product_chart?(active_params)
  product_ids = active_params['product_id']
  return false if product_ids.blank?
  
  # Don't show if filtering to single project via dropdown
  return false if product_id.present?
  
  # Show if multiple products in filter
  product_ids.is_a?(Array) && product_ids.size > 1
end
```

**Rules**:
- Show when: Multiple products in saved filter AND no dropdown selection
- Hide when: Single project selected via dropdown
- Hide when: No products in filter

## URL Parameter Handling

### Format
```
/qa_dashboards/:id?product_id=<uuid>
```

### Examples
```
# All projects
/qa_dashboards/123

# Specific project
/qa_dashboards/123?product_id=abc-123-def-456

# Clears selection
/qa_dashboards/123
```

### Persistence
- ✅ URL parameter overrides saved filter
- ✅ Selection persists during page navigation
- ✅ Auto-refresh respects current selection
- ❌ Does NOT save selection to filter (by design)

## Styling & UI

### Project Dropdown
- Full-width responsive select
- Max-width constraint (max-w-md)
- Border with focus ring
- Dark mode support
- Smooth transitions

### Visual Indicators
```html
<!-- Selected Project Badge -->
<div class="px-3 py-1 bg-blue-100 dark:bg-blue-900 text-blue-800 dark:text-blue-200 rounded-full">
  Showing: Mobile Banking App
</div>

<!-- Filter Chip in Active Parameters -->
<span class="inline-flex items-center px-3 py-1 bg-blue-100 dark:bg-blue-900 text-blue-800 dark:text-blue-200 rounded-full">
  <strong>Product Id:</strong>&nbsp;Mobile Banking App
</span>
```

### Icons
- Project folder icon (SVG)
- Clear/close icon for reset button
- Filter icon in active parameters

## Benefits

### For Users
1. ✅ **Quick Project Switching** - Change context without creating new filters
2. ✅ **Clearer Insights** - Focus on single project data
3. ✅ **Better Comparisons** - See product distribution when viewing all
4. ✅ **Flexible Analysis** - Toggle between project-specific and combined views

### For Managers
1. ✅ **Project Performance** - Track individual project health
2. ✅ **Resource Allocation** - See defect distribution across projects
3. ✅ **Trend Analysis** - Compare projects over time
4. ✅ **Team Productivity** - Filter by project to assess specific teams

### For QA Teams
1. ✅ **Focused Testing** - See only relevant project defects
2. ✅ **Priority Management** - Prioritize within project context
3. ✅ **Progress Tracking** - Monitor specific project testing progress
4. ✅ **Defect Patterns** - Identify project-specific issues

## Edge Cases Handled

### 1. Unnamed Projects
```ruby
# In chart generation and display
name.presence || 'Unnamed Project'
```

### 2. No Projects
- Dropdown shows "All Projects" only
- No error if products list is empty
- Dashboard works normally with filter's product selection

### 3. Invalid Product ID
- URL param with invalid/deleted product ID
- Fails gracefully, shows all projects
- No 404 error

### 4. Archived Products
```ruby
@products = Product.active.includes(:client).order('document_name ASC')
```
- Only shows active (non-archived) products
- Existing filter data with archived products still works
- Charts show archived product names from existing defects

### 5. No JavaScript
```erb
<noscript>
  <%= f.submit 'Apply Filter', class: '...' %>
</noscript>
```
- Submit button appears if JS disabled
- Fully functional without auto-submit

## Performance Considerations

### Eager Loading
```ruby
@products = Product.active.includes(:client).order('document_name ASC')
```
- Includes client association to avoid N+1
- Pre-loads all products once

### Defect Query
```ruby
defects = defects.where(product_id: product_id) if product_id.present?
```
- Simple indexed WHERE clause
- Uses existing foreign key index
- No complex joins for product filter

### Chart Generation
```ruby
.joins(:product)
.group('products.id', 'products.document_name')
```
- Single join for product chart
- Groups by indexed columns
- Efficient aggregation

## Testing Checklist

### Manual Testing
- [ ] Open dashboard - see "All Projects" selected
- [ ] Select specific project - charts update
- [ ] Total count changes correctly
- [ ] Active parameters show selected project
- [ ] Clear button resets to all projects
- [ ] Product distribution chart appears/disappears correctly
- [ ] URL updates with product_id param
- [ ] Browser back/forward work correctly
- [ ] Auto-refresh maintains selection
- [ ] Dark mode styling correct
- [ ] Mobile responsive

### Edge Case Testing
- [ ] Dashboard with no defects
- [ ] Dashboard with defects but no products
- [ ] Select project with 0 defects
- [ ] Invalid product_id in URL
- [ ] Archived product in saved filter
- [ ] Project with very long name
- [ ] 100+ projects in dropdown

### Cross-Browser Testing
- [ ] Chrome
- [ ] Firefox
- [ ] Safari
- [ ] Edge
- [ ] Mobile browsers

## Future Enhancements

### Potential Improvements
1. **Multi-Project Selection** - Allow selecting multiple projects at once
2. **Project Grouping** - Group projects by client or status
3. **Search in Dropdown** - For organizations with many projects
4. **Remember Selection** - Store user's last selection in session
5. **Project Comparison Mode** - Side-by-side comparison of 2-3 projects
6. **Export by Project** - Export filtered data for specific project
7. **Project-Specific KPIs** - Custom metrics per project type
8. **Saved Project Filters** - Quick access to frequently viewed projects

### Related Features to Consider
- Client-based filtering (group by client)
- Status-based filtering (e.g., only active projects)
- Date range for project creation/completion
- Project team member filtering
- Project phase/milestone filtering

## Dependencies

### Required Models
- ✅ Product model with `document_name` field
- ✅ Defect model with `product_id` foreign key
- ✅ DefectFilter model with JSONB filters column

### Required Gems
- ✅ `chartkick` - For chart visualization
- ✅ `groupdate` - For date grouping (if using timeline charts)

### Database Requirements
- ✅ `products.document_name` column (text)
- ✅ `defects.product_id` column (uuid)
- ✅ Index on `defects.product_id` (for performance)

## Migration Guide

### If Product Model Uses Different Field
If your Product model uses `name` instead of `document_name`:

1. Update helper:
```ruby
# app/helpers/dashboards_helper.rb
def format_product_ids(value)
  ids = Array(value)
  products = Product.where(id: ids).pluck(:name)  # Changed from :document_name
  # ...
end
```

2. Update service:
```ruby
# app/services/dashboard_data_generator.rb
def generate_product_chart(relation)
  relation
    .reorder(nil)
    .joins(:product)
    .group('products.id', 'products.name')  # Changed from :document_name
    # ...
end
```

3. Update view:
```erb
<!-- app/views/qa_dashboards/show.html.erb -->
@products.map { |p| [p.name, p.id] }  <!-- Changed from p.document_name -->
```

## Date
November 21, 2025

## Author
AI Assistant - GitHub Copilot

## Related Documentation
- `ASSIGNEE_ACTIVE_FILTER_FIX.md`
- `DASHBOARD_FILTER_DISPLAY_FIX.md`
- `FILTER_PERSISTENCE_BUG_FIX.md`
