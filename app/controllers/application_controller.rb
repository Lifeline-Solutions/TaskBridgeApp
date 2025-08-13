# The base controller for all controllers in the application
class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception # Protects from CSRF attacks

  # Require authentication for all actions except :new and :create
  before_action :authenticate_user!, except: %i[new create]

  # Permit additional Devise parameters if the controller is a Devise controller
  before_action :update_allowed_parameters, if: :devise_controller?

  # Check the user's state (active, profile completion, etc.) before each action
  before_action :check_user_state

  # Load notifications for the current user if signed in
  before_action :load_notifications, if: :user_signed_in?

  # Handle missing records by redirecting to root with an alert
  # rescue_from ActiveRecord::RecordNotFound, with: :redirect_to_root

  # Handle authorization errors by redirecting to root with an alert
  rescue_from CanCan::AccessDenied do |exception|
    redirect_to root_path, alert: exception.message
  end

  # Permit extra parameters for Devise actions (sign up, account update, invite)
  def update_allowed_parameters
    devise_parameter_sanitizer.permit(:sign_up) { |u| u.permit(:email, :password) }
    devise_parameter_sanitizer.permit(:account_update) do |u|
      u.permit(:name, :email, :password, :current_password, :profile_picture, :first_name, :last_name, :first_login)
    end
    devise_parameter_sanitizer.permit(:invite, keys: %i[email role])
  end

  private

  # Checks if the user is active and has completed their profile
  def check_user_state
    return unless user_signed_in?

    # If the user is deactivated, sign them out and redirect
    unless current_user.active
      sign_out current_user
      redirect_to new_user_session_path, alert: 'Your account is deactivated. Please contact the administrator.' and return
    end

    # If the user hasn't completed their profile, force them to edit it
    if !current_user.first_login && controller_name != 'registrations' && action_name != 'edit'
      redirect_to edit_user_registration_path, alert: 'Please complete your profile before continuing.' and return
    end

    # On profile update, set first_login and update names
    return unless controller_name == 'registrations' && action_name == 'update' && params[:user].present?
    return unless current_user.update(first_login: true, first_name: params[:user][:first_name], last_name: params[:user][:last_name])

    # If the user is a CEO, redirect to a special report page after profile update
    return redirect_to root_path, alert: 'Profile is Updated.' unless user_signed_in? && current_user.has_role?(:ceo) && !request.path.start_with?(cease_fire_report_path)

    redirect_to cease_fire_report_path
  end

  # Loads notifications for the current user
  def load_notifications
    return unless user_signed_in?

    @notifications = current_user.notifications.order(created_at: :desc)
  end

  # Redirects to root with a not found alert
  # def redirect_to_root
  #  redirect_to root_path, alert: 'The page you were looking for does not exist.'
  # end
end
