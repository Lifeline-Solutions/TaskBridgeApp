module DashboardWidgetsHelper
  # Returns the FontAwesome icon name for a given visualization type
  # @param viz_type [Symbol, String] The visualization type (e.g., :pie_chart, 'bar_chart')
  # @return [String] FontAwesome icon name without the 'fa-' prefix
  def viz_icon(viz_type)
    case viz_type.to_s
    when 'pie_chart'
      'chart-pie'
    when 'bar_chart'
      'chart-bar'
    when 'line_chart'
      'chart-line'
    when 'count'
      'hashtag'
    when 'table'
      'table'
    else
      'chart-simple'
    end
  end

  # Returns a human-readable label for visualization types
  # @param viz_type [Symbol, String] The visualization type
  # @return [String] Human-readable label
  def viz_label(viz_type)
    case viz_type.to_s
    when 'pie_chart'
      'Pie Chart'
    when 'bar_chart'
      'Bar Chart'
    when 'line_chart'
      'Line Chart'
    when 'count'
      'Count'
    when 'table'
      'Table'
    else
      viz_type.to_s.humanize
    end
  end

  # Returns the color class for a visualization type
  # @param viz_type [Symbol, String] The visualization type
  # @return [String] Tailwind color classes
  def viz_color(viz_type)
    case viz_type.to_s
    when 'pie_chart'
      'text-purple-600 dark:text-purple-400'
    when 'bar_chart'
      'text-blue-600 dark:text-blue-400'
    when 'line_chart'
      'text-green-600 dark:text-green-400'
    when 'count'
      'text-orange-600 dark:text-orange-400'
    else
      'text-gray-600 dark:text-gray-400'
    end
  end

  # Formats filter values for display
  # @param value [Object] The filter value
  # @return [String] Formatted value
  def format_filter_value(value)
    case value
    when Array
      value.join(', ')
    when Hash
      value.to_json
    when Date, DateTime, Time
      value.strftime('%Y-%m-%d')
    else
      value.to_s
    end
  end

  # Returns badge class for priority
  # @param priority [String] The priority value
  # @return [String] Tailwind CSS classes
  def priority_badge_class(priority)
    case priority.to_s.downcase
    when 'severity 1', 's1', 'high', '1'
      'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200'
    when 'severity 2', 's2', 'medium', '2'
      'bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200'
    when 'severity 3', 's3', 'low', '3'
      'bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200'
    when 'severity 4', 's4', 'very low', '4'
      'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200'
    else
      'bg-gray-100 text-gray-800 dark:bg-gray-900 dark:text-gray-200'
    end
  end
end
