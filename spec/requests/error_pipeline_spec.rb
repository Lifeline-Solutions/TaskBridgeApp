require 'rails_helper'

RSpec.describe 'Error pipeline', type: :request do
  before { allow(Rails.logger).to receive(:info) } # less noisy

  it 'logs and sends an email via SafeNotifier on controller exception in production-like envs' do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))

    # Create a dummy route and controller action that raises
    stub_const('ErrorsController', Class.new(ApplicationController) do
      def boom
        raise 'Kaboom'
      end
    end)

    Rails.application.routes.disable_clear_and_finalize = true
    Rails.application.routes.draw do
      get '/_test_error', to: 'errors#boom'
    end

    expect do
      get '/_test_error'
    end.to raise_error(RuntimeError, 'Kaboom')

    # ActionMailer in test env uses :test adapter
    deliveries = ActionMailer::Base.deliveries
    expect(deliveries.last&.subject).to match(/Rails Error/)
  ensure
    Rails.application.reload_routes!
  end
end
