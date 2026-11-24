Product.find_or_create_by!(sku: "FLASH-1") do |product|
  product.name = "Flash sale product"
  product.initial_stock = 1000
  product.stock = 1000
end
