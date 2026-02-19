class Ticket < ApplicationRecord
  belongs_to :project
  belongs_to :user
  has_one_attached :ticket_image
  has_many_attached :attachments
  has_many :issues, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :notifications, dependent: :destroy # Notification model is not defined in the snippet
  has_rich_text :content
  has_one_attached :image
  belongs_to :software, optional: true
  belongs_to :groupware, optional: true
  has_many :ratings, dependent: :destroy
  validates :image, content_type: %w[image/png image/jpeg], size: { less_than: 5.megabytes }
  has_many :events, dependent: :destroy
  validates :unique_id, uniqueness: true
  before_update :track_updates
  before_create :set_default_status

  resourcify
  has_many :users, through: :roles, class_name: 'User', source: :users
  has_many :creators, -> { where(roles: { name: :creator }) }, class_name: 'User', through: :roles, source: :users
  has_many :editors, -> { where(roles: { name: :editor }) }, class_name: 'User', through: :roles, source: :users
  validate :content_length_within_limit
  validates :content, presence: true
  validates :unique_id, uniqueness: true

  has_many :taggings
  has_many :users, through: :taggings, dependent: :destroy

  has_many :add_statuses
  has_many :statuses, through: :add_statuses, dependent: :destroy

  has_many :sla_tickets, dependent: :destroy
  has_one :sla_ticket, dependent: :destroy

  has_many :ticket_feedbacks, dependent: :destroy
  has_many :feedbacks, class_name: 'TicketFeedback', dependent: :destroy

  # Search scopes for global search
  scope :search_by_query, lambda { |query|
    return none if query.blank?

    sanitized_query = "%#{query}%"

    left_joins(:rich_text_content)
      .where(
        'tickets.unique_id ILIKE :q
         OR tickets.subject ILIKE :q
         OR tickets.issue ILIKE :q
         OR tickets.priority ILIKE :q
         OR action_text_rich_texts.body ILIKE :q',
        q: sanitized_query
      )
      .distinct
  }

  scope :accessible_by_user, lambda { |user|
    return none unless user

    # Internal roles (Admin, Observer, QA, Agent, Project Manager) can see all tickets
    allowed_roles = ['admin', 'qa', 'agent', 'project manager', 'observer']
    user_roles = user.roles.map(&:name)
    return all if user_roles.intersect?(allowed_roles)

    # Regular users can see tickets if:
    # 1. They belong to the project (via assignees)
    # 2. They are the creator (user_id)
    # 3. They are tagged in the ticket
    left_joins(project: :assignees)
      .left_joins(:taggings)
      .where(
        'assignees.user_id = :user_id OR tickets.user_id = :user_id OR taggings.user_id = :user_id',
        user_id: user.id
      )
      .distinct
  }

  after_create :set_initial_response_time, :set_target_repair_deadline, :set_resolution_deadline, :ticket_unique_id
  attr_accessor :skip_sla_callbacks, :skip_history_logging

  after_update :set_target_repair_deadline, :set_resolution_deadline, :set_resolution_deadline, unless: :skip_callbacks
  def set_initial_response_time
    start_time = DateTime.now
    start_time = adjust_start_time(start_time)
    update_column(:initial_response_deadline, next_business_time(start_time, 30.minutes))
  end

  def set_target_repair_deadline
    start_time = initial_response_deadline
    start_time = adjust_start_time(start_time)

    case priority
    when 'SEVERITY 1'
      update_column(:target_repair_deadline, next_business_time(start_time, 3.hours))
    when 'SEVERITY 2'
      update_column(:target_repair_deadline, next_business_time(start_time, 5.hours))
    when 'SEVERITY 3'
      update_column(:target_repair_deadline, next_business_time(start_time, 12.hours))
    when 'SEVERITY 4'
      update_column(:target_repair_deadline, next_business_time(start_time, 24.hours))
    end
  end

  def set_resolution_deadline
    start_time = target_repair_deadline
    start_time = adjust_start_time(start_time)
    case priority
    when 'SEVERITY 1'
      deadline1 = next_business_time(start_time, 4.hours)
      update_columns(resolution_deadline: deadline1, due_date: deadline1)
    when 'SEVERITY 2'
      deadline2 = next_business_time(start_time, 8.hours)
      update_columns(resolution_deadline: deadline2, due_date: deadline2)
    when 'SEVERITY 3'
      deadline3 = next_business_time(start_time, 16.hours)
      update_columns(resolution_deadline: deadline3, due_date: deadline3)
    when 'SEVERITY 4'
      deadline4 = next_business_time(start_time, 24.hours)
      update_columns(resolution_deadline: deadline4, due_date: deadline4)
    end
  end

  def sla_status
    'Not Breached'
  end

  def sla_target_response_deadline
    return 'Not Breached' if sla_on_time?

    'Breached' if sla_breached?
  end

  def sla_resolution_deadline
    return 'Not Breached' if res_sla_on_time?

    'Breached' if res_sla_breached?
  end

  def self.daily_summary
    group('DATE(tickets.created_at)')
      .select(
        'DATE(tickets.created_at) AS date',
        'COUNT(tickets.id) AS new_additions',
        "SUM(CASE WHEN statuses.name NOT IN ('Closed', 'Resolved', 'Declined') THEN 1 ELSE 0 END) AS open_tickets",
        "SUM(CASE WHEN statuses.name = 'Closed' THEN 1 ELSE 0 END) AS closed",
        "SUM(CASE WHEN statuses.name = 'Resolved' THEN 1 ELSE 0 END) AS resolved",
        "SUM(CASE WHEN statuses.name IN ('On-Hold', 'Client Infromation Pending') THEN 1 ELSE 0 END) AS with_client"
      )
      .order('date ASC')
  end

  def progress_percentage
    # Example logic to calculate progress percentage
    status = statuses.first
    return 0 unless status # Return 0 if there is no status

    case status.name
    when 'Reopened'
      5
    when 'New'
      10
    when 'Assigned'
      30
    when 'On-Hold'
      40
    when 'Work in Progress', 'Under Development', 'Pending'
      50
    when 'QA Testing'
      60
    when 'Client Information Pending'
      70
    when 'Awaiting Build'
      80
    when 'Resolved', 'Closed', 'Declined', 'Approved'
      100
    else
      0
    end
  end

  def self.count_breached_sla
    joins(:sla_tickets).where(sla_tickets: { sla_status: 'Breached' }).count
  end

  def self.count_target_breached_sla
    joins(:sla_tickets).where(sla_tickets: { sla_target_response_deadline: 'Breached' }).count
  end

  def self.count_resolution_breached_sla
    joins(:sla_tickets).where(sla_tickets: { sla_resolution_deadline: 'Breached' }).count
  end

  # Calculate business hours duration between two timestamps
  def calculate_business_hours_duration(start_time, end_time)
    return 0 if start_time.blank? || end_time.blank?
    return 0 if end_time <= start_time

    business_hours = [
      { day: 1, start: 8, end: 13 }, { day: 1, start: 14, end: 17 },
      { day: 2, start: 8, end: 13 }, { day: 2, start: 14, end: 17 },
      { day: 3, start: 8, end: 13 }, { day: 3, start: 14, end: 17 },
      { day: 4, start: 8, end: 13 }, { day: 4, start: 14, end: 17 },
      { day: 5, start: 8, end: 13 }, { day: 5, start: 14, end: 17 },
      { day: 6, start: 8, end: 13 }
    ]

    holidays = [
      Date.new(2024, 12, 25), # Christmas
      Date.new(2024, 12, 26), # Boxing Day
      Date.new(2025, 1, 1), # New Year's Day
      Date.new(2025, 10, 10), # Utamaduni!
      Date.new(2025, 10, 20), # Mashujaa Day
      Date.new(2025, 12, 12), # Jamhuri!
      Date.new(2025, 12, 12), # Utamaduni!
      Date.new(2025, 12, 25), # Christmas
      Date.new(2025, 12, 26), # Boxing Day
      Date.new(2026, 1, 1) # New Year
    ]

    business_minutes = 0
    current_time = start_time

    while current_time < end_time
      business_minutes += 1 if within_business_hours?(current_time, business_hours) && !holiday?(current_time, holidays)

      current_time += 1.minute
    end

    business_minutes * 60 # Convert minutes to seconds
  end

  private

  def skip_callbacks
    skip_sla_callbacks || skip_history_logging
  end

  # Assign status to new ticket
  def set_default_status
    status = Status.find_by(name: 'Assigned')
    statuses << status if status
  end

  def track_updates
    self.update_count += 1
    self.last_updated_at = Time.current
  end

  def res_sla_breached?
    statuses.any? { |status| status.name == 'Resolved' && resolution_deadline < DateTime.now }
  end

  def res_sla_on_time?
    statuses.any? { |status| status.name == 'Resolved' && resolution_deadline > DateTime.now }
  end

  # SLA TWO
  def sla_breached?
    statuses.any? { |status| status.name == 'Client Information Pending' && target_repair_deadline < DateTime.now }
  end

  def sla_on_time?
    statuses.any? { |status| status.name == 'Client Information Pending' && target_repair_deadline > DateTime.now }
  end

  # SLA ONE
  def on_time?
    users.any? && initial_response_deadline >= DateTime.now
  end

  def breached?
    users.any? && initial_response_deadline < DateTime.now
  end

  def adjust_start_time(start_time)
    start_time ||= DateTime.now # Default to current time if start_time is nil

    business_hours = [
      { day: 1, start: 8, end: 13 }, { day: 1, start: 14, end: 17 },
      { day: 2, start: 8, end: 13 }, { day: 2, start: 14, end: 17 },
      { day: 3, start: 8, end: 13 }, { day: 3, start: 14, end: 17 },
      { day: 4, start: 8, end: 13 }, { day: 4, start: 14, end: 17 },
      { day: 5, start: 8, end: 13 }, { day: 5, start: 14, end: 17 },
      { day: 6, start: 8, end: 13 }
    ]

    until within_business_hours?(start_time, business_hours)
      start_time += 1.minute
      # Skip time between 1pm and 2pm
      start_time = start_time.change(hour: 14, min: 0) if start_time.hour == 13
      # Skip time after 5pm
      start_time = start_time.change(hour: 8, min: 0) + 1.day if start_time.hour >= 17
      # Skip non-business days (Sunday)
      start_time = start_time.change(hour: 8, min: 0) + 1.day if start_time.wday.zero?
    end
    start_time
  end

  def next_business_time(start_time, duration)
    start_time ||= DateTime.now # Ensure start_time is not nil

    business_hours = [
      { day: 1, start: 8, end: 13 }, { day: 1, start: 14, end: 17 },
      { day: 2, start: 8, end: 13 }, { day: 2, start: 14, end: 17 },
      { day: 3, start: 8, end: 13 }, { day: 3, start: 14, end: 17 },
      { day: 4, start: 8, end: 13 }, { day: 4, start: 14, end: 17 },
      { day: 5, start: 8, end: 13 }, { day: 5, start: 14, end: 17 },
      { day: 6, start: 8, end: 13 }
    ]

    holidays = [
      Date.new(2024, 12, 25), # Christmas
      Date.new(2024, 12, 26), # Boxing Day
      Date.new(2025, 1, 1), # New Year's Day
      Date.new(2025, 10, 10), # Utamaduni!
      Date.new(2025, 10, 20), # Mashujaa Day
      Date.new(2025, 12, 12), # Jamhuri!
      Date.new(2025, 12, 12), # Utamaduni!
      Date.new(2025, 12, 25), # Christmas
      Date.new(2025, 12, 26), # Boxing Day
      Date.new(2026, 1, 1) # New Year
      # Add more holidays as needed
    ]

    remaining_duration = duration
    current_time = start_time

    while remaining_duration.positive?
      current_time += 1.minute
      remaining_duration -= 1.minute if within_business_hours?(current_time, business_hours) && !holiday?(current_time, holidays)

      # Skip time between 1pm and 2pm
      current_time = current_time.change(hour: 14, min: 0) if current_time.hour == 13
      # Skip time after 5pm
      current_time = current_time.change(hour: 8, min: 0) + 1.day if current_time.hour >= 17
      # Skip non-business days (Sunday)
      current_time = current_time.change(hour: 8, min: 0) + 1.day if current_time.wday.zero?
    end

    current_time
  end

  def within_business_hours?(time, business_hours)
    return false if time.nil? # Gracefully handle nil time

    # Exclude Saturdays if priority is 'SEVERITY 1', 'SEVERITY 2', or 'SEVERITY 3'
    return false if ['SEVERITY 2', 'SEVERITY 3', 'SEVERITY 4'].include?(priority) && time.wday == 6

    business_hours.any? do |hours|
      time.wday == hours[:day] && time.hour >= hours[:start] && time.hour < hours[:end]
    end
  end

  def holiday?(time, holidays)
    holidays.include?(time.to_date)
  end

  # Take the initials for the #{project.title} and append a random hex string to it

  def ticket_unique_id
    initials = if project&.title.present?
                 project.title.split.map { |word| word[0] }.join.upcase
               else
                 'DEFAULT' # Fallback initials
               end

    last_ticket = Ticket.with_deleted
      .where(project_id: project.id)
      .where("unique_id ~ '^[^-]+-\\d+$'") # Only process valid formats
      .order(Arel.sql("CAST(SPLIT_PART(unique_id, '-', 2) AS INTEGER) DESC"))
      .first ||
                  Ticket.with_deleted.where(project_id: project.id).order(:created_at).last

    next_number = if last_ticket&.unique_id.present?
                    last_ticket.unique_id.split('-').last.to_i + 1
                  else
                    1
                  end

    loop do
      self.unique_id = "#{initials}-#{next_number.to_s.rjust(4, '0')}"
      break unless Ticket.with_deleted.exists?(unique_id: unique_id)

      next_number += 1
    end

    # Persist unique_id without running validations again to avoid recursive validation issues
    begin
      update_column(:unique_id, unique_id)
    rescue StandardError => e
      Rails.logger.error("[Ticket#ticket_unique_id] Failed to persist unique_id: #{e.message}")
    end
  end

  def content_length_within_limit
    return unless content.to_plain_text.length > 3000

    errors.add(:content, 'must be less than or equal to 3000 characters')
  end

  # For Breaches to occur
  # Severity 1 - 30 mins + 3 hrs + 4hrs = total-time
  # Severity 2 - 30 mins + 5 hrs + 8hrs = total-time
  # Severity 3 - 30 mins + 12 hrs + 16hrs = total-time
  # Severity 4 - 30 mins + 24 hrs + 24 hrs = total-time
  # In the Event table we have a field called duration where we record intervals for each ticket and the time take
  # Each status is recorded and saved on the Event table
  # We would like to add the time taken and subtract to the total time for each severity
  # if the interval time is greater than total-time the ticket is breached
  # if the interval time is less than total-time the ticket is not breached
  # if the ticket time is On-hold, Client Information Pending, Resolved, Closed, Declined the recorded interval is ignored
  # if the ticket time is New, Assigned, Work in Progress, Under Development, Pending, QA Testing, the recorded interval is added to the total time
  #
  #
  # Calculate total time allowed for each severity
  # def calculate_sla_breach(ticket)
  #  total_time = case ticket.priority
  #                when 'SEVERITY 1'
  #                  calculate_business_hours_duration(DateTime.now, DateTime.now + (30.minutes + 3.hours + 4.hours))
  #                when 'SEVERITY 2'
  #                  calculate_business_hours_duration(DateTime.now, DateTime.now + (30.minutes + 5.hours + 8.hours))
  #                when 'SEVERITY 3'
  #                  calculate_business_hours_duration(DateTime.now, DateTime.now + (30.minutes + 12.hours + 16.hours))
  #                when 'SEVERITY 4'
  #                  calculate_business_hours_duration(DateTime.now, DateTime.now + (30.minutes + 24.hours + 24.hours))
  #                else
  #                  0 # Default to 0 if priority is not defined
  #                end

    # Fetch all events for the ticket
  # total_duration = ticket.events.sum do |event|
  #    if %w[New Assigned Work\ in\ Progress Under\ Development Pending QA\ Testing].include?(event.status)
  #      event.duration
  #    elsif %w[On-Hold Client\ Information\ Pending Resolved Closed Declined].include?(event.status)
  #      0 # Ignore these statuses
  #    else
  #      0 # Default to 0 for undefined statuses
  #    end
  #  end

  # Determine if the ticket is breached
  #  if total_duration > total_time
  #    'Breached'
  #  elsif total_duration < total_time
  #    'Not Breached'
  # end
  #

end
