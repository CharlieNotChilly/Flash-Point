require_relative "../rails_helper"
require_relative "../../lib/stock_invariant"

RSpec.describe StockInvariant do
  let(:product) { Product.create!(sku: "CHECK", name: "Test item", initial_stock: 5, stock: 2) }

  it "sums units across orders and reconciles the remaining stock" do
    [1, 2].each do |qty|
      product.orders.create!(quantity: qty, design: "locked", idempotency_key: SecureRandom.uuid)
    end

    report = described_class.read(product.sku)
    expect(report).to be_valid
    expect(report.order_qty).to eq(3)
    expect(report.active_hold_qty).to eq(0)
    expect(report.oversold).to eq(0)
  end

  it "detects missing stock even when orders are below the initial allocation" do
    report = described_class.read(product.sku)
    expect(report).not_to be_valid
    expect(report.oversold).to eq(0)
  end

  it "reports the number of units over the allocation" do
    report = described_class.new(5, 0, 0, 7, 7, 7)
    expect(report).not_to be_valid
    expect(report.oversold).to eq(2)
  end

  it "fails on repeated keys even if quantities balance" do
    expect(described_class.new(5, 2, 0, 3, 3, 2)).not_to be_valid
  end
end
