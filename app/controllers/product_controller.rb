class ProductController < ApplicationController
  before_action :authenticate_user!
  before_action :set_product, only: %i[show edit update destroy manage_users]
  load_and_authorize_resource

  def index
    # Base product query
    @product = Product.active
      .includes(softwares: :groupwares)

    # Search functionality for rich text content
    if params[:query].present?
      search_query = "%#{params[:query].strip}%"

      @product = @product
        .joins("LEFT JOIN action_text_rich_texts ON action_text_rich_texts.record_id = products.id AND action_text_rich_texts.record_type = 'Product'")
        .joins('LEFT JOIN products_statuses ON products_statuses.product_id = products.id')
        .joins('LEFT JOIN statuses ON statuses.id = products_statuses.status_id')
        .where(
          "products.document_name ILIKE :q OR
          statuses.name ILIKE :q OR
          CAST(products.budget AS TEXT) ILIKE :q OR
          action_text_rich_texts.body ILIKE :q OR
          EXISTS (
            SELECT 1 FROM clients
            WHERE clients.id = products.client_id
            AND clients.name ILIKE :q
          ) OR
          EXISTS (
            SELECT 1 FROM softwares
            WHERE softwares.id = products.software_id
            AND softwares.name ILIKE :q
          ) OR
          EXISTS (
            SELECT 1 FROM groupwares
            WHERE groupwares.id = products.groupware_id
            AND groupwares.name ILIKE :q
          )",
          q: search_query
        )
    end

    # Sort by dropdown (before pagination!)
    @product = case params[:sort_by]
               when 'upcoming'
                 @product.order(end_date: :asc)
               else
                 @product.order(created_at: :desc)
               end

    # Filter by status
    @product = @product.joins(:statuses).where(statuses: { name: params[:status] }) if params[:status].present? && params[:status] != 'All'

    # Filter by user role
    # THis line has been commented out for the time being, we are allowing PMS to see all projects
    # After 2 weeks we should re uncomment it to allow a pm to only see their own projects
    # @product = @product.joins(:users).where(users: { id: current_user.id }) unless current_user.has_any_role?(:admin, :observer, :hod)

    # Filter by user role (allow PMs to see all projects). After two weeks remove this line
    @product = @product.joins(:users).where(users: { id: current_user.id }) unless current_user.has_any_role?(:admin, :observer, :hod, 'project manager')

    # Pagination (AFTER all filters and sorts)
    @per_page = 12
    @page = (params[:page] || 1).to_i
    @total_pages = (@product.count / @per_page.to_f).ceil
    @start_count = ((@page - 1) * @per_page) + 1
    @end_count = [@page * @per_page, @product.count].min
    @total_count = @product.count

    @product = @product.offset((@page - 1) * @per_page).limit(@per_page)

    # Used statuses
    @used_statuses = @product.map { |p| p.statuses.first&.name }.compact.uniq
  end

  def show
    if current_user.has_role?('project manager') || current_user.has_role?(:admin) || @product.users.include?(current_user) || current_user.has_role?(:hod)
      @days_remaining = (@product.end_date - Date.today).to_i if @product.end_date.present?

      # Base tasks query with all necessary includes
      @tasks = @product.tasks.includes(:statuses, :users).order(created_at: 'desc')

      # Apply search query if present
      if params[:query].present?
        search_query = "%#{params[:query].strip}%"
        @tasks = @tasks.left_joins(:users).where(
          "tasks.name ILIKE ? OR
          tasks.description ILIKE ? OR
          tasks.priority ILIKE ? OR
          users.first_name ILIKE ?",
          search_query, search_query, search_query, search_query
        ).distinct
      end

      @tasks_by_status = @tasks.group_by { |task| task.statuses.first&.name || 'Uncategorized' }
    else
      redirect_to root_path, alert: 'You are not authorized to view this content.'
    end
  end

  def manage_users
    respond_to do |format|
      format.html
      format.turbo_stream
    end

    render layout: false
  end

  def new
    @product = Product.new
    @product.documents.build
    render layout: false if turbo_frame_request?
  end

  def create
    @product = Product.new(product_params)
    @product.user_id = current_user.id
    audit_on_create(@product)

    # Validate presence of name, description, and content (subject)
    @product.errors.add(:content, "can't be blank") if @product.content.blank?

    respond_to do |format|
      if (current_user.has_role?(:admin) || current_user.has_role?('project manager')) && @product.errors.empty?
        @product.users << @product.user if @product.users.empty?

        case params[:commit]
        when 'create'
          @product.status = 'published'
        when 'draft'
          @product.status = 'draft'
        end

        if @product.save
          # Save the selected software
          @product.softwares = Software.where(id: params[:product][:software_ids])

          # Save the selected groupware only if it is selected
          if params[:product][:groupware_ids].present?
            @product.groupwares = Groupware.where(id: params[:product][:groupware_ids])
          else
            @product.groupwares.clear
          end

          # Save the select script onlyd if it is elected

          current_user.add_role :creator, @product
          format.html { redirect_to product_path(@product), notice: "Project was successfully #{@product.status == 'draft' ? 'saved as draft' : 'created'}." }
        else
          format.html { render :new, status: :unprocessable_entity }
        end
      else
        format.html do
          render :new, status: :unprocessable_entity, notice: 'You are not authorized to create a product.'
        end
      end
    end
  end

  def edit
    @product.documents.build if @product.documents.empty?
  end

  def update
    audit_on_update(@product)
    if @product.update(product_params)
      redirect_to product_path(@product), notice: 'Product was successfully updated.'
    else
      SafeNotifier.email(StandardError.new('Product update failed'), context: { errors: @product.errors.full_messages, params: params.to_unsafe_h })
      render :edit, status: :unprocessable_entity
    end
  end

  def add_user
    if @product.users.include?(User.find(params[:user_id]))
      redirect_to @product, notice: 'User has already been assigned.'
    else
      @product = Product.find(params[:id])
      user = User.find(params[:user_id])
      @product.user = current_user
      @product.users << user

      activity('user_activity')
        .caused_by(current_user)
        .performed_on(@product)
        .event('product.assign_user')
        .with_properties(user_id: user.id)
        .log("Assigned #{user.name} to Product ##{@product.id}")

      assigned_user = user
      Messaging::EmailSender
        .send_email(
          'Product Assignment',
          to: [assigned_user.email],
          actor: current_user,
          priority: :normal,
          type: 'product_assign'
        )
        .use_template(view: 'user_mailer/assign_product_email', assigns: { user: assigned_user, product: @product, current_user:, assigned_user: })
        .set_source('product', @product.id)
        .set_party('user', assigned_user.id)
        .send(queue: true)
      # @product.users.each do |product_user|
      #  next if product_user == current_user

      # UserMailer.assign_product_email(product_user, @product, current_user, assigned_user).deliver_later
      # end

      redirect_to product_path(@product), notice: "#{user.name}  was successfully assigned."
    end
  end

  def product_status
    @product = Product.find(params[:id])
    status = Status.find(params[:status_id])
    @product.statuses.clear
    @product.user = current_user
    @product.statuses << status
    activity('user_activity')
      .caused_by(current_user)
      .performed_on(@product)
      .event('product.status_update')
      .with_properties(status_id: status.id, status_name: status.name)
      .log("Updated Product ##{@product.id} status to #{status.name}")

    # Send an email to the developers and select the
    @product.users.each do |u|
      client_name = @product.client&.name.presence || 'Client'
      groupware_names = @product.groupwares.map(&:name).join(', ').presence || ''
      subject = "Project Payment Status for #{client_name} #{groupware_names} milestone"
      Messaging::EmailSender
        .send_email(
          subject,
          to: [u.email],
          actor: current_user,
          priority: :normal,
          type: 'finance_sales'
        )
        .use_template(view: 'user_mailer/finance_sales_email', assigns: { product: @product, assigned_user: u, current_user: })
        .set_source('product', @product.id)
        .set_party('user', u.id)
        .send(queue: true)
    end
    redirect_to product_path(@product), notice: 'Product status was successfully updated.'
  end

  def remove_user
    @product = Product.find(params[:id])
    user = User.find(params[:user_id])
    @product.users.delete(user)
    activity('user_activity')
      .caused_by(current_user)
      .performed_on(@product)
      .event('product.unassign_user')
      .with_properties(user_id: user.id)
      .log("Unassigned #{user.name} from Product ##{@product.id}")
    redirect_to @product, notice: "#{user.name}  was successfully removed."
  end

  def toggle_paid
    @product = Product.find(params[:id])
    @milestone = @product.milestones.find(params[:milestone_id])

    if @milestone.update(paid: params[:paid] == '1')
      activity('user_activity')
        .caused_by(current_user)
        .performed_on(@milestone)
        .event('milestone.toggle_paid')
        .with_properties(paid: @milestone.paid, status: @milestone.status&.name, product_id: @milestone.product_id)
        .log('Milestone payment toggled')
      respond_to do |format|
        format.html do
          redirect_back fallback_location: product_path(@product), notice: "Milestone with status '#{@milestone.status&.name}' is now #{@milestone.paid? ? 'paid' : 'unpaid'}."
        end
        format.js
      end
    else
      respond_to do |format|
        format.html { render :edit, alert: 'Failed to update milestone.' }
        format.js
      end
    end
  end

  def destroy
    if audit_soft_delete(@product)
      redirect_to product_index_path, notice: 'Product was successfully deleted.'
    else
      @product.destroy
      redirect_to product_index_path, notice: 'Product was successfully destroyed.'
    end
  end

  private

  def set_product
    @product = Product.find(params[:id])
  end

  def product_params
    params.require(:product).permit(:status, :start_date, :end_date, :document_name, :image, :content, :budget,
                                    :user_id, :client_id, images: [], software_ids: [], groupware_ids: [],
                                                          documents_attributes: %i[id name file _destroy],
                                                          milestones_attributes: %i[id status_id percentage amount paid position _destroy])
  end
end
