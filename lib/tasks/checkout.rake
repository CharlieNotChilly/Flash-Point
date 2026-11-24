namespace :checkout do
  desc "Delete orders and restore initial product stock between benchmark runs"
  task reset: :environment do
    Product.transaction do
      Order.delete_all
      Product.update_all("stock = initial_stock")
    end
  end
end
