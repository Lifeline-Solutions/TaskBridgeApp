class AddProxyNameToProducts < ActiveRecord::Migration[7.2]
  def change
    add_column :products, :proxy_name, :string
  end
end
