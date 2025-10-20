require 'csv'
require 'axlsx'

class ReportsController < ApplicationController
  before_action :authenticate_user!

  def index
    authorize! :generate, :report
    
    # Load saved report dashboards for the current user
    @saved_dashboards = current_user.defect_filters.defect_filters.active.order(:name)

    @products = Product.includes(:client, :groupwares, :statuses)
      .select do |product|
      product.statuses.any? { |status| ['Pre Quality Assurance', 'End Of Quality Assurance'].include?(status.name) } &&
        Defect.published.where(product_id: product.id).exists?
    end

    @product_options = @products.map do |product|
      client_name = product.client&.name || 'No Client Assigned'
      groupware_names = product.groupwares.any? ? product.groupwares.map(&:name).join(', ') : 'No Software'
      ["#{client_name} - #{groupware_names}", product.id]
    end

    # Check if we're loading a saved dashboard
    if params[:dashboard_id].present?
      load_saved_dashboard(params[:dashboard_id])
    end

    # Check if form was submitted via Apply button (not product change or dashboard load)
    form_submitted = params[:commit].present? && params[:product_change].blank? && params[:dashboard_id].blank?

    # Handle multiple product selection - convert to array if it's a string
    product_ids = if params[:product_id].is_a?(String)
                   params[:product_id].split(',')
                 else
                   Array(params[:product_id]).reject(&:blank?)
                 end
    
    # Metrics selection (configurable)
    default_metrics = %w[severity reporter status assignee ageing modules submodules]
    @selected_metrics = Array(params[:metrics]).presence || default_metrics

    # Get selected sub-options from params
    @selected_severities = Array(params[:severities]).reject(&:blank?)
    @selected_reporters = Array(params[:reporters]).reject(&:blank?)
    @selected_statuses = Array(params[:statuses]).reject(&:blank?)
    @selected_assignees = Array(params[:assignees]).reject(&:blank?)
    @selected_modules = Array(params[:modules]).reject(&:blank?)
    @selected_submodules = Array(params[:submodules]).reject(&:blank?)
    @selected_ageing_type = params[:ageing_type] || 'latest'

    # Filters
    start_date = parse_date(params[:start_date])
    end_date = parse_date(params[:end_date])

    # Create base scope for gathering available options (WITHOUT sub-filters)
    base_scope_for_options = Defect.published
    base_scope_for_options = base_scope_for_options.where(product_id: product_ids) if product_ids.any?
    base_scope_for_options = base_scope_for_options.where('defects.created_at >= ?', start_date.beginning_of_day) if start_date
    base_scope_for_options = base_scope_for_options.where('defects.created_at <= ?', end_date.end_of_day) if end_date

    # Gather available options based on the base scope (without sub-filters)
    @available_options = {}

    if product_ids.any?
      # Available severities
      if @selected_metrics.include?('severity')
        @available_options[:severities] = base_scope_for_options
          .where.not(priority: [nil, ''])
          .distinct
          .pluck(:priority)
          .map { |p| normalize_severity(p) }
          .uniq
          .sort
      end

      # Available reporters
      if @selected_metrics.include?('reporter')
        @available_options[:reporters] = base_scope_for_options
          .joins(:creator)
          .select('users.id, users.first_name, users.last_name')
          .distinct
          .map { |u| [u.id, "#{u.first_name} #{u.last_name}"] }
      end

      # Available statuses
      if @selected_metrics.include?('status')
        @available_options[:statuses] = base_scope_for_options
          .joins(:statuses)
          .select('statuses.id, statuses.name')
          .distinct
          .map { |s| [s.id, s.name] }
          .uniq { |_id, name| name }
      end

      # Available assignees
      if @selected_metrics.include?('assignee')
        @available_options[:assignees] = base_scope_for_options
          .joins(:users)
          .select('users.id, users.first_name, users.last_name')
          .distinct
          .map { |u| [u.id, "#{u.first_name} #{u.last_name}"] }
      end

      # Available modules
      if @selected_metrics.include?('modules')
        @available_options[:modules] = base_scope_for_options
          .joins(:qa_module)
          .where.not(qa_modules: { id: nil })
          .select('qa_modules.id, qa_modules.name')
          .distinct
          .map { |m| [m.id, m.name] }
      end

      # Available submodules (dependent on modules)
      if @selected_metrics.include?('submodules')
        @available_options[:submodules] = base_scope_for_options
          .joins('LEFT JOIN qa_modules submods ON submods.id = defects.submodule_id')
          .where.not(submods: { id: nil })
          .select('submods.id, submods.name, submods.parent_id')
          .distinct
          .map { |sm| [sm.id, sm.name, sm.parent_id] }
      end

      # Ageing options
      @available_options[:ageing_types] = [%w[Latest latest], %w[Oldest oldest]] if @selected_metrics.include?('ageing')
    end

    # ONLY calculate metrics if form was submitted via Apply button OR dashboard is loaded AND products are selected
    if (form_submitted || params[:dashboard_id].present?) && product_ids.any?
      # NOW create the filtered scope for metric calculations
      defects_scope = base_scope_for_options

      # Apply sub-filters for metric calculations
      # Filter: Severity (priority) - only if specific severities are selected
      if @selected_severities.any?
        all_values = @selected_severities.flat_map do |severity|
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

      # Apply other filters...
      # Filter: Reporter
      defects_scope = defects_scope.where(creator_id: @selected_reporters) if @selected_reporters.any?

      # Filter: Status
      if @selected_statuses.any?
        downcased_statuses = @selected_statuses.map(&:downcase)
        defects_scope = defects_scope.joins(:statuses).where('LOWER(statuses.name) IN (?)', downcased_statuses)
      end

      # Filter: Assignee
      defects_scope = defects_scope.joins(:users).where(users: { id: @selected_assignees }) if @selected_assignees.any?

      # Filter: Module
      defects_scope = defects_scope.where(qa_module_id: @selected_modules) if @selected_modules.any?

      # Filter: Submodule
      defects_scope = defects_scope.where(submodule_id: @selected_submodules) if @selected_submodules.any?

      # NOW calculate the metrics with the filtered data
      @defects_per_creator = if @selected_metrics.include?('reporter')
                               defects_scope
                                 .joins(:creator)
                                 .group('users.id', 'users.first_name', 'users.last_name')
                                 .count
                             else
                               {}
                             end

      @defects_per_status = if @selected_metrics.include?('status')
                              defects_scope
                                .joins(:statuses)
                                .group('statuses.id', 'statuses.name')
                                .count
                            else
                              {}
                            end

      @defects_per_severity = if @selected_metrics.include?('severity')
                                raw = defects_scope.group("LOWER(COALESCE(priority, 'unknown'))").count
                                raw.transform_keys { |k| normalize_severity(k) }
                              else
                                {}
                              end

      @defects_per_assignee = if @selected_metrics.include?('assignee')
                                defects_scope
                                  .joins(:users)
                                  .group('users.id', 'users.first_name', 'users.last_name')
                                  .count
                              else
                                {}
                              end

      @defects_per_module = if @selected_metrics.include?('modules')
                              defects_scope
                                .joins(:qa_module)
                                .group('qa_modules.id', 'qa_modules.name')
                                .count
                            else
                              {}
                            end

      @defects_per_submodule = if @selected_metrics.include?('submodules')
                                 defects_scope
                                   .joins('LEFT JOIN qa_modules submods ON submods.id = defects.submodule_id')
                                   .group('submods.id', 'submods.name')
                                   .count
                                   .reject { |(id, name), _| id.nil? || name.nil? }
                               else
                                 {}
                               end

      @defects_age_buckets = if @selected_metrics.include?('ageing')
                               ageing_scope = defects_scope.unscope(:order)

                               buckets = ageing_scope.group(<<~SQL.squish).count
                                 CASE
                                   WHEN defects.created_at >= NOW() - INTERVAL '7 days' THEN '0-7 days'
                                   WHEN defects.created_at >= NOW() - INTERVAL '14 days' THEN '8-14 days'
                                   WHEN defects.created_at >= NOW() - INTERVAL '30 days' THEN '15-30 days'
                                   ELSE '31+ days'
                                 END
                               SQL

                               ordered_buckets = {}
                               if @selected_ageing_type == 'latest'
                                 ['0-7 days', '8-14 days', '15-30 days', '31+ days'].each do |bucket|
                                   ordered_buckets[bucket] = buckets[bucket] || 0
                                 end
                               else
                                 ['31+ days', '15-30 days', '8-14 days', '0-7 days'].each do |bucket|
                                   ordered_buckets[bucket] = buckets[bucket] || 0
                                 end
                               end
                               ordered_buckets
                             else
                               {}
                             end
    else
      # Initialize empty metrics if form not submitted via Apply button
      @defects_per_creator = {}
      @defects_per_status = {}
      @defects_per_severity = {}
      @defects_per_assignee = {}
      @defects_per_module = {}
      @defects_per_submodule = {}
      @defects_age_buckets = {}
    end
  end

  def save_dashboard
    # Parse and prepare the filters for storage
    filters_data = if params[:defect_filter] && params[:defect_filter][:filters].is_a?(String)
                     JSON.parse(params[:defect_filter][:filters])
                   else
                     params[:defect_filter][:filters] || {}
                   end

    # Handle multiple product selection for storage
    product_ids = if params[:defect_filter][:product_id].is_a?(String)
                   params[:defect_filter][:product_id].split(',')
                 else
                   Array(params[:defect_filter][:product_id]).reject(&:blank?)
                 end
    product_id = product_ids.any? ? product_ids.first : nil

    @dashboard = current_user.defect_filters.build(
      name: params[:defect_filter][:name],
      product_id: product_id,
      filters: filters_data,
      filter_type: 'report',
      is_dashboard: true
    )

    # Audit fields
    @dashboard.created_by = current_user
    @dashboard.modified_by = current_user

    if @dashboard.save
      redirect_to reports_path, notice: 'Dashboard saved successfully!'
    else
      redirect_to reports_path(params.except(:defect_filter, :commit, :action, :controller)),
                  alert: "Failed to save dashboard: #{@dashboard.errors.full_messages.join(', ')}"
    end
  end

  def download_report
    require 'csv'
    authorize! :generate, :report

    product_ids = if params[:product_id].is_a?(String)
                   params[:product_id].split(',')
                 else
                   Array(params[:product_id]).reject(&:blank?)
                 end
    start_date = parse_date(params[:start_date])
    end_date = parse_date(params[:end_date])

    # Create base scope
    defects_scope = Defect.published
    defects_scope = defects_scope.where(product_id: product_ids) if product_ids.any?
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

  def load_saved_dashboard(dashboard_id)
    # Clean up the dashboard_id parameter (remove any "value+" corruption)
    clean_dashboard_id = dashboard_id.to_s.gsub(/value\+/, '').strip
    return if clean_dashboard_id.blank?

    # Use defect_filters scope since that's what you're loading
    dashboard = current_user.defect_filters.defect_filters.active.find_by(id: clean_dashboard_id)
    return unless dashboard

    # Apply the saved filters to the current params
    # For defect filters, we need to convert them to report parameters
    saved_filters = dashboard.sanitized_filters
    
    # Convert defect filter parameters to report parameters
    report_params = convert_defect_filters_to_report_params(saved_filters)
    
    # Delete all existing params except the ones we want to keep
    params.keys.each do |key|
      unless key == 'controller' || key == 'action'
        params.delete(key)
      end
    end
    
    # Set the dashboard_id
    params[:dashboard_id] = clean_dashboard_id
    
    # Set all the parameters from the saved dashboard
    report_params.each do |key, value|
      if value.present?
        params[key] = value 
      end
    end
    
    # Clear commit and product_change to prevent form submission logic
    params[:commit] = nil
    params[:product_change] = nil
  end

  def convert_defect_filters_to_report_params(defect_filters)
    report_params = {}
    
    # Map defect filter keys to report parameter keys
    defect_filters.each do |key, value|
      case key
      when 'product_id'
        if value.present?
          report_params['product_id'] = Array(value)
        end
      when 'user_id'
        if value.present?
          report_params['assignees'] = Array(value)
        end
      when 'qa_module_id'
        if value.present?
          report_params['modules'] = Array(value)
        end
      when 'submodule_id'
        if value.present?
          report_params['submodules'] = Array(value)
        end
      when 'priority'
        if value.present?
          # Convert priority to severities
          report_params['severities'] = Array(value).map { |p| normalize_severity(p) }
        end
      when 'status'
        if value.present?
          report_params['statuses'] = Array(value)
        end
      when 'start_date'
        if value.present?
          report_params['start_date'] = value
        end
      when 'end_date'
        if value.present?
          report_params['end_date'] = value
        end
      end
    end
    
    # Set default metrics based on what filters are available
    metrics = []
    metrics << 'severity' if report_params['severities'].present?
    metrics << 'reporter' if defect_filters['user_id'].present? # Use creator from defect filters
    metrics << 'status' if report_params['statuses'].present?
    metrics << 'assignee' if report_params['assignees'].present?
    metrics << 'modules' if report_params['modules'].present?
    metrics << 'submodules' if report_params['submodules'].present?
    metrics << 'ageing' # Always include ageing by default
    
    report_params['metrics'] = metrics.any? ? metrics : %w[severity reporter status assignee ageing modules submodules]
    
    report_params
  end

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
end