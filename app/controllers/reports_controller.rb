class ReportsController < ApplicationController
  before_action :authenticate_user!
  def index
    # This should show a pie chart of defects per status for all defects
    #  @defects = Defect.published
    #       .includes(:users, :qa_module, :submodule, :banking_type, :statuses, product: %i[client groupwares])
    #

    # app/controllers/reports_controller.rb
    @defects_per_creator = Defect.published
      .joins(:creator)
      .group('users.id', 'users.first_name', 'users.last_name')
      .count
  end
end
