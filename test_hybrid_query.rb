# Create a test product
product = Product.create!(document_name: "Test Product Hybrid", client: Client.first || Client.create!(name: "Test Client"), user: User.first)
puts "Created Product: #{product.id}"

# Create a banking type with legacy product_id ONLY (no join record)
bt_legacy = BankingType.find_or_create_by!(name: "Legacy Banking Type")
# Manually set product_id since association is removed/commented out
BankingType.connection.execute("UPDATE banking_types SET product_id = '#{product.id}' WHERE id = '#{bt_legacy.id}'")
puts "Created Legacy Banking Type: #{bt_legacy.id}"

# Create a banking type with join record ONLY (new way)
bt_new = BankingType.find_or_create_by!(name: "New Banking Type")
unless product.banking_types.include?(bt_new)
  product.banking_types << bt_new 
end
puts "Created New Banking Type: #{bt_new.id}"

# Verify counts
puts "Legacy BT product_id: #{BankingType.find(bt_legacy.id).product_id}"
puts "Product Banking Types (association): #{product.banking_types.count}" # Should be 1 (only bt_new)

# Test Hybrid Query
hybrid_types = BankingType.left_joins(:products)
                 .where("banking_types_products.product_id = :pid OR banking_types.product_id = :pid", pid: product.id)
                 .distinct
                 .order(:name)

puts "Hybrid Query Count: #{hybrid_types.count}"
puts "Hybrid Query Names: #{hybrid_types.map(&:name)}"

# Cleanup
product.destroy
bt_legacy.destroy
bt_new.destroy
