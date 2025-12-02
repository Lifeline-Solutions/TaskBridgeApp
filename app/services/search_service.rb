# frozen_string_literal: true

# Service class for handling global search across tickets and defects
class SearchService
  # Pattern for ticket unique IDs (e.g., PROJ-123, CS-0001)
  # Requires at least one letter, hyphen, and at least one digit
  TICKET_PATTERN = /^[A-Z]+-\d+$/i

  # Pattern for defect unique IDs (e.g., CS-0001, DEFAULT-0123)
  # Same as ticket pattern since defects use CLIENT_INITIALS-NUMBER format
  # Must have at least one digit after the hyphen
  DEFECT_PATTERN = /^[A-Z]+-\d+$/i

  attr_reader :query, :current_user

  def initialize(query, current_user)
    @query = query.to_s.strip
    @current_user = current_user
  end

  # Main search method
  def search
    return empty_results if query.blank?

    # Check if query matches a direct issue key pattern
    if direct_issue_match?
      find_direct_issue
    else
      perform_full_search
    end
  end

  # Check if query is a direct issue key
  def direct_issue_match?
    query.match?(TICKET_PATTERN) || query.match?(DEFECT_PATTERN)
  end

  # Find and return direct issue (ticket or defect)
  def find_direct_issue
    # Try to find ticket first
    ticket = find_ticket_by_unique_id(query)
    return { type: :redirect, resource: :ticket, record: ticket } if ticket

    # Try to find defect
    defect = find_defect_by_unique_id(query)
    return { type: :redirect, resource: :defect, record: defect } if defect

    # Not found, perform full search instead
    perform_full_search
  end

  private

  def perform_full_search
    {
      type: :results,
      query: query,
      tickets: search_tickets,
      defects: search_defects,
      total_count: nil # Will be calculated in controller
    }
  end

  def search_tickets
    Ticket
      .search_by_query(query)
      .accessible_by_user(current_user)
      .includes(:project, :statuses, :users)
      .order(created_at: :desc)
      .limit(50)
  end

  def search_defects
    Defect
      .search_by_query(query)
      .accessible_by_user(current_user)
      .includes(:product, :statuses, :users, :qa_module)
      .order(created_at: :desc)
      .limit(50)
  end

  def find_ticket_by_unique_id(unique_id)
    ticket = Ticket
      .where('LOWER(unique_id) = ?', unique_id.downcase)
      .accessible_by_user(current_user)
      .first

    ticket
  end

  def find_defect_by_unique_id(unique_id)
    defect = Defect
      .where('LOWER(defect_unique) = ?', unique_id.downcase)
      .accessible_by_user(current_user)
      .first

    defect
  end

  def empty_results
    {
      type: :results,
      query: '',
      tickets: Ticket.none,
      defects: Defect.none,
      total_count: 0
    }
  end
end
