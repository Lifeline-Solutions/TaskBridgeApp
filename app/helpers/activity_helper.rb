module ActivityHelper
  extend ActiveSupport::Concern

  def activity(log_name = 'user_activity')
    Activities.activity(log_name: log_name)
  end
end
