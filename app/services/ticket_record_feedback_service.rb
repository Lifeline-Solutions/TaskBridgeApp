class TicketRecordFeedbackService
  # Initializes with:
  #  - ticket: Ticket record (persisted)
  #  - actor: User who performed the submission (should be ticket.user/client)
  #  - rating: integer 1..5
  #  - comment_html: optional HTML string (from ActionText)
  def initialize(ticket:, actor:, rating:, comment_html: nil)
    @ticket = ticket
    @actor = actor
    @rating = rating.to_i
    @comment_html = comment_html
  end

  # Creates the feedback record and increments ticket.feedback_count in a transaction.
  # Returns created TicketFeedback record.
  def call
    raise ArgumentError, "Invalid rating" unless (1..5).include?(@rating)
    @ticket.transaction do
      @ticket.lock!
      # increment feedback_count (safe if previously nil)
      @ticket.feedback_count = @ticket.feedback_count.to_i + 1
      @ticket.save!

      fb = TicketFeedback.create!(
        ticket: @ticket,
        rating: @rating,
        creator: @actor,
        captured_at: Time.current
      )

      # write ActionText content
      fb.comment = @comment_html.presence || "<p>No comment provided</p>"
      fb.save!

      # create timeline entry (use your existing DefectHistory/TicketHistory pattern)
      begin
        TicketHistory.create!(
          ticket: @ticket,
          user: @actor,
          history_type: "Client Feedback",
          history: "Feedback recorded (rating=#{@rating})"
        )
      rescue => e
        Rails.logger.error("TicketRecordFeedbackService: failed to create TicketHistory: #{e.message}")
      end

      fb
    end
  end
end