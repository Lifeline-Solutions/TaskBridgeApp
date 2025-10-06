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

    # Metrics selection (configurable)
    default_metrics = %w[severity reporter status assignee ageing modules submodules]
    @selected_metrics = Array(params[:metrics]).presence || default_metrics

    # Get selected sub-options from params FIRST
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
        .uniq { |id, name| name }
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
    @available_options[:ageing_types] = [['Latest', 'latest'], ['Oldest', 'oldest']] if @selected_metrics.include?('ageing')

    # NOW create the filtered scope for metric calculations
    defects_scope = base_scope_for_options

    # Apply sub-filters for metric calculations
    # Filter: Severity (priority)
    if @selected_severities.any?
      all_values = @selected_severities.flat_map do |severity|
        case severity.downcase
        when 'severity 1' then %w[severity\ 1 s1 high]
        when 'severity 2' then %w[severity\ 2 s2 medium]
        when 'severity 3' then %w[severity\ 3 s3 low]
        when 'severity 4' then %w[severity\ 4 s4 very\ low]
        else [severity.downcase]
        end
      end
      defects_scope = defects_scope.where("LOWER(COALESCE(defects.priority, 'unknown')) IN (?)", all_values)
    end

    # Filter: Reporter
    if @selected_reporters.any?
      defects_scope = defects_scope.where(creator_id: @selected_reporters)
    end

    # Filter: Status
    if @selected_statuses.any?
      downcased_statuses = @selected_statuses.map(&:downcase)
      defects_scope = defects_scope.joins(:statuses).where("LOWER(statuses.name) IN (?)", downcased_statuses)
    end

    # Filter: Assignee
    if @selected_assignees.any?
      defects_scope = defects_scope.joins(:users).where(users: { id: @selected_assignees })
    end

    # Filter: Module
    if @selected_modules.any?
      defects_scope = defects_scope.where(qa_module_id: @selected_modules)
    end

    # Filter: Submodule
    if @selected_submodules.any?
      defects_scope = defects_scope.where(submodule_id: @selected_submodules)
    end

    # NOW calculate the metrics with the filtered data

    # Reporter
    @defects_per_creator = if @selected_metrics.include?('reporter')
                             defects_scope
                               .joins(:creator)
                               .group('users.id', 'users.first_name', 'users.last_name')
                               .count
                           else
                             {}
                           end

    # Status
    @defects_per_status = if @selected_metrics.include?('status')
                            defects_scope
                              .joins(:statuses)
                              .group('statuses.id', 'statuses.name')
                              .count
                          else
                            {}
                          end

    # Severity (priority)
    @defects_per_severity = if @selected_metrics.include?('severity')
      raw = defects_scope.group("LOWER(COALESCE(priority, 'unknown'))").count
      raw.transform_keys { |k| normalize_severity(k) }
    else
      {}
    end

    # Assignee
    @defects_per_assignee = if @selected_metrics.include?('assignee')
                              defects_scope
                                .joins(:users)
                                .group('users.id', 'users.first_name', 'users.last_name')
                                .count
                            else
                              {}
                            end

    # Modules
    @defects_per_module = if @selected_metrics.include?('modules')
                            defects_scope
                              .joins(:qa_module)
                              .group('qa_modules.id', 'qa_modules.name')
                              .count
                          else
                            {}
                          end

    # Submodules (LEFT JOIN because optional)
    @defects_per_submodule = if @selected_metrics.include?('submodules')
                               defects_scope
                                 .joins('LEFT JOIN qa_modules submods ON submods.id = defects.submodule_id')
                                 .group('submods.id', 'submods.name')
                                 .count
                                 .reject { |(id, name), _| id.nil? || name.nil? }
                             else
                               {}
                             end

    # Ageing buckets
    @defects_age_buckets = if @selected_metrics.include?('ageing')
      # Remove any ordering before grouping
      ageing_scope = defects_scope.unscope(:order)
      
      buckets = ageing_scope.group(<<~SQL.squish).count
        CASE
          WHEN defects.created_at >= NOW() - INTERVAL '7 days' THEN '0-7 days'
          WHEN defects.created_at >= NOW() - INTERVAL '14 days' THEN '8-14 days'
          WHEN defects.created_at >= NOW() - INTERVAL '30 days' THEN '15-30 days'
          ELSE '31+ days'
        END
      SQL
      
      # Order based on selected ageing type
      if @selected_ageing_type == 'latest'
        ordered_buckets = {}
        ['0-7 days', '8-14 days', '15-30 days', '31+ days'].each do |bucket|
          ordered_buckets[bucket] = buckets[bucket] || 0
        end
        ordered_buckets
      else
        ordered_buckets = {}
        ['31+ days', '15-30 days', '8-14 days', '0-7 days'].each do |bucket|
          ordered_buckets[bucket] = buckets[bucket] || 0
        end
        ordered_buckets
      end
    else
      {}
    end

    # REMOVE the duplicate filtering section at the bottom (lines 270-310)
  end

  private

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