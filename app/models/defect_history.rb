class DefectHistory < ApplicationRecord
  belongs_to :defect
  belongs_to :user

  # Parse the history text to extract old and new values
  # Expected format: "Status changed from Open to Closed"
  def old_value
    return nil unless history.present?

    # Match pattern: "something from X to Y"
    match = history.match(/from (.+?) to (.+?)(?:\s+(?:by|at)|$)/i)
    match[1].strip if match
  end

  def new_value
    return nil unless history.present?

    # Match pattern: "something from X to Y"
    match = history.match(/from (.+?) to (.+?)(?:\s+(?:by|at)|$)/i)
    match[2].strip if match
  end

  def field_changed
    return nil unless history_type.present?

    # Extract the field name from history_type
    # e.g., "Status Changed" -> "Status"
    #       "Assigned to" -> "Assignee"
    case history_type.downcase
    when /status/i
      'Status'
    when /assign/i
      'Assignee'
    when /priority/i
      'Priority'
    else
      history_type.gsub(/\s+(changed|updated|to|from)/i, '').strip
    end
  end
end
