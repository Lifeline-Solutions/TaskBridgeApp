# frozen_string_literal: true

class Widget < ApplicationRecord
  # Associations
  belongs_to :dashboard
  belongs_to :defect_filter, optional: true
  
  # Widget types
  WIDGET_TYPES = %w[chart table stat].freeze
  
  # Validations
  validates :widget_type, presence: true, inclusion: { in: WIDGET_TYPES }
  validates :title, presence: true, length: { maximum: 200 }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :width, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 4 }
  validates :height, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 4 }
  validates :dashboard, presence: true
  
  # Default values
  attribute :config, :jsonb, default: -> { {} }
  attribute :width, :integer, default: 1
  attribute :height, :integer, default: 1
  attribute :position, :integer, default: 0
  
  # Scopes
  default_scope { order(:position) }
  scope :charts, -> { where(widget_type: 'chart') }
  scope :tables, -> { where(widget_type: 'table') }
  scope :stats, -> { where(widget_type: 'stat') }
  
  # Callbacks
  before_create :set_position, unless: :position?
  after_touch :touch_dashboard
  
  # Execute the widget's filter query
  # @return [ActiveRecord::Relation]
  def execute_query
    return Defect.none if defect_filter.blank?
    
    base = Defect.published
      .includes(:users, :statuses, product: [:client, :groupwares])
    
    # Use the defect filter's apply_to method
    defect_filter.apply_to(base)
  end
  
  # Get cached data for this widget
  # @return [Array, Hash]
  def cached_data
    Rails.cache.fetch(cache_key_with_version, expires_in: cache_duration) do
      fetch_widget_data
    end
  end
  
  # Fetch fresh data (not cached)
  # @return [Array, Hash]
  def fetch_widget_data
    case widget_type
    when 'table'
      fetch_table_data
    when 'chart'
      fetch_chart_data
    when 'stat'
      fetch_stat_data
    else
      []
    end
  end
  
  # Clear cache for this widget
  def clear_cache
    Rails.cache.delete(cache_key_with_version)
  end
  
  # Get chart configuration
  def chart_config
    return {} unless widget_type == 'chart'
    
    config.with_indifferent_access.slice(
      :chart_type, :x_axis, :y_axis, :grouping, :colors
    )
  end
  
  # Get table configuration
  def table_config
    return {} unless widget_type == 'table'
    
    config.with_indifferent_access.slice(
      :columns, :sortable, :paginate, :page_size
    )
  end
  
  # Check if widget is a chart
  def chart?
    widget_type == 'chart'
  end
  
  # Check if widget is a table
  def table?
    widget_type == 'table'
  end
  
  # Check if widget is a stat
  def stat?
    widget_type == 'stat'
  end
  
  private
  
  def set_position
    max_position = dashboard.widgets.maximum(:position) || -1
    self.position = max_position + 1
  end
  
  def touch_dashboard
    dashboard.touch
  end
  
  def cache_duration
    (config['cache_duration'] || 5).minutes
  end
  
  def fetch_table_data
    query = execute_query
    limit = table_config[:page_size] || 10
    
    query.limit(limit).map do |defect|
      {
        id: defect.id,
        summary: defect.summary,
        status: defect.statuses.first&.name,
        priority: defect.priority,
        assignees: defect.users.map(&:full_name).join(', '),
        created_at: defect.created_at
      }
    end
  end
  
  def fetch_chart_data
    query = execute_query
    grouping = chart_config[:grouping] || 'status'
    
    case grouping
    when 'status'
      query.joins(:statuses)
        .group('statuses.name')
        .count
    when 'priority'
      query.group(:priority).count
    when 'assignee'
      query.joins(:users)
        .group('users.first_name', 'users.last_name')
        .count
        .transform_keys { |k| k.join(' ') }
    when 'created_date'
      query.group_by_day(:created_at).count
    else
      {}
    end
  end
  
  def fetch_stat_data
    {
      count: execute_query.count,
      title: title
    }
  end
end
