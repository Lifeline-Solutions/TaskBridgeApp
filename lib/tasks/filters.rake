namespace :filters do
  desc 'Test the new DefectQueryBuilder with sample data'
  task test_query_builder: :environment do
    puts "\n========== Testing DefectQueryBuilder ==========\n\n"

    # Test 1: Legacy format (backward compatibility)
    puts 'Test 1: Legacy Format'
    puts '-' * 50
    legacy_filters = {
      'status' => ['Open', 'In Progress'],
      'priority' => 'High'
    }

    builder = DefectQueryBuilder.new(Defect.all)
    result = builder.apply_rules(legacy_filters)
    puts "SQL: #{result.to_sql}"
    puts "Count: #{result.count}"
    puts "✓ Legacy format works\n\n"

    # Test 2: New format with AND conditions
    puts 'Test 2: New Format (AND)'
    puts '-' * 50
    and_rules = {
      'operator' => 'AND',
      'conditions' => [
        { 'field' => 'status', 'operator' => 'IN', 'value' => ['Open', 'In Progress'] },
        { 'field' => 'priority', 'operator' => '=', 'value' => 'High' }
      ]
    }

    builder2 = DefectQueryBuilder.new(Defect.all)
    result2 = builder2.apply_rules(and_rules)
    puts "SQL: #{result2.to_sql}"
    puts "Count: #{result2.count}"
    puts "✓ New AND format works\n\n"

    # Test 3: New format with OR conditions
    puts 'Test 3: New Format (OR)'
    puts '-' * 50
    or_rules = {
      'operator' => 'OR',
      'conditions' => [
        { 'field' => 'priority', 'operator' => '=', 'value' => 'High' },
        { 'field' => 'priority', 'operator' => '=', 'value' => 'Critical' }
      ]
    }

    builder3 = DefectQueryBuilder.new(Defect.all)
    result3 = builder3.apply_rules(or_rules)
    puts "SQL: #{result3.to_sql}"
    puts "Count: #{result3.count}"
    puts "✓ New OR format works\n\n"

    # Test 4: Nested conditions (Status = Open OR In Progress) AND Priority = High
    puts 'Test 4: Nested Conditions'
    puts '-' * 50
    nested_rules = {
      'operator' => 'AND',
      'conditions' => [
        {
          'operator' => 'OR',
          'conditions' => [
            { 'field' => 'status', 'operator' => 'IN', 'value' => ['Open'] },
            { 'field' => 'status', 'operator' => 'IN', 'value' => ['In Progress'] }
          ]
        },
        { 'field' => 'priority', 'operator' => '=', 'value' => 'High' }
      ]
    }

    builder4 = DefectQueryBuilder.new(Defect.all)
    result4 = builder4.apply_rules(nested_rules)
    puts "SQL: #{result4.to_sql}"
    puts "Count: #{result4.count}"
    puts "✓ Nested format works\n\n"

    # Test 5: FilterAugmentor - merge saved filter with params
    puts 'Test 5: FilterAugmentor'
    puts '-' * 50
    saved_filter = DefectFilter.defect_filters.first
    if saved_filter
      params = { 'priority' => 'High' }
      merged = FilterAugmentor.merge(saved_filter, params)
      puts "Saved filter: #{saved_filter.filters.inspect}"
      puts "Params: #{params.inspect}"
      puts "Merged: #{merged.inspect}"

      builder5 = DefectQueryBuilder.new(Defect.all)
      result5 = builder5.apply_rules(merged)
      puts "Count: #{result5.count}"
      puts "✓ Filter augmentation works\n\n"
    else
      puts "No saved filters found - skipping test\n\n"
    end

    puts "========== All Tests Complete! ==========\n"
  end

  desc 'Migrate existing filters to new format'
  task migrate_to_filter_rules: :environment do
    puts "\n========== Migrating Filters to New Format ==========\n\n"

    DefectFilter.defect_filters.where(filter_rules: {}).or(DefectFilter.where(filter_rules: nil)).find_each do |filter|
      next if filter.filters.blank?

      print "Migrating '#{filter.name}'... "
      filter.migrate_to_filter_rules!
      puts '✓'
    end

    puts "\n========== Migration Complete! ==========\n"
  end
end
