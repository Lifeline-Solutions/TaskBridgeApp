# frozen_string_literal: true

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
    'status' => { table: 'statuses', column: 'name', join: :statuses },
    'priority' => { table: 'defects', column: 'priority' },
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
    operator = (group['operator'] || group[:operator] || 'AND').upcase
    conditions = group['conditions'] || group[:conditions] || []

    return @relation if conditions.empty?

    # Build all conditions (may include nested groups)
    arel_conditions = conditions.map do |condition|
      if condition['conditions'] || condition[:conditions]
        # Nested group - build sub-query
        build_nested_group_condition(condition)
      else
        # Single condition
        build_condition(condition.with_indifferent_access)
      end
    end.compact

    return @relation if arel_conditions.empty?

    # Combine with AND or OR
    if operator == 'OR'
      combined = arel_conditions.reduce { |memo, cond| memo.or(cond) }
      @relation = @relation.where(combined)
    else
      arel_conditions.each { |condition| @relation = @relation.where(condition) }
    end

    @relation
  end

  def build_nested_group_condition(nested_group)
    # For nested groups, we need to build the conditions independently
    operator = (nested_group['operator'] || nested_group[:operator] || 'AND').upcase
    conditions = nested_group['conditions'] || nested_group[:conditions] || []

    sub_conditions = conditions.map do |condition|
      if condition['conditions'] || condition[:conditions]
        build_nested_group_condition(condition)
      else
        build_condition(condition.with_indifferent_access)
      end
    end.compact

    return nil if sub_conditions.empty?

    if operator == 'OR'
      sub_conditions.reduce { |memo, cond| memo.or(cond) }
    else
      # For AND, we'll combine them in the parent
      sub_conditions.reduce { |memo, cond| memo.and(cond) }
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
      arel_table[column].in(Array(value))
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
        @relation = @relation.where(statuses: { name: Array(value) })
      when 'priority'
        @relation = @relation.where(priority: Array(value))
      when 'user_id', 'assignee_id'
        @joins_needed << :users
        @relation = @relation.where(users: { id: Array(value) })
      when 'reporter_id'
        @relation = @relation.where(created_by: Array(value))
      when 'label_ids'
        @joins_needed << :labels
        @relation = @relation.where(labels: { id: Array(value) })
      when 'qa_module_id'
        @relation = @relation.where(qa_module_id: Array(value))
      when 'submodule_id'
        @relation = @relation.where(submodule_id: Array(value))
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

  # Apply all necessary joins
  def apply_joins
    @joins_needed.each do |join|
      @relation = @relation.joins(join)
    end
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
end
