class DefectRecordFailureService
  def initialize(defect:, actor:, reason_html: nil)
    @defect = defect
    @actor = actor
    @reason_html = reason_html
  end

  def call
    @defect.transaction do
      @defect.lock!

      failed_status = Status.where("lower(name) = ?", "failed qa").first || Status.find_by(name: "Failed QA")
      if failed_status
        @defect.statuses.clear
        @defect.statuses << failed_status
      end

      @defect.retest_count = @defect.retest_count.to_i + 1
      @defect.save!

      report = DefectFailureReport.create!(
        defect: @defect,
        retest_number: @defect.retest_count,
        captured_at: Time.current,
        creator: @actor
      )

      # store HTML into ActionText rich text
      report.reason = @reason_html.presence || "<p>No QA comment provided</p>"
      report.save!

      create_history_and_activity(report)

      report
    end
  end

  private

  def create_history_and_activity(report)
    # create timeline entry
    DefectHistory.create!(
      defect: @defect,
      user: @actor,
      history_type: 'QA Failed (retest recorded)',
      history: "Retest ##{report.retest_number} recorded at #{report.captured_at.strftime('%Y-%m-%d %H:%M')}"
    )
    # audit activity, wrap in rescue in your production code as needed
    activity('user_activity').caused_by(@actor).performed_on(@defect)
      .event('defect.retest_recorded').with_properties(retest_number: report.retest_number)
      .log("Defect ##{@defect.id} marked QA Failed — retest ##{report.retest_number}")
  rescue => e
    Rails.logger.error("DefectRecordFailureService: logging failure: #{e.message}")
  end
end
