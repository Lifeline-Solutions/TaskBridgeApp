# frozen_string_literal: true

# WidgetDataGenerator - Generates chart data for Dashboard Widgets
#
# CRITICAL: Uses SQL GROUP BY for performance - does NOT load defects into memory
#
# Usage:
#   generator = WidgetDataGenerator.new(dashboard_widget)
#   data = generator.generate
#   # => { "High" => 5, "Medium" => 3, "Low" => 1 }
#
class WidgetDataGenerator
  attr_reader :widget

  def initialize(widget)
    @widget = widget
  end

  # Main entry point - generates the dataset
  # Returns hash with label => count
  def generate
    base_relation = widget.filtered_defects

    case widget.group_by_field
    when 'priority'
      generate_priority_data(base_relation)
    when 'status'
      generate_status_data(base_relation)
    when 'assignee'
      generate_assignee_data(base_relation)
    when 'reporter'
      generate_reporter_data(base_relation)
    when 'qa_module'
      generate_module_data(base_relation)
    when 'submodule'
      generate_submodule_data(base_relation)
    when 'banking_type'
      generate_banking_type_data(base_relation)
    when 'label'
      generate_label_data(base_relation)
    when 'ageing'
      generate_ageing_data(base_relation)
    else
      {}
    end
  end

  private

  # Priority (Enum-aware) - handles both string and integer values
  def generate_priority_data(relation)
    # Use SQL GROUP BY - no Ruby objects loaded
    raw_counts = relation.group(:priority).count

    # Normalize priority strings
    normalized = {}
    raw_counts.each do |priority, count|
      normalized_priority = normalize_priority(priority)
      normalized[normalized_priority] = (normalized[normalized_priority] || 0) + count
    end

    # Sort by severity (Severity 1 first)
    normalized.sort_by { |k, _v| priority_sort_order(k) }.to_h
  end

  # Status - handles join correctly
  def generate_status_data(relation)
    # GOOD: Single SQL query with GROUP BY
    relation
      .joins(:statuses)
      .group('statuses.name')
      .count
  end

  # Assignee - handles user join correctly
  def generate_assignee_data(relation)
    # Use explicit join and GROUP BY to avoid N+1
    results = relation
      .joins('INNER JOIN defects_users ON defects_users.defect_id = defects.id')
      .joins('INNER JOIN users AS assignees ON assignees.id = defects_users.user_id')
      .group('assignees.id', 'assignees.first_name', 'assignees.last_name')
      .count

    # Convert to label => count
    formatted = {}
    results.each do |(_user_id, first_name, last_name), count|
      formatted["#{first_name} #{last_name}"] = count
    end
    formatted
  end

  # Reporter (Creator) - handles user join correctly
  def generate_reporter_data(relation)
    # Use explicit join and GROUP BY
    results = relation
      .joins('INNER JOIN users AS creators ON creators.id = defects.created_by')
      .group('creators.id', 'creators.first_name', 'creators.last_name')
      .count

    # Convert to label => count
    formatted = {}
    results.each do |(_user_id, first_name, last_name), count|
      formatted["#{first_name} #{last_name}"] = count
    end
    formatted
  end

  # Module - handles join correctly
  def generate_module_data(relation)
    relation
      .joins(:qa_module)
      .group('qa_modules.id', 'qa_modules.name')
      .count
      .transform_keys { |(_id, name)| name }
  end

  # Submodule - handles optional join correctly
  def generate_submodule_data(relation)
    relation
      .joins('LEFT JOIN qa_modules submods ON submods.id = defects.submodule_id')
      .where.not('submods.id' => nil)
      .group('submods.id', 'submods.name')
      .count
      .transform_keys { |(_id, name)| name }
  end

  # Banking Type - handles join correctly
  def generate_banking_type_data(relation)
    relation
      .joins(:banking_type)
      .group('banking_types.id', 'banking_types.name')
      .count
      .transform_keys { |(_id, name)| name }
  end

  # Label - handles many-to-many join correctly
  def generate_label_data(relation)
    relation
      .joins(:labels)
      .group('labels.id', 'labels.name')
      .count
      .transform_keys { |(_id, name)| name }
  end

  # Ageing - uses SQL CASE statement for bucketing
  def generate_ageing_data(relation)
    # GOOD: SQL-based bucketing, not Ruby
    buckets = relation.group(<<~SQL.squish).count
      CASE
        WHEN defects.created_at >= NOW() - INTERVAL '7 days' THEN '0-7 days'
        WHEN defects.created_at >= NOW() - INTERVAL '14 days' THEN '8-14 days'
        WHEN defects.created_at >= NOW() - INTERVAL '30 days' THEN '15-30 days'
        ELSE '31+ days'
      END
    SQL

    # Return in consistent order
    ordered_buckets = {}
    ['0-7 days', '8-14 days', '15-30 days', '31+ days'].each do |bucket|
      ordered_buckets[bucket] = buckets[bucket] || 0
    end
    ordered_buckets
  end

  # Normalize priority string (handles variations)
  def normalize_priority(priority)
    return 'Unknown' if priority.blank?

    p = priority.to_s.strip.downcase
    case p
    when 'severity 1', 's1', 'high', '1'
      'Severity 1'
    when 'severity 2', 's2', 'medium', '2'
      'Severity 2'
    when 'severity 3', 's3', 'low', '3'
      'Severity 3'
    when 'severity 4', 's4', 'very low', '4'
      'Severity 4'
    else
      priority.to_s.titleize
    end
  end

  # Sort order for priorities (Severity 1 is most important)
  def priority_sort_order(priority)
    case priority
    when 'Severity 1' then 1
    when 'Severity 2' then 2
    when 'Severity 3' then 3
    when 'Severity 4' then 4
    when 'Unknown' then 99
    else 50
    end
  end
end
