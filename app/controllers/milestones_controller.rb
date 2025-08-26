class MilestonesController < ApplicationController
  # Minimal controller implementation to satisfy autoloader and provide basic actions.
  before_action :set_milestone, only: %i[show edit update destroy]

  def index
    @milestones = Milestone.all
  end

  def show; end

  def new
    @milestone = Milestone.new
  end

  def create
    @milestone = Milestone.new(milestone_params)
    if @milestone.save
      redirect_to @milestone, notice: 'Milestone created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @milestone.update(milestone_params)
      redirect_to @milestone, notice: 'Milestone updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @milestone.destroy
    redirect_to milestones_path, notice: 'Milestone deleted.'
  end

  private

  def set_milestone
    @milestone = Milestone.find(params[:id])
  end

  def milestone_params
    params.require(:milestone).permit(:product_id, :status_id, :percentage, :amount, :position)
  end
end
