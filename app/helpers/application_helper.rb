module ApplicationHelper
  def cancel_redirect_path
    referer = request.referer || root_path
    referer.gsub(%r{/comments/new$}, '') # Removes '/comments/new' from the referer URL
  end

  def flash_class(level)
    case level.to_sym
    when :notice then 'blue'
    when :alert then 'red'
    when :success then 'green'
    else 'gray'
    end
  end

  def greeting_message
    current_hour = Time.zone.now.hour

    case current_hour
    when 0..11
      'Good Morning'
    when 12..17
      'Good Afternoon'
    else
      'Good Evening'
    end
  end

  def previewable?(attachment)
    attachment.content_type.start_with?('image/')
  end

  def full_title(page_title = '')
    base_title = 'Taskbridge'

    if page_title.empty?
      base_title
    else
      "#{base_title} | #{page_title}"
    end
  end

  def status_badge_class(status)
    case status&.to_s&.downcase
    when 'failed', 'failed qa'
      'bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-400'
    when 'passed', 'resolved', 'closed'
      'bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-400'
    when 'in progress', 'qa testing', 'work in progress'
      'bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-400'
    when 'on-hold', 'awaiting build'
      'bg-yellow-100 text-yellow-800 dark:bg-yellow-900/30 dark:text-yellow-400'
    when 'reopened'
      'bg-orange-100 text-orange-800 dark:bg-orange-900/30 dark:text-orange-400'
    when 'to do', 'todo'
      'bg-purple-100 text-purple-800 dark:bg-purple-900/30 dark:text-purple-400'
    else
      'bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300'
    end
  end

  def priority_badge_class(priority)
    case priority&.to_s&.downcase
    when 'severity 1', 'critical', 'high'
      'bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-400'
    when 'severity 2', 'medium'
      'bg-orange-100 text-orange-800 dark:bg-orange-900/30 dark:text-orange-400'
    when 'severity 3', 'low'
      'bg-yellow-100 text-yellow-800 dark:bg-yellow-900/30 dark:text-yellow-400'
    when 'severity 4', 'minor'
      'bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-400'
    else
      'bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300'
    end
  end
end
