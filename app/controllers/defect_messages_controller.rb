class DefectMessagesController < ApplicationController
  before_action :authorize_user!
  before_action :set_defect
  before_action :set_defect_message, only: [:edit, :update, :destroy]

  def create
    @defect_message = @defect.defect_messages.build(defect_message_params)
    @defect_message.user = current_user
    @defect_message.defect_unique = @defect.defect_unique

    if @defect_message.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @defect, notice: "Message created successfully." }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @defect_message.update(defect_message_params)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @defect, notice: "Message updated successfully." }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @defect_message.destroy
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @defect, notice: "Message deleted successfully." }
    end
  end

  private

  def set_defect
    @defect = Defect.find(params[:defect_id])
  end

  def set_defect_message
    @defect_message = @defect.defect_messages.find(params[:id])
  end

  def defect_message_params
    params.require(:defect_message).permit(:content)
  end
end
