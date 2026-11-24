require_relative "../rails_helper"
require "rake"

RSpec.describe "checkout:reset" do
  before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?("checkout:reset") }

  it "deletes orders and restores stock to the configured initial balance" do
    product = Product.create!(sku: "RESET-ITEM", name: "Test item", initial_stock: 7, stock: 5)
    product.orders.create!(quantity: 2, design: "locked", idempotency_key: SecureRandom.uuid)

    Rake::Task["checkout:reset"].execute

    expect(Order.count).to eq(0)
    expect(product.reload.stock).to eq(7)
  end
end
