class LabelsController < ApplicationController
  before_action :authenticate_user!

  def index
    scope = Label.where(deleted_on: nil)
    if params[:q].present?
      q = params[:q].strip.downcase
      scope = scope.where('LOWER(name) LIKE ?', "%#{q}%")
    end
    scope = scope.order(:name).limit([params.fetch(:limit, 100).to_i, 500].min)
    render json: scope.select(:id, :name)
  end

  def create
    name = params[:name].to_s.strip.gsub(/\s+/, '-').downcase
    return render json: { error: 'Name required' }, status: :unprocessable_entity if name.blank?

    label = Label.with_deleted.find_by('LOWER(name)=?', name)
    label.update(deleted_on: nil, deleted_by: nil) if label&.deleted_on.present?
    label ||= Label.new(name: name)
    AuditTrailService.apply_create(label, current_user)
    if label.save
      render json: { id: label.id, name: label.name }, status: :created
    else
      render json: { error: label.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end
end
