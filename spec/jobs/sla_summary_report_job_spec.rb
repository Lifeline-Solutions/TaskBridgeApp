require 'rails_helper'

RSpec.describe SlaSummaryReportJob, type: :job do
  describe '#perform' do
    it 'executes without errors' do
      expect { SlaSummaryReportJob.new.perform }.not_to raise_error
    end

    it 'logs the start and completion of the job' do
      expect(Rails.logger).to receive(:info).with(/Starting daily SLA summary report/)
      expect(Rails.logger).to receive(:info).with(/Completed daily SLA summary report/)

      SlaSummaryReportJob.new.perform
    end

    it 'processes each team in the system' do
      team_count = Team.count

      if team_count > 0
        expect(Rails.logger).to receive(:info).at_least(team_count).times
      end

      SlaSummaryReportJob.new.perform
    end
  end

  describe '#calculate_performance_metrics' do
    let(:job) { SlaSummaryReportJob.new }

    it 'calculates compliance rate correctly' do
      scope = Ticket.joins(:users, :sla_ticket).where(users: { id: User.pluck(:id) })

      metrics = job.send(:calculate_performance_metrics, scope)

      expect(metrics).to have_key(:compliance_rate)
      expect(metrics[:compliance_rate]).to be_a(Numeric)
      expect(metrics[:compliance_rate]).to be_between(0, 100).inclusive
    end

    it 'handles zero tickets gracefully' do
      scope = Ticket.none

      metrics = job.send(:calculate_performance_metrics, scope)

      expect(metrics[:compliance_rate]).to eq(0)
    end

    it 'returns valid metrics structure' do
      scope = Ticket.joins(:users, :sla_ticket).limit(5)

      metrics = job.send(:calculate_performance_metrics, scope)

      expect(metrics).to be_a(Hash)
      expect(metrics[:compliance_rate]).to be_a(Numeric)
    end
  end

  describe '#build_summary_data' do
    let(:job) { SlaSummaryReportJob.new }

    it 'returns a hash with required keys' do
      user_ids = User.limit(1).pluck(:id)
      skip 'No users available' if user_ids.empty?

      summary = job.send(:build_summary_data, user_ids)

      expect(summary).to be_a(Hash)
      expect(summary).to have_key(:total_tickets)
      expect(summary).to have_key(:breached_count)
      expect(summary).to have_key(:on_time_count)
      expect(summary).to have_key(:at_risk_count)
      expect(summary).to have_key(:performance_metrics)
    end

    it 'includes breach breakdown by type' do
      user_ids = User.limit(1).pluck(:id)
      skip 'No users available' if user_ids.empty?

      summary = job.send(:build_summary_data, user_ids)

      expect(summary[:breach_by_type]).to have_key(:initial_response)
      expect(summary[:breach_by_type]).to have_key(:target_repair)
      expect(summary[:breach_by_type]).to have_key(:resolution)
    end
  end

  describe '#collect_report_recipients' do
    let(:job) { SlaSummaryReportJob.new }
    let(:team) { Team.first }

    it 'returns an array of emails' do
      skip 'No teams available' unless team

      recipients = job.send(:collect_report_recipients, team)

      expect(recipients).to be_an(Array)
    end

    it 'returns unique emails only' do
      skip 'No teams available' unless team

      recipients = job.send(:collect_report_recipients, team)

      expect(recipients.size).to eq(recipients.uniq.size)
    end

    it 'filters out blank emails' do
      skip 'No teams available' unless team

      recipients = job.send(:collect_report_recipients, team)

      expect(recipients).to all(be_present)
    end
  end
end
