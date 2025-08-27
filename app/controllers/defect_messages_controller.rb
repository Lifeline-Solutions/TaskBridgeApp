class DefectMessagesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_defect
  before_action :set_defect_message, only: %i[edit update destroy]
  load_and_authorize_resource through: :defect
  before_action :authorize_message_owner, only: %i[edit update destroy]

  def index
    @defect_messages = @defect.defect_messages
      .includes(:user, rich_text_content: :embeds)
      .where(archive_status: false, deleted_on: nil)
      .order(created_at: :desc)

    # Full-text search in ActionText body
    if params[:query].present?
      search_query = "%#{params[:query].strip}%"
      @defect_messages = @defect_messages
        .joins("LEFT JOIN action_text_rich_texts ON action_text_rich_texts.record_id = defect_messages.id AND action_text_rich_texts.record_type = 'DefectMessage'")
        .where('action_text_rich_texts.body ILIKE :q', q: search_query)
    end

    # Sorting
    @defect_messages = case params[:sort_by]
                       when 'oldest'
                         @defect_messages.order(created_at: :asc)
                       else
                         @defect_messages.order(created_at: :desc)
                       end

    # Pagination
    @per_page = (params[:per_page] || 10).to_i
    @page = (params[:page] || 1).to_i
    @total_count = @defect_messages.count
    @total_pages = (@total_count / @per_page.to_f).ceil
    @start_count = ((@page - 1) * @per_page) + 1
    @end_count = [@page * @per_page, @total_count].min

    @defect_messages = @defect_messages.offset((@page - 1) * @per_page).limit(@per_page)
  end

  def create
    @defect_message = @defect.defect_messages.build(defect_message_params)
    @defect_message.user = current_user

    if @defect_message.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to defect_path(@defect), notice: 'Message posted!' }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace('new_defect_message', partial: 'defect_messages/form', locals: { defect: @defect, defect_message: @defect_message })
        end
        format.html { render 'defect/show', status: :unprocessable_entity }
      end
    end
  end

  def update
    audit_on_update(@defect_message)
    if @defect_message.update(defect_message_params)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @defect, notice: 'Message updated successfully.' }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if audit_soft_delete(@defect_message)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @defect, notice: 'Message archived successfully.' }
      end
    else
      @defect_message.destroy
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @defect, notice: 'Message deleted permanently.' }
      end
    end

    redirect_to defect_path(@defect), notice: 'Message deleted successfully.'
  end

  private

  def authorize_message_owner
    return if @defect_message.user == current_user

    respond_to do |format|
      format.html { redirect_to defect_path(@defect), alert: 'You are not authorized to edit or delete this message.' }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(dom_id(@defect_message), partial: 'defect_messages/message', locals: { message: @defect_message }), status: :forbidden
      end
    end
  end

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
