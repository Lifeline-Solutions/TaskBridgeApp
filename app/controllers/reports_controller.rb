require 'csv'
require 'axlsx'
class ReportsController < ApplicationController
  before_action :authenticate_user!

  def index
    # Get available products for dropdown - FIXED: Include client and groupware associations
    @product_options = Product.active
                              .includes(:client, :groupwares)
                              .map { |p| ["#{p.client&.name} #{p.groupwares&.first&.name}".strip, p.id] }
    
    # Initialize defect filters for the dropdown
    @defect_filters = current_user.defect_filters.active.defect_filters.includes(:product)
    
    # Handle defect filter selection
    if params[:defect_filter_id].present?
      defect_filter = @defect_filters.find_by(id: params[:defect_filter_id])
      if defect_filter
        # Apply the saved defect filter to report parameters
        apply_defect_filter_to_report(defect_filter)
      end
    end

    # Handle product selection (single or multiple)
    @selected_products = if params[:product_ids].present?
                          Array(params[:product_ids])
                        elsif params[:product_id].present?
                          [params[:product_id]]
                        else
                          []
                        end

    # Set main product_id for backward compatibility (first selected product)
    @product_id = @selected_products.first

    # Get available options based on selected products
    if @selected_products.any?
      @available_options = get_available_options(@selected_products)
      
      # Get selected metrics and their values
      @selected_metrics = Array(params[:metrics] || [])
      @selected_severities = Array(params[:severities] || [])
      @selected_reporters = Array(params[:reporters] || [])
      @selected_statuses = Array(params[:statuses] || [])
      @selected_assignees = Array(params[:assignees] || [])
      @selected_modules = Array(params[:modules] || [])
      @selected_submodules = Array(params[:submodules] || [])
      @selected_ageing_type = params[:ageing_type]

      # Generate report data if Apply was clicked or defect filter was selected
      if params[:commit].present? || params[:defect_filter_id].present?
        generate_report_data(@selected_products)
      end
    else
      @available_options = {}
      @selected_metrics = []
    end
  end
  
  def save_dashboard
    # Parse and prepare the filters for storage
    filters_data = if params[:defect_filter] && params[:defect_filter][:filters].is_a?(String)
                     JSON.parse(params[:defect_filter][:filters])
                   else
                     params[:defect_filter][:filters] || {}
                   end

    # Convert array parameters to JSON strings for proper storage
    %w[metrics severities reporters statuses assignees modules submodules].each do |array_key|
      filters_data[array_key] = filters_data[array_key].to_json if filters_data[array_key].is_a?(Array)
    end

    @dashboard = current_user.defect_filters.build(
      name: params[:defect_filter][:name],
      product_id: params[:defect_filter][:product_id],
      filters: filters_data,
      filter_type: 'report',
      is_dashboard: true
    )

    # Audit fields
    @dashboard.created_by = current_user
    @dashboard.modified_by = current_user

    if @dashboard.save
      redirect_to defect_filters_path, notice: 'Dashboard saved successfully!'
    else
      redirect_to reports_path(params.except(:defect_filter, :commit, :action, :controller)),
                  alert: "Failed to save dashboard: #{@dashboard.errors.full_messages.join(', ')}"
    end
  end

  def download_report
    require 'csv'
    # Download the current report data as CSV  for all reports once selected.
    authorize! :generate, :report

    product_id = params[:product_id]
    start_date = parse_date(params[:start_date])
    end_date = parse_date(params[:end_date])

    # Create base scope
    defects_scope = Defect.published
    defects_scope = defects_scope.where(product_id: product_id) if product_id.present?
    defects_scope = defects_scope.where('defects.created_at >= ?', start_date.beginning_of_day) if start_date
    defects_scope = defects_scope.where('defects.created_at <= ?', end_date.end_of_day) if end_date

    # Apply filters from params
    selected_severities = Array(params[:severities]).reject(&:blank?)
    if selected_severities.any?
      all_values = selected_severities.flat_map do |severity|
        case severity.downcase
        when 'severity 1' then ['severity 1', 's1', 'high']
        when 'severity 2' then ['severity 2', 's2', 'medium']
        when 'severity 3' then ['severity 3', 's3', 'low']
        when 'severity 4' then ['severity 4', 's4', 'very low']
        else [severity.downcase]
        end
      end
      defects_scope = defects_scope.where("LOWER(COALESCE(defects.priority, 'unknown')) IN (?)", all_values)
    end

    selected_reporters = Array(params[:reporters]).reject(&:blank?)
    defects_scope = defects_scope.where(creator_id: selected_reporters) if selected_reporters.any?

    selected_statuses = Array(params[:statuses]).reject(&:blank?)
    if selected_statuses.any?
      downcased_statuses = selected_statuses.map(&:downcase)
      defects_scope = defects_scope.joins(:statuses).where('LOWER(statuses.name) IN (?)', downcased_statuses)
    end

    selected_assignees = Array(params[:assignees]).reject(&:blank?)
    defects_scope = defects_scope.joins(:users).where(users: { id: selected_assignees }) if selected_assignees.any?

    selected_modules = Array(params[:modules]).reject(&:blank?)
    defects_scope = defects_scope.where(qa_module_id: selected_modules) if selected_modules.any?

    selected_submodules = Array(params[:submodules]).reject(&:blank?)
    defects_scope = defects_scope.where(submodule_id: selected_submodules) if selected_submodules.any?

    # Fetch defects with necessary associations to avoid N+1 queries
    defects = defects_scope
      .includes(:creator, :users, :statuses, :qa_module, :product)
      .order('defects.created_at DESC')

    # Generate CSV
    csv_data = CSV.generate(headers: true) do |csv|
      csv << ['ID', 'Summary', 'Project', 'Priority', 'Reporter', 'Assignees', 'Statuses', 'Module', 'Submodule', 'Created At', 'Updated At']

      defects.each do |defect|
        client_and_groupware = [defect.product.client&.name, defect.product.groupwares.first&.name].compact.join(' - ')

        csv << [
          defect.defect_unique,
          defect.summary,
          client_and_groupware,
          normalize_severity(defect.priority),
          defect.creator ? "#{defect.creator.first_name} #{defect.creator.last_name}" : 'N/A',
          defect.users.map { |u| "#{u.first_name} #{u.last_name}" }.join('; '),
          defect.statuses.map(&:name).join('; '),
          defect.qa_module&.name || 'N/A',
          defect.submodule&.name || 'N/A',
          defect.created_at.strftime('%Y-%m-%d %H:%M:%S'),
          defect.updated_at.strftime('%Y-%m-%d %H:%M:%S')
        ]
      end
    end

    filename = "defect_report_#{Time.now.strftime('%Y%m%d_%H%M')}.csv"
    send_data csv_data, filename: filename, type: 'text/csv'
  end

  private

  def dashboard_params
    params.require(:defect_filter).permit(:name, :product_id, filters: {})
  end

  def parse_date(value)
    return nil if value.blank?

    begin
      Date.parse(value)
    rescue StandardError
      nil
    end
  end

  def normalize_severity(key)
    k = key.to_s.strip.downcase
    case k
    when 'severity 1', 's1', 'high' then 'Severity 1'
    when 'severity 2', 's2', 'medium' then 'Severity 2'
    when 'severity 3', 's3', 'low' then 'Severity 3'
    when 'unknown', '' then 'Unknown'
    else k.titleize
    end
  end

  def apply_defect_filter_to_report(defect_filter)
    filters = defect_filter.sanitized_filters
    
    # Map defect filter parameters to report parameters
    params[:product_ids] = Array(filters['product_id']) if filters['product_id'].present?
    params[:start_date] = filters['start_date'] if filters['start_date'].present?
    params[:end_date] = filters['end_date'] if filters['end_date'].present?
    
    # Note: Defect filters don't have report metrics, so we keep existing metric selections
    # or you could set default metrics here if needed
  end

  def get_available_options(product_ids)
    defects_scope = Defect.where(product_id: product_ids, draft: false)
    defects_scope = defects_scope.where(created_at: params[:start_date]..params[:end_date]) if params[:start_date].present? && params[:end_date].present?

    {
      severities: defects_scope.distinct.pluck(:priority).compact.sort,
      reporters: defects_scope.joins(:creator)
                             .select('users.id, users.first_name, users.last_name')
                             .distinct
                             .map { |u| [u.id, "#{u.first_name} #{u.last_name}"] },
      statuses: defects_scope.joins(:statuses)
                            .select('statuses.id, statuses.name')
                            .distinct
                            .map { |s| [s.id, s.name] },
      assignees: defects_scope.joins(:users) # FIXED: Removed incorrect join
                             .select('users.id, users.first_name, users.last_name')
                             .distinct
                             .map { |u| [u.id, "#{u.first_name} #{u.last_name}"] },
      modules: defects_scope.joins(:qa_module)
                           .where(qa_modules: { parent_id: nil })
                           .select('qa_modules.id, qa_modules.name')
                           .distinct
                           .map { |m| [m.id, m.name] },
      submodules: defects_scope.joins(:qa_module)
                              .where.not(qa_modules: { parent_id: nil })
                              .select('qa_modules.id, qa_modules.name, qa_modules.parent_id')
                              .distinct
                              .map { |m| [m.id, m.name, m.parent_id] },
      ageing_types: [
        ['Last 7 days', '7_days'],
        ['Last 30 days', '30_days'],
        ['Last 90 days', '90_days'],
        ['Last 6 months', '6_months'],
        ['Last 1 year', '1_year']
      ]
    }
  end

  def generate_report_data(product_ids)
    defects_scope = Defect.where(product_id: product_ids, draft: false)
    defects_scope = defects_scope.where(created_at: params[:start_date]..params[:end_date]) if params[:start_date].present? && params[:end_date].present?

    # Defects by Reporter
    if @selected_metrics.include?('reporter')
      @defects_per_creator = defects_scope.joins(:creator)
                                         .group('users.id, users.first_name, users.last_name')
                                         .count
    end

    # Defects by Status
    if @selected_metrics.include?('status')
      status_scope = defects_scope
      status_scope = status_scope.joins(:statuses).where(statuses: { name: @selected_statuses }) if @selected_statuses.any?
      @defects_per_status = status_scope.joins(:statuses)
                                       .group('statuses.id, statuses.name')
                                       .count
    end

    # Defects by Severity
    if @selected_metrics.include?('severity')
      severity_scope = defects_scope
      severity_scope = severity_scope.where(priority: @selected_severities) if @selected_severities.any?
      @defects_per_severity = severity_scope.group(:priority).count
    end

    # Defects by Assignee
    if @selected_metrics.include?('assignee')
      assignee_scope = defects_scope.joins(:users)
      assignee_scope = assignee_scope.where(users: { id: @selected_assignees }) if @selected_assignees.any?
      @defects_per_assignee = assignee_scope.group('users.id, users.first_name, users.last_name').count
    end

    # Defects by Module
    if @selected_metrics.include?('modules')
      module_scope = defects_scope.joins(:qa_module).where(qa_modules: { parent_id: nil })
      module_scope = module_scope.where(qa_modules: { id: @selected_modules }) if @selected_modules.any?
      @defects_per_module = module_scope.group('qa_modules.id, qa_modules.name').count
    end

    # Defects by Submodule
    if @selected_metrics.include?('submodules')
      submodule_scope = defects_scope.joins(:qa_module).where.not(qa_modules: { parent_id: nil })
      submodule_scope = submodule_scope.where(qa_modules: { id: @selected_submodules }) if @selected_submodules.any?
      @defects_per_submodule = submodule_scope.group('qa_modules.id, qa_modules.name').count
    end

    # Defects Ageing
    if @selected_metrics.include?('ageing')
      @defects_age_buckets = calculate_defects_age_buckets(defects_scope, @selected_ageing_type)
    end
  end

  def calculate_defects_age_buckets(defects_scope, ageing_type)
    # ... existing ageing calculation logic ...
    # This should remain the same as your current implementation
  end
end