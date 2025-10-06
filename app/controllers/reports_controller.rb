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

    defects_scope = Defect.published
    defects_scope = defects_scope.where(product_id: product_id) if product_id.present?
    defects_scope = defects_scope.where('defects.created_at >= ?', start_date.beginning_of_day) if start_date
    defects_scope = defects_scope.where('defects.created_at <= ?', end_date.end_of_day) if end_date

    # Gather available options for each metric based on the filtered defects
    @available_options = {}

    # Available severities
    if @selected_metrics.include?('severity')
      @available_options[:severities] = defects_scope
        .where.not(priority: [nil, ''])
        .distinct
        .pluck(:priority)
        .map { |p| normalize_severity(p) }
        .uniq
        .sort
    end

    # Available reporters
    if @selected_metrics.include?('reporter')
      @available_options[:reporters] = defects_scope
        .joins(:creator)
        .select('users.id, users.first_name, users.last_name')
        .distinct
        .map { |u| [u.id, "#{u.first_name} #{u.last_name}"] }
    end

    # Available statuses
    if @selected_metrics.include?('status')
      @available_options[:statuses] = defects_scope
        .joins(:statuses)
        .select('statuses.id, statuses.name')
        .distinct
        .map { |s| [s.id, s.name] }
        .uniq { |id, name| name }
    end

    # Available assignees
    if @selected_metrics.include?('assignee')
      @available_options[:assignees] = defects_scope
        .joins(:users)
        .select('users.id, users.first_name, users.last_name')
        .distinct
        .map { |u| [u.id, "#{u.first_name} #{u.last_name}"] }
    end

    # Available modules
    if @selected_metrics.include?('modules')
      @available_options[:modules] = defects_scope
        .joins(:qa_module)
        .where.not(qa_modules: { id: nil })
        .select('qa_modules.id, qa_modules.name')
        .distinct
        .map { |m| [m.id, m.name] }
    end

    # Available submodules (dependent on modules)
    if @selected_metrics.include?('submodules')
      @available_options[:submodules] = defects_scope
        .joins('LEFT JOIN qa_modules submods ON submods.id = defects.submodule_id')
        .where.not(submods: { id: nil })
        .select('submods.id, submods.name, submods.parent_id')
        .distinct
        .map { |sm| [sm.id, sm.name, sm.parent_id] }
    end

    # Ageing options
    @available_options[:ageing_types] = [['Latest', 'latest'], ['Oldest', 'oldest']] if @selected_metrics.include?('ageing')

    # NOW calculate the metrics with the filtered data

    # Reporter
    @defects_per_creator = if @selected_metrics.include?('reporter')
                             scope = defects_scope
                             scope = scope.joins(:creator).where(users: { id: @selected_reporters }) if @selected_reporters.any?
                             scope
                               .joins(:creator)
                               .group('users.id', 'users.first_name', 'users.last_name')
                               .count
                           else
                             {}
                           end

    # Status
    @defects_per_status = if @selected_metrics.include?('status')
                            scope = defects_scope
                            scope = scope.joins(:statuses).where(statuses: { name: @selected_statuses }) if @selected_statuses.any?
                            scope
                              .joins(:statuses)
                              .group('statuses.id', 'statuses.name')
                              .count
                          else
                            {}
                          end

    # Severity (priority)
    @defects_per_severity = if @selected_metrics.include?('severity')
      scope = defects_scope
      # Filter by selected severities if any are chosen
      if @selected_severities.any?
        # Build individual OR conditions
        or_conditions = @selected_severities.map do |severity|
          normalized_severity = severity.downcase
          case normalized_severity
          when 'severity 1'
            "LOWER(COALESCE(priority, 'unknown')) IN ('severity 1', 's1', 'high')"
          when 'severity 2'
            "LOWER(COALESCE(priority, 'unknown')) IN ('severity 2', 's2', 'medium')"
          when 'severity 3'
            "LOWER(COALESCE(priority, 'unknown')) IN ('severity 3', 's3', 'low')"
          else
            "LOWER(COALESCE(priority, 'unknown')) = '#{normalized_severity}'"
          end
        end
        
        # Join with OR
        scope = scope.where(or_conditions.join(' OR '))
      end
      
      raw = scope.group("LOWER(COALESCE(priority, 'unknown'))").count
      raw.transform_keys { |k| normalize_severity(k) }
    else
      {}
    end

    # Assignee
    @defects_per_assignee = if @selected_metrics.include?('assignee')
                              scope = defects_scope
                              scope = scope.joins(:users).where(users: { id: @selected_assignees }) if @selected_assignees.any?
                              scope
                                .joins(:users)
                                .group('users.id', 'users.first_name', 'users.last_name')
                                .count
                            else
                              {}
                            end

    # Modules
    @defects_per_module = if @selected_metrics.include?('modules')
                            scope = defects_scope
                            scope = scope.where(qa_module_id: @selected_modules) if @selected_modules.any?
                            scope
                              .joins(:qa_module)
                              .group('qa_modules.id', 'qa_modules.name')
                              .count
                          else
                            {}
                          end

    # Submodules (LEFT JOIN because optional)
    @defects_per_submodule = if @selected_metrics.include?('submodules')
                               scope = defects_scope
                               scope = scope.where(submodule_id: @selected_submodules) if @selected_submodules.any?
                               scope
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
      
      # Apply ordering to the base scope, not the grouped one
      if @selected_ageing_type == 'latest'
        # For latest, we'll handle ordering in the view or manually
        # Just get the counts without ordering
        buckets = ageing_scope.group(<<~SQL.squish).count
          CASE
            WHEN defects.created_at >= NOW() - INTERVAL '7 days' THEN '0-7 days'
            WHEN defects.created_at >= NOW() - INTERVAL '14 days' THEN '8-14 days'
            WHEN defects.created_at >= NOW() - INTERVAL '30 days' THEN '15-30 days'
            ELSE '31+ days'
          END
        SQL
        
        # Order the buckets manually for display
        ordered_buckets = {}
        ['0-7 days', '8-14 days', '15-30 days', '31+ days'].each do |bucket|
          ordered_buckets[bucket] = buckets[bucket] || 0
        end
        ordered_buckets
      else
        # For oldest, reverse the bucket order
        buckets = ageing_scope.group(<<~SQL.squish).count
          CASE
            WHEN defects.created_at >= NOW() - INTERVAL '7 days' THEN '0-7 days'
            WHEN defects.created_at >= NOW() - INTERVAL '14 days' THEN '8-14 days'
            WHEN defects.created_at >= NOW() - INTERVAL '30 days' THEN '15-30 days'
            ELSE '31+ days'
          END
        SQL
        
        # Order the buckets manually for display (oldest first)
        ordered_buckets = {}
        ['31+ days', '15-30 days', '8-14 days', '0-7 days'].each do |bucket|
          ordered_buckets[bucket] = buckets[bucket] || 0
        end
        ordered_buckets
      end
    else
      {}
    end

    # Filter: Severity (priority)
if params[:severities].present?
  all_values = params[:severities].flat_map do |severity|
    case severity.downcase
    when 'severity 1' then %w[severity 1 s1 high]
    when 'severity 2' then %w[severity 2 s2 medium]
    when 'severity 3' then %w[severity 3 s3 low]
    when 'severity 4' then %w[severity 4 s4 very low]
    else [severity.downcase]
    end
  end
  defects_scope = defects_scope.where("LOWER(COALESCE(defects.priority, 'unknown')) IN (?)", all_values)
end

# Filter: Reporter
if params[:reporters].present?
  defects_scope = defects_scope.where(creator_id: params[:reporters])
end

# Filter: Status
if params[:statuses].present?
  downcased_statuses = params[:statuses].map(&:downcase)
  defects_scope = defects_scope.joins(:statuses).where("LOWER(statuses.name) IN (?)", downcased_statuses)
end

# Filter: Assignee
if params[:assignees].present?
  defects_scope = defects_scope.joins(:users).where(users: { id: params[:assignees] })
end

# Filter: Module
if params[:modules].present?
  defects_scope = defects_scope.where(qa_module_id: params[:modules])
end

# Filter: Submodule
if params[:submodules].present?
  defects_scope = defects_scope.where(submodule_id: params[:submodules])
end

# Filter: Ageing (latest/oldest)
if params[:ageing_type].present?
  direction = params[:ageing_type] == 'latest' ? :desc : :asc
  defects_scope = defects_scope.order(created_at: direction)
end

  end

  def severity_aliases(severity)
    case severity.downcase
      when 'severity 1' then %w[severity 1 s1 high]
      when 'severity 2' then %w[severity 2 s2 medium]
      when 'severity 3' then %w[severity 3 s3 low]
      else [severity.downcase]
    end
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