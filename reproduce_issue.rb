# Create a test product
product = Product.create!(document_name: "Test Product", client: Client.first || Client.create!(name: "Test Client"), user: User.first)
puts "Created Product: #{product.id}"

# Create a banking type and add to product
bt = BankingType.find_or_create_by!(name: "Test Banking Type")
unless product.banking_types.include?(bt)
  product.banking_types << bt 
  puts "Added Banking Type to Product"
end
puts "Banking Type: #{bt.id}"

# Verify association
puts "Product Banking Types Count: #{product.banking_types.count}"

# Create a defect
defect = Defect.create!(summary: "Test Defect", product: product, priority: "SEVERITY 1", statuses: [Status.first || Status.create!(name: "Open")], user_ids: [User.first.id], banking_type: bt)
puts "Created Defect: #{defect.id}"

# Simulate set_form_data logic
# Scenario 1: params[:product_id] is nil, @defect is set
@defect = defect
params = {}

@selected_product = if params[:product_id].present?
                      Product.find_by(id: params[:product_id])
                    elsif defined?(@defect) && @defect&.product_id.present?
                      @defect.product
                    end

puts "Selected Product: #{@selected_product&.id}"

@banking_types = if @selected_product
                   @selected_product.banking_types.order(:name)
                 else
                   []
                 end

puts "Banking Types Found: #{@banking_types.count}"
puts "Banking Types Names: #{@banking_types.map(&:name)}"

# Cleanup
defect.destroy
product.destroy
bt.destroy
