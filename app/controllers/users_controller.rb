class UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user, only: %i[edit update]

  def index
    @per_page = 10
    @page = (params[:page] || 1).to_i

    @users = if params[:query].present?
               User.left_joins(:client, :roles)
                 .where('users.email ILIKE :query OR users.first_name ILIKE :query OR
                         users.last_name ILIKE :query OR clients.name ILIKE :query OR roles.name ILIKE :query',
                        query: "%#{params[:query]}%").distinct
             else
               User.order('created_at DESC').distinct
             end
    @total_pages = (@users.count / @per_page.to_f).ceil
    @users = @users.offset((@page - 1) * @per_page).limit(@per_page)
  end

  def edit; end

  def update
    audit_on_update(@user)
    respond_to do |format|
      if @user.update(filtered_user_params)
        activity('user_activity')
          .caused_by(current_user)
          .performed_on(@user)
          .event('user.update')
          .log('User updated')
        format.html { redirect_to users_path, notice: 'User was successfully updated.' }
      else
        format.html { render :edit, status: :unprocessable_entity }
      end
    end
  end

  def search
    users = User.where('first_name ILIKE ?', "%#{params[:q]}%").limit(250)
    render json: users.select(:id, :first_name, :last_name)
  end

  # Add status to active or inactive user

  def status
    @user = User.find(params[:id])
    @user.toggle_boolean(:active)
    activity('user_activity')
      .caused_by(current_user)
      .performed_on(@user)
      .event('user.toggle_status')
      .with_properties(active: @user.active)
      .log('User status toggled')
    redirect_to users_path, notice: 'User status was successfully updated.'
  end

  def active
    per_page = 50
    page = params[:page].to_i.positive? ? params[:page].to_i : 1 # Default to page 1 if no page is provided

    @active_users = User.joins(:roles)
      .where(roles: { name: ['client', 'project manager', 'admin', 'agent', 'observer'] })
      .where('sign_in_count > ?', 0)
      .distinct
      .order(sign_in_count: :desc)
      .limit(per_page)
      .offset((page - 1) * per_page)

    @total_pages = (User.joins(:roles)
                        .where(roles: { name: ['client', 'project manager', 'admin', 'agent', 'observer'] })
                        .where('sign_in_count > ?', 0)
                        .count / per_page.to_f).ceil
    @current_page = page
  end

  def client_active
    per_page = 50
    page = params[:page].to_i.positive? ? params[:page].to_i : 1

    @active_users_clients = User.joins(:roles)
      .where(roles: { name: 'client' })
      .distinct
      .order(sign_in_count: :desc)
      .where('sign_in_count > ?', 0)
      .limit(per_page)
      .offset((page - 1) * per_page)

    @total_pages = (User.joins(:roles)
                        .where(roles: { name: 'client' })
                        .where('sign_in_count > ?', 0)
                        .count / per_page.to_f).ceil
    @current_page = page
  end

  def manager_active
    per_page = 50
    page = params[:page].to_i.positive? ? params[:page].to_i : 1

    @active_users_manager = User.joins(:roles)
      .where(roles: { name: 'project manager' })
      .distinct
      .where('sign_in_count > ?', 0)
      .order(sign_in_count: :desc)
      .limit(per_page)
      .offset((page - 1) * per_page)

    @total_pages = (User.joins(:roles)
                        .where(roles: { name: 'project manager' })
                        .where('sign_in_count > ?', 0)
                        .count / per_page.to_f).ceil
    @current_page = page
  end

  def agent_active
    per_page = 50
    page = params[:page].to_i.positive? ? params[:page].to_i : 1

    @active_users_agent = User.joins(:roles).where(roles: { name: 'agent' })
      .distinct
      .where('sign_in_count > ?', 0)
      .order(sign_in_count: :desc)
      .limit(per_page)
      .offset((page - 1) * per_page)

    @total_pages = (User.joins(:roles)
                        .where(roles: { name: 'agent' })
                        .where('sign_in_count > ?', 0)
                        .count / per_page.to_f).ceil
    @current_page = page
  end

  def reset_user_password
    @user = User.find(params[:id])
    respond_to do |format|
      if @user.update(confirmation_token: nil, reset_password_token: nil, password: SecureRandom.hex(8))
        format.html { redirect_to users_path, notice: 'Password reset successfully' }
      else
        format.html { redirect_to users_path, notice: 'Password reset failed' }
      end
    end
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:first_name, :last_name, :client_id, role_ids: [])
  end

  def filtered_user_params
    if current_user.has_role?(:admin)
      user_params
    else
      user_params.tap do |params|
        if params[:role_ids].present? && (admin_role = Role.find_by(name: 'admin'))
          params[:role_ids] -= [admin_role.id.to_s]
        end
      end
    end
  end
end
