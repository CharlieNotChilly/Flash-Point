require_relative "../rails_helper"
require_relative "../support/reservation_stock"
require_relative "../../lib/stock_invariant"

RSpec.describe ReservationMaintenance do
  include_context "reservation stock"
  let!(:product) { Product.create!(sku: sku, name: "Test product", initial_stock: 10, stock: 10) }
  let(:now) { Time.utc(2026, 1, 1) }

  def confirmed_hold(qty, key)
    id = Reservations.reserve(sku: sku, qty: qty, idem_key: key, now: now).fetch(:hold_id)
    Reservations.confirm(id, idem_key: key, now: now)
    confirmed_ids << id
    id
  end

  it "F1.2 returns expired units exactly once and preserves live and confirmed holds" do
    id = Reservations.reserve(sku: sku, qty: 3, idem_key: sku, now: now).fetch(:hold_id)
    live = Reservations.reserve(sku: sku, qty: 1, now: now + 1.second)
    confirmed_hold(2, "#{sku}-confirmed")
    allow(PersistOrderJob).to receive(:perform_async)
    described_class.sweep(now: now + Reservations::TTL - 0.001)
    expect(redis.call("GET", stock_key)).to eq("4")
    2.times { described_class.sweep(now: now + Reservations::TTL) }
    expect(redis.call("EXISTS", "hold:#{id}")).to eq(0)
    expect(redis.call("ZRANGE", expiry_key, 0, -1)).to eq([live[:hold_id]])
    expect(redis.call("GET", stock_key)).to eq("7")
  end

  it "F3.4 re-enqueues a lost confirmation and commits its order once across retries" do
    id = confirmed_hold(2, sku)
    allow(PersistOrderJob).to receive(:perform_async)
    described_class.sweep(now: now + 5)
    expect(PersistOrderJob).not_to have_received(:perform_async).with(id)
    described_class.sweep(now: now + 6)
    expect(PersistOrderJob).to have_received(:perform_async).with(id)
    expect { StockInvariant.wait_for_pending!(timeout: 0) }.to raise_error(/Timed out/)
    2.times { PersistOrderJob.new.perform(id) }
    expect(product.orders.sole).to have_attributes(quantity: 2, design: "flashpoint", hold_id: id, idempotency_key: sku)
    expect(redis.call("ZSCORE", "confirmed:pending", id)).to be_nil
    expect(StockInvariant.read(sku, design: "flashpoint")).to be_valid
  end

  it "keeps an unresolved pending record if a different order owns the unique key" do
    id = confirmed_hold(1, sku)
    product.orders.create!(design: "locked", quantity: 1, idempotency_key: sku)
    expect { PersistOrderJob.new.perform(id) }.to raise_error(/Conflicting order/)
    expect(redis.call("ZSCORE", "confirmed:pending", id)).to be_present
  end

  it "restores missing stock across held, pending, and already committed units" do
    Reservations.reserve(sku: sku, qty: 2, idem_key: "#{sku}-held", now: now)
    confirmed_hold(1, "#{sku}-pending")
    written = confirmed_hold(3, sku)
    PersistOrderJob.new.perform(written)
    # Simulate a worker death after PostgreSQL commits and before Redis acknowledges.
    redis.call("ZADD", "confirmed:pending", now.to_i * 1000, written)
    product.orders.create!(design: "locked", quantity: 9, idempotency_key: SecureRandom.uuid)
    redis.call("DEL", stock_key)
    described_class.restore_stock(product)
    expect(redis.call("GET", stock_key)).to eq("4")
    confirmed_ids.each { |id| PersistOrderJob.new.perform(id) }
    report = StockInvariant.read(sku, design: "flashpoint")
    expect(report).to be_valid
    expect(report.active_hold_qty).to eq(2)
    expect(report.order_qty).to eq(4)
    described_class.restore_stock(product)
    expect(redis.call("GET", stock_key)).to eq("4")
  end
end
