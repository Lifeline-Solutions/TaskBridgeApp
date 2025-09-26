class ReportsController < ApplicationController
  before_action :authenticate_user!
  # ruby

  def index
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

    # Filters
    product_id = params[:product_id]
    start_date = parse_date(params[:start_date])
    end_date = parse_date(params[:end_date])

    defects_scope = Defect.published
    defects_scope = defects_scope.where(product_id: product_id) if product_id.present?
    defects_scope = defects_scope.where('created_at >= ?', start_date.beginning_of_day) if start_date
    defects_scope = defects_scope.where('created_at <= ?', end_date.end_of_day) if end_date

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
                              # Group by normalized, case-insensitive priority
                              raw = defects_scope
                                .group("LOWER(COALESCE(priority, 'unknown'))")
                                .count
                              # Normalize keys for display
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
                             defects_scope
                               .group(<<~SQL.squish)
                                 CASE
                                   WHEN created_at >= NOW() - INTERVAL '7 days' THEN '0-7 days'
                                   WHEN created_at >= NOW() - INTERVAL '14 days' THEN '8-14 days'
                                   WHEN created_at >= NOW() - INTERVAL '30 days' THEN '15-30 days'
                                   ELSE '31+ days'
                                 END
                               SQL
                               .count
                           else
                             {}
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
