require 'rails_helper'

RSpec.describe SlaWarningJob, type: :job do
  describe '#perform' do
    let(:project) { create(:project) }
    let(:user) { create(:user) }

    before do
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:error)
      # Clear cache before each test
      Rails.cache.clear
    end

    context 'when tickets are approaching initial response deadline' do
      let!(:at_risk_ticket) do
        create(:ticket,
               project: project,
               user: user,
               initial_response_deadline: 25.minutes.from_now)
      end
      let!(:sla_ticket) { create(:sla_ticket, ticket: at_risk_ticket, sla_status: 'Not Breached') }

      it 'sends warning notification' do
        expect(Messaging::EmailSender).to receive(:send_email).and_call_original
        SlaWarningJob.new.perform
      end

      it 'marks the ticket as warned in cache' do
        SlaWarningJob.new.perform
        cache_key = "sla_warning:#{at_risk_ticket.id}:initial_response:30"
        expect(Rails.cache.exist?(cache_key)).to be true
      end
    end

    context 'when ticket has already been warned' do
      let!(:at_risk_ticket) do
        create(:ticket,
               project: project,
               user: user,
               initial_response_deadline: 25.minutes.from_now)
      end
      let!(:sla_ticket) { create(:sla_ticket, ticket: at_risk_ticket, sla_status: 'Not Breached') }

      before do
        # Mark as already warned
        cache_key = "sla_warning:#{at_risk_ticket.id}:initial_response:30"
        Rails.cache.write(cache_key, true, expires_in: 24.hours)
      end

      it 'does not send duplicate warning' do
        expect(Messaging::EmailSender).not_to receive(:send_email)
        SlaWarningJob.new.perform
      end
    end

    context 'when tickets are not at risk' do
      let!(:safe_ticket) do
        create(:ticket,
               project: project,
               user: user,
               initial_response_deadline: 3.hours.from_now)
      end
      let!(:sla_ticket) { create(:sla_ticket, ticket: safe_ticket, sla_status: 'Not Breached') }

      it 'does not send warnings' do
        expect(Messaging::EmailSender).not_to receive(:send_email)
        SlaWarningJob.new.perform
      end
    end
  end

  describe '#calculate_time_remaining' do
    let(:job) { SlaWarningJob.new }

    it 'formats time correctly for hours and minutes' do
      deadline = 2.hours.from_now + 30.minutes
      result = job.send(:calculate_time_remaining, deadline)
      expect(result).to match(/2 hours \d+ minutes?/)
    end

    it 'formats time correctly for minutes only' do
      deadline = 45.minutes.from_now
      result = job.send(:calculate_time_remaining, deadline)
      expect(result).to match(/\d+ minutes?/)
    end

    it 'handles expired deadlines' do
      deadline = 1.hour.ago
      result = job.send(:calculate_time_remaining, deadline)
      expect(result).to eq('0 minutes')
    end

    it 'handles nil deadlines' do
      result = job.send(:calculate_time_remaining, nil)
      expect(result).to eq('Unknown')
    end
  end
end
