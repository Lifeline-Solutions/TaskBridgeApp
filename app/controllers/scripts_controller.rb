class ScriptsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_software
  before_action :set_groupware

  def show_index
    if params[:groupware_id]
      groupware = Groupware.find(params[:groupware_id])
      scripts = groupware.scripts
    else
      scripts = Script.all
    end

    render json: scripts
  end

  def new
    @script = Script.new
  end

  def create
    @script = @groupware.scripts.build(script_params)
    @script.software = @software
    audit_on_create(@script)

    respond_to do |format|
      if @script.save
        activity('user_activity')
          .caused_by(current_user)
          .performed_on(@script)
          .event('script.create')
          .with_properties(software_id: @software.id, groupware_id: @groupware.id)
          .log('Script created')
        format.html { redirect_to software_groupware_path(@software, @groupware), notice: 'Script was successfully created.' }
      else
        Rails.logger.debug @script.errors.full_messages
        format.html { render :new, status: :unprocessable_entity }
      end
    end
  end

  def edit; end

  def update
    # Controller seems to be updating groupware; keep audit on that record
    audit_on_update(@groupware)
    respond_to do |format|
      if @groupware.update(groupware_params)
        format.html { redirect_to software_path(@software), notice: 'Groupware was successfully updated.' }
      else
        format.html { render :edit, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    if audit_soft_delete(@groupware)
      # soft-deleted
    else
      @groupware.destroy
    end
    respond_to do |format|
      format.html { redirect_to software_path(@software), notice: 'Groupware was successfully deleted.' }
    end
  end

  private

  def set_software
    @software = Software.find(params[:software_id])
  end

  def set_groupware
    @groupware = Groupware.find(params[:groupware_id])
  end

  def script_params
    params.require(:script).permit(:name, :description)
  end
end
