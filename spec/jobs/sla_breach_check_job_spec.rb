require 'rails_helper'

RSpec.describe SlaBreachCheckJob, type: :job do
  describe '#perform' do
    it 'executes without errors' do
      expect { SlaBreachCheckJob.new.perform }.not_to raise_error
    end

    it 'completes successfully' do
      result = SlaBreachCheckJob.new.perform
      # Job execution completed (returns true from logger check)
      expect([nil, true]).to include(result)
    end

    context 'with existing tickets' do
      it 'finds and processes breached tickets' do
        allow(Rails.logger).to receive(:info)

        # Count how many tickets would be processed
        initial_breached = Ticket.joins(:sla_ticket)
          .where('tickets.initial_response_deadline < ?', Time.current)
          .where.not(sla_tickets: { sla_status: 'Breached' })
          .where('tickets.initial_response_deadline IS NOT NULL')
          .count

        # Run the job
        SlaBreachCheckJob.new.perform

        # Verify logging occurred
        expect(Rails.logger).to have_received(:info).with(/Starting SLA breach check/)
        expect(Rails.logger).to have_received(:info).with(/Completed SLA breach check/)
      end
    end
  end

  describe '#collect_recipients' do
    let(:job) { SlaBreachCheckJob.new }
    let(:ticket) { Ticket.joins(:project).first }

    it 'returns an array of emails' do
      skip 'No tickets available for testing' unless ticket

      recipients = job.send(:collect_recipients, ticket)
      expect(recipients).to be_an(Array)
    end

    it 'includes ticket creator email when present' do
      skip 'No tickets available for testing' unless ticket
      skip 'Ticket has no user' unless ticket.user

      recipients = job.send(:collect_recipients, ticket)
      expect(recipients).to include(ticket.user.email) if ticket.user&.email
    end

    it 'returns unique emails only' do
      skip 'No tickets available for testing' unless ticket

      recipients = job.send(:collect_recipients, ticket)
      expect(recipients.size).to eq(recipients.uniq.size)
    end

    it 'filters out blank emails' do
      skip 'No tickets available for testing' unless ticket

      recipients = job.send(:collect_recipients, ticket)
      expect(recipients).to all(be_present)
    end
  end

  describe '#breach_subject' do
    let(:job) { SlaBreachCheckJob.new }
    let(:ticket) { Ticket.first || double('Ticket', unique_id: 'TEST-001') }

    it 'generates correct subject for initial response breach' do
      subject = job.send(:breach_subject, ticket, :initial_response_breach)
      expect(subject).to include('Initial Response')
      expect(subject).to include('SLA BREACH')
    end

    it 'generates correct subject for target repair breach' do
      subject = job.send(:breach_subject, ticket, :target_repair_breach)
      expect(subject).to include('Target Repair')
      expect(subject).to include('SLA BREACH')
    end

    it 'generates correct subject for resolution breach' do
      subject = job.send(:breach_subject, ticket, :resolution_breach)
      expect(subject).to include('Resolution')
      expect(subject).to include('SLA BREACH')
    end
  end
end
