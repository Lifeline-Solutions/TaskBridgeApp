class DefectFiltersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_defect_filter, only: %i[update destroy]

  def index
    @defect_filters = current_user.defect_filters.active.includes(:product).order(:name)
  end

  def create
    raw_filters = parse_filters_param(params.dig(:defect_filter, :filters) || params[:filters])
    permitted_filters = permit_filter_keys(raw_filters)

    @defect_filter = current_user.defect_filters.build(
      name: params.dig(:defect_filter, :name) || params[:name] || 'Unnamed filter',
      product_id: params.dig(:defect_filter, :product_id) || params[:product_id],
      filters: permitted_filters
    )

    # Audit fields
    @defect_filter.created_by = current_user
    @defect_filter.modified_by = current_user
    @defect_filter.archive_status = false

    if @defect_filter.save
      redirect_back fallback_location: index_show_defect_index_path(product_id: @defect_filter.product_id), notice: 'Filter saved'
    else
      redirect_back fallback_location: index_show_defect_index_path(product_id: params[:product_id]), alert: @defect_filter.errors.full_messages.to_sentence
    end
  end

  def update
    if params.dig(:defect_filter, :filters).present?
      raw_filters = parse_filters_param(params.dig(:defect_filter, :filters))
      @defect_filter.filters = permit_filter_keys(raw_filters)
    end

    @defect_filter.name = params.dig(:defect_filter, :name) if params.dig(:defect_filter, :name).present?
    @defect_filter.modified_by = current_user

    if @defect_filter.save
      redirect_back fallback_location: defect_filters_path, notice: 'Filter updated'
    else
      redirect_back fallback_location: defect_filters_path, alert: @defect_filter.errors.full_messages.to_sentence
    end
  end

  # Soft-delete (audit)
  def destroy
    @defect_filter.update(deleted_on: Time.current, deleted_by: current_user, archive_status: true)
    redirect_back fallback_location: defect_filters_path, notice: 'Filter deleted'
  end

  private

  def set_defect_filter
    @defect_filter = current_user.defect_filters.find(params[:id])
  end

  def parse_filters_param(filters_param)
    case filters_param
    when String
      begin
        JSON.parse(filters_param)
      rescue JSON::ParserError
        {}
      end
    when ActionController::Parameters
      filters_param.to_unsafe_h
    when Hash
      filters_param
    else
      {}
    end
  end

  def permit_filter_keys(raw_hash)
    raw = raw_hash.to_h.with_indifferent_access.slice(*DefectFilter::ALLOWED_FILTER_KEYS)
    # Normalize multi-value keys
    %w[label_ids status].each do |k|
      next unless raw_hash.key?(k)
      raw[k] = Array(raw_hash[k]).reject(&:blank?)
    end
    raw
  end
end