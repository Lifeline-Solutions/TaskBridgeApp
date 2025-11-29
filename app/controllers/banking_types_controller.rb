class BankingTypesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_product
  before_action :set_banking_type, only: %i[show edit update destroy remove]

  # GET /products/:product_id/banking_types
  def index
    # Banking types already assigned to this product
    @assigned_banking_types = @product.banking_types.active.order(:name)

    # Banking types available to add (not yet in this product)
    @available_banking_types = BankingType.active.not_in_product(@product.id).order(:name)

    # All banking types for type-ahead search (active only)
    @all_banking_types = BankingType.active.order(:name)
  end

  # GET /products/:product_id/banking_types/1
  def show; end

  # GET /products/:product_id/banking_types/new
  def new
    @banking_type = BankingType.new

    # Get all existing banking types for type-ahead
    @existing_banking_types = BankingType.active.order(:name)
  end

  # GET /products/:product_id/banking_types/1/edit
  def edit; end

  # POST /products/:product_id/banking_types
  def create
    banking_type_name = banking_type_params[:name]&.strip

    # Check if banking type already exists (case-insensitive)
    @banking_type = BankingType.find_by('LOWER(name) = ?', banking_type_name.downcase)

    if @banking_type
      # Banking type exists - add it to the product if not already added
      if @product.banking_types.include?(@banking_type)
        redirect_to product_banking_types_path(@product),
                    alert: "#{@banking_type.name} is already added to this project."
      else
        @product.banking_types << @banking_type

        activity('user_activity')
          .caused_by(current_user)
          .performed_on(@banking_type)
          .event('banking_type.add_to_project')
          .log("Added existing banking type to project #{@product.id}")

        redirect_to product_banking_types_path(@product),
                    notice: "#{@banking_type.name} has been added to this project."
      end
    else
      # Create new banking type and add to product
      @banking_type = BankingType.new(name: banking_type_name)
      audit_on_create(@banking_type)

      if @banking_type.save
        # Add to current product
        @product.banking_types << @banking_type

        activity('user_activity')
          .caused_by(current_user)
          .performed_on(@banking_type)
          .event('banking_type.create')
          .log("Created new banking type and added to project #{@product.id}")

        redirect_to product_banking_types_path(@product),
                    notice: 'New banking type created and added to this project.'
      else
        @existing_banking_types = BankingType.active.order(:name)
        render :new, status: :unprocessable_entity
      end
    end
  end

  # POST /products/:product_id/banking_types/add_existing
  def add_existing
    banking_type = BankingType.find(params[:banking_type_id])

    if @product.banking_types.include?(banking_type)
      flash[:alert] = "#{banking_type.name} is already in this project."
    else
      @product.banking_types << banking_type

      activity('user_activity')
        .caused_by(current_user)
        .performed_on(banking_type)
        .event('banking_type.add_to_project')
        .log("Added banking type #{banking_type.name} to project #{@product.id}")

      flash[:notice] = "#{banking_type.name} added to project."
    end

    redirect_to product_banking_types_path(@product)
  end

  # PATCH/PUT /products/:product_id/banking_types/1
  def update
    audit_on_update(@banking_type)

    if @banking_type.update(banking_type_params)
      activity('user_activity')
        .caused_by(current_user)
        .performed_on(@banking_type)
        .event('banking_type.update')
        .log('Banking type updated')

      redirect_to product_banking_types_path(@product),
                  notice: 'Banking type was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /products/:product_id/banking_types/1/remove
  def remove
    # Remove banking type from this product (doesn't delete the banking type)
    @product.banking_types.delete(@banking_type)

    activity('user_activity')
      .caused_by(current_user)
      .performed_on(@banking_type)
      .event('banking_type.remove_from_project')
      .log("Removed banking type #{@banking_type.name} from project #{@product.id}")

    redirect_to product_banking_types_path(@product),
                notice: "#{@banking_type.name} removed from this project."
  end

  # DELETE /products/:product_id/banking_types/1
  def destroy
    # Only soft delete if no other products are using this banking type
    if @banking_type.products.count <= 1
      if audit_soft_delete(@banking_type)
        # Also remove from this product
        @product.banking_types.delete(@banking_type)

        activity('user_activity')
          .caused_by(current_user)
          .performed_on(@banking_type)
          .event('banking_type.destroy')
          .log('Banking type deleted')

        redirect_to product_banking_types_path(@product),
                    notice: 'Banking type was successfully deleted.'
      else
        redirect_to product_banking_types_path(@product),
                    alert: 'Unable to delete banking type.'
      end
    else
      # Banking type is used by other projects, just remove from this one
      @product.banking_types.delete(@banking_type)
      redirect_to product_banking_types_path(@product),
                  notice: "Banking type removed from this project. It's still available in other projects."
    end
  end

  private

  def set_product
    @product = Product.find(params[:product_id])
  end

  def set_banking_type
    @banking_type = BankingType.find(params[:id])
  end

  def banking_type_params
    params.require(:banking_type).permit(:name)
  end
end
