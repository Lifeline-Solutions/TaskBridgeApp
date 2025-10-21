class DraftDefectMessagesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_defect
  before_action :set_draft, only: [:show, :update, :destroy]

  def show
    respond_to do |format|
      format.json { render json: { content: @draft.content&.to_trix_html } }
    end
  end

  def create
    @draft = DraftDefectMessage.create_or_update_for_user(
      @defect, 
      current_user, 
      draft_params.merge(modified_by_id: current_user.id)
    )

    if @draft.persisted?
      respond_to do |format|
        format.json { render json: { success: true, id: @draft.id } }
      end
    else
      respond_to do |format|
        format.json { render json: { errors: @draft.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def update
    if @draft.update(draft_params.merge(modified_by_id: current_user.id))
      respond_to do |format|
        format.json { render json: { success: true } }
      end
    else
      respond_to do |format|
        format.json { render json: { errors: @draft.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    # Use hard delete for drafts to avoid audit trail issues
    if @draft.destroy
      respond_to do |format|
        format.json { render json: { success: true } }
      end
    else
      respond_to do |format|
        format.json { render json: { errors: @draft.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def check
    @draft = DraftDefectMessage.find_for_user(@defect, current_user)
    
    respond_to do |format|
      format.json do
        if @draft
          render json: { 
            has_draft: true, 
            content: @draft.content&.to_trix_html,
            updated_at: @draft.updated_at.iso8601
          }
        else
          render json: { has_draft: false }
        end
      end
    end
  end

  private

  def set_defect
    @defect = Defect.find(params[:defect_id])
  end

  def set_draft
    @draft = DraftDefectMessage.find_for_user(@defect, current_user)
    head :not_found unless @draft
  end

  def draft_params
    params.require(:draft_defect_message).permit(:content, :mentions_data)
  end
end