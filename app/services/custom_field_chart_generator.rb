# CustomFieldChartGenerator - Generates distribution charts for any custom field selected by user
#
# Usage:
#   defects = Defect.where(product_id: 1)
#   generator = CustomFieldChartGenerator.new(defects)
#   status_chart = generator.generate_chart('status')
#   reporter_chart = generator.generate_chart('reporter')
#
class CustomFieldChartGenerator
  attr_reader :defects

  def initialize(defects)
    @defects = defects
  end

  # Main entry point - generates chart for a specific field
  def generate_chart(field)
    case field
    when 'status'
      generate_status_chart
    when 'priority'
      generate_priority_chart
    when 'assignee'
      generate_assignee_chart
    when 'reporter'
      generate_reporter_chart
    when 'qa_module'
      generate_module_chart
    when 'submodule'
      generate_submodule_chart
    when 'banking_type'
      generate_banking_type_chart
    when 'label'
      generate_label_chart

    else
      {}
    end
  end

  private

  # Status distribution
  def generate_status_chart
    defects
      .reorder(nil)
      .joins(:statuses)
      .group('statuses.name')
      .count
  end

  # Priority distribution
  def generate_priority_chart
    raw_counts = defects.reorder(nil).group(:priority).count

    # Normalize priority strings
    normalized = {}
    raw_counts.each do |priority, count|
      normalized_priority = normalize_priority(priority)
      normalized[normalized_priority] = (normalized[normalized_priority] || 0) + count
    end

    # Sort by severity
    normalized.sort_by { |k, _v| priority_sort_order(k) }.to_h
  end

  # Assignee distribution
  def generate_assignee_chart
    results = defects
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

  # Reporter distribution
  def generate_reporter_chart
    results = defects
      .reorder(nil)
      .joins('INNER JOIN users AS reporters ON reporters.id = defects.created_by')
      .group('reporters.id', 'reporters.first_name', 'reporters.last_name')
      .count

    formatted = {}
    results.each do |(_user_id, first_name, last_name), count|
      formatted["#{first_name} #{last_name}"] = count
    end
    formatted
  end

  # QA Module distribution
  def generate_module_chart
    defects
      .reorder(nil)
      .joins(:qa_module)
      .group('qa_modules.id', 'qa_modules.name')
      .count
      .transform_keys { |(_id, name)| name }
  end

  # Sub-module distribution
  def generate_submodule_chart
    # Group by submodule_id to avoid table aliasing issues with joins
    counts = defects
      .reorder(nil)
      .where.not(submodule_id: nil)
      .group(:submodule_id)
      .count

    # Fetch submodule names efficiently
    submodule_names = QaModule.where(id: counts.keys).pluck(:id, :name).to_h

    # Transform keys from ID to Name
    counts.transform_keys { |id| submodule_names[id] || 'Unknown' }
  end

  # Banking Type distribution
  def generate_banking_type_chart
    defects
      .reorder(nil)
      .joins(:banking_type)
      .group('banking_types.id', 'banking_types.name')
      .count
      .transform_keys { |(_id, name)| name }
  end

  # Label distribution
  def generate_label_chart
    defects
      .reorder(nil)
      .joins(:labels)
      .group('labels.id', 'labels.name')
      .count
      .transform_keys { |(_id, name)| name }
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
