# QA Dashboards Controller - Manages dashboards with embedded widgets
class QaDashboardsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_dashboard, only: %i[edit update destroy]
  before_action :set_accessible_dashboard, only: %i[show]

  def index
    @dashboards = Dashboard.active.visible_to(current_user).includes(:defect_filter)
  end

  def new
    @dashboard = Dashboard.new
    @saved_filters = current_user.defect_filters.active
    @users = User.where.not(id: current_user.id)
      .where(active: true)
      .where('email ILIKE ?', '%@craftsilicon%')
      .order(:first_name, :last_name) # For sharing
  end

  def create
    @dashboard = current_user.dashboards.build(dashboard_params)
    @dashboard.created_by = current_user
    @dashboard.modified_by = current_user

    if @dashboard.save
      redirect_to qa_dashboard_path(@dashboard), notice: 'Dashboard created successfully.'
    else
      @saved_filters = current_user.defect_filters.active
      render :new, status: :unprocessable_entity
    end
  end

  def show
    # Check if defect filter exists (might be deleted/archived)
    unless @dashboard.defect_filter.present?
      redirect_to qa_dashboards_path, alert: 'This dashboard\'s filter has been deleted. Please update or delete this dashboard.'
      return
    end

    # Initialize product filter variables
    @selected_product_ids = Array(params[:product_id]).reject(&:blank?)

    # Load products with QA statuses (similar to reports_controller approach)
    products = Product.qa_projects.active.includes(:client, :groupwares)
    @product_options = products.map do |product|
      client_name = product.client&.name || 'No Client Assigned'
      groupware_names = product.groupwares.any? ? product.groupwares.map(&:name).join(', ') : 'No Software'
      ["#{client_name} - #{groupware_names}", product.id]
    end

    # Determine which products to filter by:
    # 1. If user selected products via dropdown, use those
    # 2. Otherwise, use the filter's associated product_id (default view)
    # 3. If neither exists, show all products (legacy behavior)
    product_ids_to_filter = if @selected_product_ids.any?
                              @selected_product_ids
                            elsif @dashboard.defect_filter.product_id.present?
                              [@dashboard.defect_filter.product_id]
                            else
                              []
                            end
    @product_scope = product_ids_to_filter

    # Generate automatic charts for active filter parameters with product filtering
    result = DashboardDataGenerator.new(@dashboard, product_ids: product_ids_to_filter).generate
    @defects = result[:defects]
    @charts = result[:charts]
    @total_count = result[:total_count]
    @filter_params = @dashboard.defect_filter.sanitized_filters

    # Generate retest count metrics
    @retest_metrics = generate_retest_metrics(@defects)

    # Resolve current project names for display
    @current_project_names = resolve_project_names(product_ids_to_filter)

    # Debug: Log active parameters
    Rails.logger.debug '=== DASHBOARD DEBUG ==='
    Rails.logger.debug "Filter ID: #{@dashboard.defect_filter.id}"
    Rails.logger.debug "Filter's product_id: #{@dashboard.defect_filter.product_id}"
    Rails.logger.debug "Selected product IDs from UI: #{@selected_product_ids.inspect}"
    Rails.logger.debug "Product IDs used for filtering: #{product_ids_to_filter.inspect}"
    Rails.logger.debug "Active Filter Parameters: #{@dashboard.active_filter_parameters.inspect}"
    Rails.logger.debug "Sanitized Filters: #{@filter_params.inspect}"
    Rails.logger.debug "Charts Generated: #{@charts.keys.inspect}"
    Rails.logger.debug '======================='

    # Generate custom field charts (new feature)
    @custom_field_charts = generate_custom_field_charts(@defects) if @dashboard.custom_fields.present?

    # Legacy widget data (if widgets exist)
    @widget_data = {}
    @dashboard.widgets.each_with_index do |_widget, index|
      @widget_data[index] = @dashboard.generate_widget_data(index)
    end

    @defects = @defects.where(retest_count: params[:retest_count]) if params[:retest_count].present?

    # show the number of reopened defects this from the defect History

    defect_ids_for_page = @defects.map(&:id)
    @reopened_defect_count_per_defect = if defect_ids_for_page.any?
                                          DefectHistory.where(defect_id: defect_ids_for_page, history_type: 'Status Changed')
                                            .where('history ILIKE ?', '%to Reopened%')
                                            .count

                                        end
    # Total Defects with Reopened
    @reopened_defects_count = if defect_ids_for_page.any?
                                DefectHistory.where(defect_id: defect_ids_for_page, history_type: 'Status Changed')
                                  .where('history ILIKE ?', '%to Reopened%')
                                  .distinct
                                  .count(:defect_id)
                              else
                                0
                              end

    # Show the total number of reopened per project for the current filter
    @reopened_defects_total = if defect_ids_for_page.any?
                                DefectHistory.where(defect_id: defect_ids_for_page, history_type: 'Status Changed')
                                  .where('history ILIKE ?', '%to Reopened%')
                                  .count
                              else
                                0
                              end

    # Calculate the number of defects for the current product_id
    @reopened_percentage = (@reopened_defects_count.to_f / @total_count * 100).round(1)

    # Show the following for the defects on Reopened
    # 1. Display the list with frequency show the number of times a defect has been opened,
    #     i.e. 1 time 2 times 3 times e.t.c
    #     2. Show the top 5 defects with the highest number of times reopened

    # Calculate the frequency of "Reopened" for each defect
    @reopened_frequency = if defect_ids_for_page.any?
                            DefectHistory.where(defect_id: defect_ids_for_page, history_type: 'Status Changed')
                              .where('history ILIKE ?', '%to Reopened%')
                              .group(:defect_id)
                              .count
                          else
                            {}
                          end

    # Group the defects by the count of times reopened
    @grouped_reopened_frequency = @reopened_frequency.values.group_by(&:itself).transform_values(&:count)

    # Sort the grouped counts in descending order
    @sorted_grouped_reopened_frequency = @grouped_reopened_frequency.sort_by { |count, _frequency| -count }.to_h
  end

  def edit
    @saved_filters = current_user.defect_filters.active
    @users = User.where.not(id: current_user.id)
      .where(active: true)
      .where('email ILIKE ?', '%@craftsilicon%')
      .order(:first_name, :last_name) # For sharing
  end

  def update
    @dashboard.modified_by = current_user

    if @dashboard.update(dashboard_params)
      redirect_to qa_dashboard_path(@dashboard), notice: 'Dashboard updated successfully.'
    else
      @saved_filters = current_user.defect_filters.active
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @dashboard.update(deleted_on: Time.current, deleted_by: current_user)
    redirect_to qa_dashboards_path, notice: 'Dashboard deleted successfully.'
  end

  private

  def generate_retest_metrics(defects)
    # Remove any existing ORDER BY to avoid PostgreSQL DISTINCT issues
    defects = defects.unscope(:order) if defects.respond_to?(:unscope)

    # Step 1: Get defect IDs with retest counts using raw SQL to avoid Rails complexities
    defect_ids = defects.pluck(:id)
    return { distribution: {}, top_defects: [], total_with_retests: 0, total_defects: defects.count } if defect_ids.empty?

    # Use raw SQL to get counts and avoid PostgreSQL grouping issues
    sql = <<~SQL
      SELECT d.id, COUNT(dfr.id) as retest_count
      FROM defects d
      LEFT JOIN defect_failure_reports dfr ON d.id = dfr.defect_id
      WHERE d.id IN (#{defect_ids.map { |id| "'#{id}'" }.join(',')})
      GROUP BY d.id
      HAVING COUNT(dfr.id) > 0
      ORDER BY COUNT(dfr.id) DESC
    SQL

    results = ActiveRecord::Base.connection.execute(sql)

    # Calculate distribution from results
    retest_distribution = {}
    results.each do |row|
      count = row['retest_count']
      retest_distribution[count] = (retest_distribution[count] || 0) + 1
    end
    retest_distribution = retest_distribution.sort_by { |count, _| -count }.to_h

    # Get the defect IDs with retests in order
    defect_ids_with_retests = results.map { |row| row['id'] }

    # Load full defect records in the correct order
    top_defects_with_retests = if defect_ids_with_retests.any?
                                 Defect.where(id: defect_ids_with_retests)
                                   .includes(:users, :product, :statuses, :qa_module, :banking_type)
                                   .index_by(&:id)
                                   .values_at(*defect_ids_with_retests)
                                   .each_with_index do |defect, index|
                                     # Add the retest_count as an attribute
                                     defect.define_singleton_method(:retest_count) { results[index]['retest_count'] }
                                   end
                               else
                                 []
                               end

    {
      distribution: retest_distribution,
      top_defects: top_defects_with_retests.first(50),
      total_with_retests: defect_ids_with_retests.count,
      total_defects: defects.count
    }
  end

  def generate_custom_field_charts(defects)
    charts = {}
    return charts if @dashboard.custom_fields.blank?

    generator = CustomFieldChartGenerator.new(defects)
    @dashboard.custom_fields.each do |field|
      chart_data = generator.generate_chart(field)
      charts[field.titleize] = chart_data if chart_data.present?
    end
    charts
  end

  def set_dashboard
    # Restrict edit/update/destroy to owner only
    @dashboard = current_user.dashboards.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    # Check if dashboard exists but belongs to someone else
    dashboard = Dashboard.active.find_by(id: params[:id])
    if dashboard
      redirect_to qa_dashboards_path,
                  alert: 'You cannot edit or delete dashboards that you do not own. This dashboard is shared with you as read-only.'
    else
      redirect_to qa_dashboards_path, alert: 'Dashboard not found.'
    end
  end

  def set_accessible_dashboard
    # Restrict show to owner OR shared OR public
    @dashboard = Dashboard.active.visible_to(current_user).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to qa_dashboards_path, alert: 'You do not have permission to view this dashboard.'
  end

  def dashboard_params
    params.require(:dashboard).permit(
      :name,
      :description,
      :defect_filter_id,
      :auto_refresh_interval,
      :visibility,
      custom_fields: [],
      widgets: %i[name group_by_field visualization_type position],
      shared_user_ids: []
    )
  end

  def resolve_project_names(product_ids)
    return 'All Products' if product_ids.empty?

    # Fetch products based on IDs
    products = Product.where(id: product_ids).includes(:client, :groupwares)

    if products.empty?
      # Fallback to dashboard filter's single product if no products found by IDs
      if @dashboard.defect_filter.product_id.present?
        fallback_product = Product.find_by(id: @dashboard.defect_filter.product_id)
        return fallback_product&.document_name || 'All Products'
      end
      'All Products'
    elsif products.one?
      # Single product - show full name with client info
      product = products.first
      client_name = product.client&.name || 'No Client'
      groupware_names = product.groupwares.any? ? product.groupwares.map(&:name).join(', ') : 'No Software'
      "#{client_name} - #{groupware_names}"
    else
      # Multiple products - show count and summarize
      "#{products.count} Projects Selected"
    end
  end
end
