# DefectQueryBuilder - Query Object Pattern for applying complex filters to defects
#
# Usage:
#   builder = DefectQueryBuilder.new(Defect.all)
#   filtered = builder.apply_rules(filter_rules)
#
# Supports both:
# 1. New format: Complex nested AND/OR conditions
# 2. Legacy format: Simple key-value pairs (backward compatible)
#
class DefectQueryBuilder
  OPERATORS = {
    '=' => :eq,
    '!=' => :not_eq,
    'IN' => :in,
    'NOT IN' => :not_in,
    'LIKE' => :matches,
    'NOT LIKE' => :does_not_match,
    '>' => :gt,
    '>=' => :gteq,
    '<' => :lt,
    '<=' => :lteq,
    'IS NULL' => :eq,
    'IS NOT NULL' => :not_eq
  }.freeze

  # Maps filter field names to database table/column names
  FIELD_MAPPING = {
    'status' => { table: 'statuses', column: 'name', join: :statuses, case_insensitive: true },
    'priority' => { table: 'defects', column: 'priority', case_insensitive: true },
    'assignee_id' => { table: 'users', column: 'id', join: :users },
    'user_id' => { table: 'users', column: 'id', join: :users }, # Alias for assignee
    'reporter_id' => { table: 'defects', column: 'created_by' },
    'label_ids' => { table: 'labels', column: 'id', join: :labels },
    'qa_module_id' => { table: 'defects', column: 'qa_module_id' },
    'submodule_id' => { table: 'defects', column: 'submodule_id' },
    'banking_type_id' => { table: 'defects', column: 'banking_type_id' },
    'created_at' => { table: 'defects', column: 'created_at' },
    'updated_at' => { table: 'defects', column: 'updated_at' },
    'product_id' => { table: 'defects', column: 'product_id' }
  }.freeze

  def initialize(base_relation = Defect.all)
    @relation = base_relation
    @joins_needed = Set.new
  end

  # Main entry point - applies filter rules to the relation
  # @param rules [Hash] Filter rules in new or legacy format
  # @return [ActiveRecord::Relation]
  def apply_rules(rules)
    return @relation if rules.blank?

    # Detect format: new format has 'conditions' key
    if rules.is_a?(Hash) && (rules['conditions'] || rules[:conditions])
      apply_condition_group(rules.with_indifferent_access)
    else
      apply_legacy_filters(rules.with_indifferent_access)
    end

    apply_joins
    @relation.distinct
  end

  private

  # Apply a group of conditions with AND/OR operator
  def apply_condition_group(group)
    operator = group['operator'] || group[:operator] || 'AND'
    conditions = group['conditions'] || []

    return @relation if conditions.empty?

    # Process each condition and combine them
    arel_conditions = conditions.map do |condition|
      if condition['conditions'] || condition[:conditions]
        # Nested group
        apply_nested_group(condition)
      else
        # Single condition
        build_condition(condition)
      end
    end.compact

    return @relation if arel_conditions.empty?

    combined_condition = arel_conditions.reduce do |accum, condition|
      if operator.to_s.upcase == 'OR'
        accum.or(condition)
      else
        accum.and(condition)
      end
    end

    # Apply the combined condition to the relation
    @relation = @relation.where(combined_condition)
    
    @relation
  end

  def apply_nested_group(group)
    operator = group['operator'] || group[:operator] || 'AND'
    conditions = group['conditions'] || []

    sub_conditions = conditions.map do |condition|
      if condition['conditions'] || condition[:conditions]
        apply_nested_group(condition)
      else
        build_condition(condition.with_indifferent_access)
      end
    end.compact

    return nil if sub_conditions.empty?

    sub_conditions.reduce do |accum, condition|
      if operator.to_s.upcase == 'OR'
        accum.or(condition)
      else
        accum.and(condition)
      end
    end
  end

  # Build a single Arel condition
  def build_condition(condition)
    field = condition['field'] || condition[:field]
    operator = condition['operator'] || condition[:operator]
    value = condition['value'] || condition[:value]

    field_config = FIELD_MAPPING[field.to_s]
    return nil unless field_config

    # Track joins needed
    @joins_needed << field_config[:join] if field_config[:join]

    table = field_config[:table]
    column = field_config[:column]
    arel_table = Arel::Table.new(table)

    case operator.to_s.upcase
    when 'IN'
      if field_config[:case_insensitive]
        arel_table[column].lower.in(Array(value).map(&:to_s).map(&:downcase))
      else
        arel_table[column].in(Array(value))
      end
    when 'NOT IN'
      arel_table[column].not_in(Array(value))
    when 'IS NULL'
      arel_table[column].eq(nil)
    when 'IS NOT NULL'
      arel_table[column].not_eq(nil)
    when 'LIKE'
      arel_table[column].matches("%#{value}%")
    when 'NOT LIKE'
      arel_table[column].does_not_match("%#{value}%")
    when '>=', 'GTEQ'
      arel_table[column].gteq(parse_value(value, column))
    when '<=', 'LTEQ'
      arel_table[column].lteq(parse_value(value, column))
    when '>', 'GT'
      arel_table[column].gt(parse_value(value, column))
    when '<', 'LT'
      arel_table[column].lt(parse_value(value, column))
    when '!=', 'NOT_EQ'
      arel_table[column].not_eq(value)
    when '=', 'EQ'
      arel_table[column].eq(value)
    else
      # Default to equality
      arel_table[column].eq(value)
    end
  end

  # Apply legacy filters (backward compatible)
  def apply_legacy_filters(filters)
    filters.each do |key, value|
      next if value.blank?

      case key.to_s
      when 'status'
        @joins_needed << :statuses
        # Case-insensitive status match
        statuses = Array(value).map(&:downcase)
        @relation = @relation.where('LOWER(statuses.name) IN (?)', statuses)
      when 'priority'
        # Case-insensitive priority match
        priorities = Array(value).map(&:downcase)
        @relation = @relation.where('LOWER(defects.priority) IN (?)', priorities)
      when 'user_id', 'assignee_id'
        @joins_needed << :users
        @relation = @relation.where(users: { id: Array(value) })
      when 'reporter_id'
        @relation = @relation.where(created_by: Array(value))
      when 'label_ids'
        @joins_needed << :labels
        @relation = @relation.where(labels: { id: Array(value) })
      when 'qa_module_id'
        # Expand to include submodules (match DefectController behavior)
        module_ids = Array(value)
        submodule_ids = QaModule.where(parent_id: module_ids).pluck(:id)
        all_ids = (module_ids + submodule_ids).uniq
        @relation = @relation.where(qa_module_id: all_ids)
      when 'submodule_id'
        # Handle submodule filtering in conjunction with parent modules
        # This is handled by qa_module_id case above
      when 'banking_type_id'
        @relation = @relation.where(banking_type_id: Array(value))
      when 'product_id'
        @relation = @relation.where(product_id: Array(value))
      when 'start_date'
        @relation = @relation.where('defects.created_at >= ?', value.to_date.beginning_of_day)
      when 'end_date'
        @relation = @relation.where('defects.created_at <= ?', value.to_date.end_of_day)
      when 'query'
        @relation = @relation.where('defects.summary ILIKE :q OR defects.description ILIKE :q', q: "%#{value}%")
      when 'order'
        # Handle ordering separately
        direction = value.to_s.downcase == 'asc' ? :asc : :desc
        @relation = @relation.order(created_at: direction)
      end
    end

    @relation
  end

  # Apply all necessary joins with conflict prevention
  def apply_joins
    @joins_needed.uniq.each do |join|
      # Check if join is already applied to prevent duplicate joins
      join_tables = case join
      when :statuses then ['statuses']
      when :users then ['users', 'defects_users']
      when :labels then ['labels', 'defects_labels']
      else [join.to_s]
      end

      # Only apply join if not already present in the query
      unless join_already_applied?(join_tables)
        begin
          @relation = @relation.joins(join)
        rescue ActiveRecord::StatementInvalid => e
          # Handle cases where join table doesn't exist or association is missing
          Rails.logger.warn "Join #{join} failed: #{e.message}"
        end
      end
    end
  end

  # Check if a join is already applied to the relation
  def join_already_applied?(table_names)
    sql = @relation.to_sql.downcase
    table_names.any? { |table| sql.include?("join #{table}") || sql.include?("joins #{table}") }
  end

  # Parse value based on column type
  def parse_value(value, column)
    case column.to_s
    when 'created_at', 'updated_at'
      value.respond_to?(:to_datetime) ? value.to_datetime : value
    else
      value
    end
  end

  # Normalize priority values to handle case-insensitive matching
  def normalize_priorities(priorities)
    priorities.flat_map do |priority|
      case priority.to_s.strip.downcase
      when 'severity 1', 's1', 'high' then ['severity 1', 's1', 'high']
      when 'severity 2', 's2', 'medium' then ['severity 2', 's2', 'medium']
      when 'severity 3', 's3', 'low' then ['severity 3', 's3', 'low']
      when 'severity 4', 's4', 'very low' then ['severity 4', 's4', 'very low']
      else [priority.to_s.downcase]
      end
    end
  end

  # Apply module filtering with proper parent-child relationship handling
  def apply_module_filter(qa_module_ids, submodule_ids = nil)
    qa_module_ids = qa_module_ids.reject(&:blank?)
    submodule_ids = Array(submodule_ids).reject(&:blank?)

    return @relation if qa_module_ids.empty? && submodule_ids.empty?

    begin
      # Dynamically check if QaModule model exists to avoid errors in environments without this feature
      qa_module_class = Object.const_get('QaModule')

      if qa_module_ids.any? && submodule_ids.any?
        # Both parent modules and submodules selected - prefer submodules but fallback to parents
        submodule_relation = @relation.where(qa_module_id: submodule_ids)

        if submodule_relation.exists?
          @relation = submodule_relation
        else
          # Fallback to parent modules if no defects found in submodules
          @relation = @relation.where(qa_module_id: qa_module_ids)
        end
      elsif qa_module_ids.any?
        # Only parent modules selected - expand to include all their submodules
        parent_modules = qa_module_class.where(id: qa_module_ids)
        if parent_modules.any?
          child_module_ids = qa_module_class.where(parent_id: qa_module_ids).pluck(:id)
          all_module_ids = qa_module_ids + child_module_ids
          @relation = @relation.where(qa_module_id: all_module_ids)
        else
          @relation = @relation.where(qa_module_id: qa_module_ids)
        end
      elsif submodule_ids.any?
        # Only submodules selected
        @relation = @relation.where(qa_module_id: submodule_ids)
      end
    rescue NameError, ActiveRecord::StatementInvalid => e
      # QaModule doesn't exist or column doesn't exist - skip module filtering
      Rails.logger.warn "Module filtering not available: #{e.message}"
    end

    @relation
  end
end
