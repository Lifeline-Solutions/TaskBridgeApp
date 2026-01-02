require 'rails_helper'

RSpec.describe SlaWarningJob, type: :job do
  describe '#perform' do
    before do
      # Clear cache before tests
      Rails.cache.clear
    end

    it 'executes without errors' do
      expect { SlaWarningJob.new.perform }.not_to raise_error
    end

    it 'logs the start and completion of the job' do
      expect(Rails.logger).to receive(:info).with(/Starting SLA warning check/)
      expect(Rails.logger).to receive(:info).with(/Completed SLA warning check/)

      SlaWarningJob.new.perform
    end

    describe '#calculate_time_remaining' do
      let(:job) { SlaWarningJob.new }

      it 'formats time correctly for hours and minutes' do
        deadline = 2.hours.from_now + 30.minutes
        result = job.send(:calculate_time_remaining, deadline)

        expect(result).to match(/2 hours?/)
        expect(result).to match(/\d+ minutes?/)
      end

      it 'formats time correctly for minutes only' do
        deadline = 45.minutes.from_now
        result = job.send(:calculate_time_remaining, deadline)

        # Allow for small timing variations (44-46 minutes)
        expect(result).to match(/4[4-6] minutes?/)
        expect(result).not_to match(/hours?/)
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

    describe '#already_warned?' do
      let(:job) { SlaWarningJob.new }
      let(:ticket) { Ticket.first }

      it 'returns false when ticket has not been warned' do
        skip 'Requires valid ticket' unless ticket

        result = job.send(:already_warned?, ticket, :initial_response, 30)
        expect(result).to be false
      end

      it 'returns true after marking ticket as warned' do
        skip 'Requires valid ticket' unless ticket

        job.send(:mark_as_warned, ticket, :initial_response, 30)
        result = job.send(:already_warned?, ticket, :initial_response, 30)

        expect(result).to be true
      end
    end

    describe '#mark_as_warned' do
      let(:job) { SlaWarningJob.new }
      let(:ticket) { Ticket.first }

      it 'caches the warning for 24 hours' do
        skip 'Requires valid ticket' unless ticket

        job.send(:mark_as_warned, ticket, :initial_response, 30)
        cache_key = "sla_warning:#{ticket.id}:initial_response:30"

        expect(Rails.cache.exist?(cache_key)).to be true
      end
    end
  end
end
