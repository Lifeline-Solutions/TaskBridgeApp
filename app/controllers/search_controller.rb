# Controller for handling global search requests
class SearchController < ApplicationController
  before_action :authenticate_user!

  def index
    @query = params[:query].to_s.strip

    if @query.blank?
      @tickets = Ticket.none
      @defects = Defect.none
      @total_count = 0
      flash.now[:notice] = 'Enter a search term to find tickets and defects'
      return
    end

    # Use SearchService to perform the search
    service = SearchService.new(@query, current_user)

    begin
      result = service.search

      # Handle redirect for direct issue match
      if result[:type] == :redirect
        redirect_to_issue(result[:resource], result[:record])
        return
      end

      # Handle search results
      @tickets = result[:tickets]
      @defects = result[:defects]
      @total_count = @tickets.size + @defects.size

      # Show helpful message if no results found
      flash.now[:alert] = "No results found for '#{@query}'. Try different keywords or check your spelling." if @total_count.zero?
    rescue StandardError => e
      # Log the error for debugging
      Rails.logger.error("Search error: #{e.message}\n#{e.backtrace.join("\n")}")

      # Show user-friendly error message
      @tickets = Ticket.none
      @defects = Defect.none
      @total_count = 0
      flash.now[:alert] = 'An error occurred while searching. Please try again or contact support if the problem persists.'
    end
  end

  # Autocomplete endpoint for search suggestions
  def autocomplete
    @query = params[:query].to_s.strip

    if @query.blank? || @query.empty?
      render json: []
      return
    end

    begin
      # Use SearchService but limit results for autocomplete
      SearchService.new(@query, current_user)

      # Get limited results for autocomplete
      tickets = Ticket
        .search_by_query(@query)
        .accessible_by_user(current_user)
        .includes(:project)
        .limit(5)
        .select(:id, :unique_id, :subject, :project_id)

      defects = Defect
        .search_by_query(@query)
        .accessible_by_user(current_user)
        .includes(:product)
        .limit(5)
        .select(:id, :defect_unique, :summary, :product_id)

      # Format results for autocomplete

      suggestions = tickets.map do |ticket|
        {
          type: 'ticket',
          id: ticket.id,
          key: ticket.unique_id,
          title: ticket.subject,
          project: ticket.project&.title,
          url: project_ticket_path(ticket.project, ticket)
        }
      end

      defects.each do |defect|
        suggestions << {
          type: 'defect',
          id: defect.id,
          key: defect.defect_unique,
          title: defect.summary,
          product: defect.product&.document_name,
          url: defect_path(defect)
        }
      end

      render json: suggestions
    rescue StandardError => e
      # Log the error
      Rails.logger.error("Autocomplete error: #{e.message}\n#{e.backtrace.join("\n")}")

      # Return empty array instead of crashing
      render json: []
    end
  end

  private

  def redirect_to_issue(resource_type, record)
    if record.nil?
      # Issue key format matched but not found - show empty results
      @tickets = Ticket.none
      @defects = Defect.none
      @total_count = 0
      flash.now[:alert] = "No #{resource_type} found with ID: #{@query}"
      render :index
      return
    end

    # Redirect to the appropriate show page
    case resource_type
    when :ticket
      redirect_to project_ticket_path(record.project, record)
    when :defect
      redirect_to defect_path(record)
    else
      # Fallback to search results
      render :index
    end
  end
end
