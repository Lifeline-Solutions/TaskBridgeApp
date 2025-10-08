require 'csv'
require 'axlsx'
class ReportsController < ApplicationController
  before_action :authenticate_user!

  def index
    authorize! :generate, :report
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

    # Check if form was submitted via Apply button (not product change)
    form_submitted = params[:commit].present? && params[:product_change].blank?

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
    product_id = params[:product_id]
    start_date = parse_date(params[:start_date])
    end_date = parse_date(params[:end_date])

    # Create base scope for gathering available options (WITHOUT sub-filters)
    base_scope_for_options = Defect.published
    base_scope_for_options = base_scope_for_options.where(product_id: product_id) if product_id.present?
    base_scope_for_options = base_scope_for_options.where('defects.created_at >= ?', start_date.beginning_of_day) if start_date
    base_scope_for_options = base_scope_for_options.where('defects.created_at <= ?', end_date.end_of_day) if end_date

    # Gather available options based on the base scope (without sub-filters)
    @available_options = {}

    if product_id.present?
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

    # ONLY calculate metrics if form was submitted via Apply button AND product is selected
    if form_submitted && product_id.present?
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

    # Convert array parameters to JSON strings for proper storage
    %w[metrics severities reporters statuses assignees modules submodules].each do |array_key|
      if filters_data[array_key].is_a?(Array)
        filters_data[array_key] = filters_data[array_key].to_json
      end
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
      redirect_to report_dashboards_path, notice: 'Dashboard saved successfully!'
    else
      redirect_to reports_path(params.except(:defect_filter, :commit, :action, :controller)), 
                  alert: "Failed to save dashboard: #{@dashboard.errors.full_messages.join(', ')}"
    end
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
end
