# frozen_string_literal: true

# DashboardDataGenerator - Generates multiple chart visualizations based on active filter parameters
#
# Usage:
#   generator = DashboardDataGenerator.new(dashboard_widget)
#   result = generator.generate
#   # Returns: {
#   #   defects: <ActiveRecord::Relation>,
#   #   charts: {
#   #     'Priority Distribution' => { 'Severity 1' => 5, 'Severity 2' => 10, ... },
#   #     'Status Distribution' => { 'TODO' => 3, 'On-Hold' => 7, ... },
#   #     ...
#   #   },
#   #   total_count: 15
#   # }
#
class DashboardDataGenerator
  attr_reader :dashboard

  def initialize(dashboard)
    @dashboard = dashboard
  end

  # Main entry point - generates dashboard data with multiple charts
  def generate
    defects = dashboard.filtered_defects
                      .includes(:users, :statuses, :qa_module, :banking_type, :labels, :creator)
    
    {
      defects: defects,
      charts: generate_all_charts(defects),
      total_count: defects.count
    }
  end

  private

  # Generate charts for all active filter parameters
  def generate_all_charts(relation)
    active_params = dashboard.active_filter_parameters
    charts = {}

    # Generate chart for each active filter parameter
    charts['Priority Distribution'] = generate_priority_chart(relation) if should_show_priority_chart?(active_params)
    charts['Status Distribution'] = generate_status_chart(relation) if should_show_status_chart?(active_params)
    charts['Module Distribution'] = generate_module_chart(relation) if should_show_module_chart?(active_params)
    charts['Banking Type Distribution'] = generate_banking_type_chart(relation) if should_show_banking_type_chart?(active_params)
    charts['Assignee Distribution'] = generate_assignee_chart(relation) if should_show_assignee_chart?(active_params)
    charts['Creation Timeline'] = generate_timeline_chart(relation) if should_show_timeline_chart?(active_params)

    charts.compact
  end

  # Determine if we should show priority chart (if priority filter is active)
  def should_show_priority_chart?(active_params)
    active_params['priority'].present? || dashboard.defect_filter.filters.dig('priority').present?
  end

  # Determine if we should show status chart (if status filter is active)
  def should_show_status_chart?(active_params)
    active_params['status'].present? || dashboard.defect_filter.filters.dig('status').present?
  end

  # Determine if we should show module chart
  def should_show_module_chart?(active_params)
    active_params['qa_module_id'].present?
  end

  # Determine if we should show banking type chart
  def should_show_banking_type_chart?(active_params)
    active_params['banking_type_id'].present?
  end

  # Determine if we should show assignee chart
  def should_show_assignee_chart?(active_params)
    active_params['user_id'].present?
  end

  # Determine if we should show timeline chart
  def should_show_timeline_chart?(active_params)
    active_params['start_date'].present? || active_params['end_date'].present?
  end

  # Generate priority distribution chart (only showing selected priorities)
  def generate_priority_chart(relation)
    raw_counts = relation.reorder(nil).group(:priority).count
    
    # Normalize priority strings
    normalized = {}
    raw_counts.each do |priority, count|
      normalized_priority = normalize_priority(priority)
      normalized[normalized_priority] = (normalized[normalized_priority] || 0) + count
    end
    
    # Sort by severity
    normalized.sort_by { |k, _v| priority_sort_order(k) }.to_h
  end

  # Generate status distribution chart (only showing filtered statuses)
  def generate_status_chart(relation)
    relation
      .reorder(nil)
      .joins(:statuses)
      .group('statuses.name')
      .count
  end

  # Generate module distribution chart
  def generate_module_chart(relation)
    relation
      .reorder(nil)
      .joins(:qa_module)
      .group('qa_modules.id', 'qa_modules.name')
      .count
      .transform_keys { |(_id, name)| name }
  end

  # Generate banking type distribution chart
  def generate_banking_type_chart(relation)
    relation
      .reorder(nil)
      .joins(:banking_type)
      .group('banking_types.id', 'banking_types.name')
      .count
      .transform_keys { |(_id, name)| name }
  end

  # Generate assignee distribution chart
  def generate_assignee_chart(relation)
    results = relation
      .reorder(nil)
      .joins('INNER JOIN defects_users ON defects_users.defect_id = defects.id')
      .joins('INNER JOIN users AS assignees ON assignees.id = defects_users.user_id')
      .group('assignees.id', 'assignees.first_name', 'assignees.last_name')
      .count

    formatted = {}
    results.each do |(_user_id, first_name, last_name), count|
      formatted["#{first_name} #{last_name}"] = count
    end
    formatted
  end

  # Generate timeline chart based on date range filter
  def generate_timeline_chart(relation)
    # Group by creation date in weekly buckets
    buckets = relation.reorder(nil).group(<<~SQL.squish).count
      CASE
        WHEN defects.created_at >= NOW() - INTERVAL '7 days' THEN 'This Week'
        WHEN defects.created_at >= NOW() - INTERVAL '14 days' THEN 'Last Week'
        WHEN defects.created_at >= NOW() - INTERVAL '30 days' THEN 'This Month'
        ELSE 'Older'
      END
    SQL

    # Return in chronological order
    ordered_buckets = {}
    ['This Week', 'Last Week', 'This Month', 'Older'].each do |bucket|
      count = buckets[bucket] || 0
      ordered_buckets[bucket] = count if count > 0
    end
    ordered_buckets
  end

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

