# repro_dashboard.rb

# Find the filter
filter = DefectFilter.find_by(name: 'New ERP 2')

if filter.nil?
  puts "Filter 'New ERP 2' not found!"
  exit
end

puts "=== Filter Info ==="
puts "ID: #{filter.id}"
puts "Name: #{filter.name}"
puts "Product ID (column): #{filter.product_id}"
puts "Filters (jsonb): #{filter.filters}"
puts "Filter Rules (jsonb): #{filter.filter_rules}"
puts "Active Rules: #{filter.active_rules}"
puts "Sanitized Filters: #{filter.sanitized_filters}"

# Find the dashboard
dashboard = Dashboard.find_by(defect_filter_id: filter.id)

if dashboard.nil?
  puts "Dashboard using this filter not found!"
  # Try to find any dashboard to simulate
  dashboard = Dashboard.new(defect_filter: filter)
  puts "Created temporary dashboard for simulation"
else
  puts "=== Dashboard Info ==="
  puts "ID: #{dashboard.id}"
  puts "Name: #{dashboard.name}"
end

# Simulate QaDashboardsController logic
selected_product_ids = [] # Simulate no selection from dropdown

product_ids_to_filter = if selected_product_ids.any?
                          selected_product_ids
                        elsif dashboard.defect_filter.product_id.present?
                          [dashboard.defect_filter.product_id]
                        else
                          []
                        end

puts "Product IDs to filter: #{product_ids_to_filter.inspect}"

# Simulate DashboardDataGenerator logic
generator = DashboardDataGenerator.new(dashboard, product_ids: product_ids_to_filter)
result = generator.generate

puts "=== Results ==="
puts "Defects Count: #{result[:total_count]}"
puts "Charts: #{result[:charts].keys}"

# Debug SQL
defects = dashboard.filtered_defects
defects = defects.where(product_id: product_ids_to_filter) if product_ids_to_filter.any?
puts "SQL: #{defects.to_sql}"

# Check if any defects exist at all for this product (if product_id is involved)
if filter.product_id
  count = Defect.where(product_id: filter.product_id).count
  puts "Total defects for Product ID #{filter.product_id}: #{count}"
  published_count = Defect.published.where(product_id: filter.product_id).count
  puts "Published defects for Product ID #{filter.product_id}: #{published_count}"
end

# Check if any defects match the filter rules WITHOUT the extra product filter
base_filtered = dashboard.filtered_defects
puts "Base filtered count (without extra product filter): #{base_filtered.count}"
puts "Base filtered SQL: #{base_filtered.to_sql}"

# Check modules
if filter.filters['qa_module_id'].present?
  module_ids = filter.filters['qa_module_id']
  puts "Filter has #{module_ids.count} modules."
  
  # Check how many of these modules belong to the product
  if filter.product_id
    valid_modules = QaModule.where(id: module_ids, product_id: filter.product_id).count
    puts "Modules belonging to product #{filter.product_id}: #{valid_modules}"
    
    invalid_modules = QaModule.where(id: module_ids).where.not(product_id: filter.product_id).count
    puts "Modules belonging to OTHER products: #{invalid_modules}"

    # Check for submodules
    submodule_ids = QaModule.where(parent_id: module_ids).pluck(:id)
    puts "Submodules found: #{submodule_ids.count}"
    
    all_module_ids = module_ids + submodule_ids
    puts "Total module IDs (parents + submodules): #{all_module_ids.count}"
    
    # Try filtering with expanded modules
    expanded_filtered = dashboard.filtered_defects.unscope(where: :qa_module_id)
    expanded_filtered = expanded_filtered.where(qa_module_id: all_module_ids)
    # Re-apply other filters manually if needed, but let's just see if this simple change fixes it
    # We need to re-construct the query because filtered_defects already applied the narrow filter
    
    # Let's use DefectQueryBuilder manually with modified rules
    rules = filter.active_rules.dup
    rules['qa_module_id'] = all_module_ids
    
    builder = DefectQueryBuilder.new(Defect.published)
    expanded_result = builder.apply_rules(rules)
    
    # Apply product filter
    if filter.product_id
       expanded_result = expanded_result.where(product_id: filter.product_id)
    end
    
    puts "Expanded filtered count: #{expanded_result.count}"
    
    # Check individual filters
    base = Defect.published.where(product_id: filter.product_id)
    puts "Base (Product only): #{base.count}"
    
    if filter.active_rules['qa_module_id'].present?
      count = base.where(qa_module_id: all_module_ids).count
      puts "After Module filter (expanded): #{count}"
    end
    
    if filter.active_rules['status'].present?
      count = base.joins(:statuses).where(statuses: { name: filter.active_rules['status'] }).count
      puts "After Status filter: #{count}"
    end
    
    if filter.active_rules['priority'].present?
      count = base.where(priority: filter.active_rules['priority']).count
      puts "After Priority filter: #{count}"
    end
    
    if filter.active_rules['user_id'].present?
      count = base.joins(:users).where(users: { id: filter.active_rules['user_id'] }).count
      puts "After User filter: #{count}"
    end
    
    if filter.active_rules['label_ids'].present?
      count = base.joins(:labels).where(labels: { id: filter.active_rules['label_ids'] }).count
      puts "After Label filter: #{count}"
    end
    
    if filter.active_rules['reporter_id'].present?
      count = base.where(created_by: filter.active_rules['reporter_id']).count
      puts "After Reporter filter: #{count}"
    end
    
    # Check actual priority values
    priorities = base.distinct.pluck(:priority)
    puts "Actual priorities in DB: #{priorities.inspect}"
  end
end
