class InvitationsController < Devise::InvitationsController
  # Ensure the user is authenticated before any action
  before_action :authenticate_user!

  # Renders the invitation form
  def new
    @user = User.new # Initialize a new User object
    self.resource = @user # Set Devise resource for the form
    @resource_name = :user # Set resource name for Devise views
  end

  # Handles the invitation creation
  def create
    # Check if the email is blank
    if invite_params[:email].blank?
      flash.now[:alert] = 'Email cannot be blank.' # Show alert
      render :new # Re-render the form
      return # Stop further execution
    end

    # Check if a user with the same details already exists
    existing_user = User.find_by(
      email: invite_params[:email],
      first_name: invite_params[:first_name],
      last_name: invite_params[:last_name],
      client_id: invite_params[:client_id]
    )

    if existing_user
      flash[:alert] = 'User already exists.' # Show alert
      redirect_to new_user_invitation_path # Redirect to invitation form
    else
      invited_user = nil # Placeholder for the invited user
      # Invite the user and assign a role
      User.invite!(invite_params, current_user) do |u|
        assign_role(u) # Assign role to the invited user
        invited_user = u # Store the invited user
      end

      # Check if invitation was successful
      if invited_user&.errors&.blank?
        activity('user_activity')
          .caused_by(current_user)
          .performed_on(invited_user)
          .event('user.invited')
          .with_properties(email: invited_user.email, client_id: invited_user.client_id, role_ids: invited_user.role_ids)
          .log('User invited')
        redirect_to users_path, notice: 'User has been invited successfully.' # Success redirect
      else
        flash[:alert] = 'There was an error inviting the user.' # Show error
        redirect_to new_user_invitation_path # Redirect to invitation form
      end
    end
  end

  private

  # Strong parameters for invitation
  def invite_params
    params.require(:user).permit(:email, :first_name, :last_name, :client_id, roles: [])
  end

  # Assigns a role to the user based on the current user's role
  def assign_role(user)
    return unless params[:role].present? # Skip if no role provided

    role = params[:role] # Get the role from params

    if current_user.has_role?(:admin)
      user.add_role(role) # Admin can assign any role
    elsif current_user.has_role?(:project_manager)
      user.add_role(role) unless role == 'admin' # Project manager can't assign admin
    else
      user.add_role(role) unless %w[admin project_manager].include?(role) # Others can't assign admin or project_manager
    end
  end
end
