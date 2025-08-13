class TestController < ApplicationController
  before_action :authenticate_user!, except: [:crash]

  def crash
    raise '💥 Test exception from web request!'
  end
end
