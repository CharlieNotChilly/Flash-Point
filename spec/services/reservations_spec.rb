require_relative "../rails_helper"
require_relative "../support/reservation_stock"

RSpec.describe Reservations do
  include_context "reservation stock"
  let(:now) { Time.utc(2026, 1, 1) }

  it "F1.1 stores the hold and expiry and deducts exactly the requested quantity" do
    hold = described_class.reserve(sku: sku, qty: 3, idem_key: sku, now: now)
    id = hold.fetch(:hold_id)
    expect(redis.call("HMGET", "hold:#{id}", "sku", "qty", "idem_key", "state")).to eq([sku, "3", sku, "held"])
    expect(redis.call("GET", stock_key)).to eq("7")
    expiry = (now.to_i + Reservations::TTL) * 1000
    expect(hold.fetch(:expires_at)).to eq(expiry)
    expect(redis.call("ZSCORE", expiry_key, id).to_i).to eq(expiry)
  end

  it "moves a live hold to pending and preserves it on release" do
    id = described_class.reserve(sku: sku, qty: 2, now: now).fetch(:hold_id)
    confirmed_ids << id
    expect(described_class.confirm(id, now: now)).to eq("CONFIRMED")
    expect(redis.call("ZSCORE", expiry_key, id)).to be_nil
    expect(redis.call("ZSCORE", "confirmed:pending", id).to_i).to eq(now.to_i * 1000)
    expect(described_class.release(id)).to eq(0)
    expect(redis.call("HGET", "hold:#{id}", "state")).to eq("confirmed")
    expect(redis.call("GET", stock_key)).to eq("8")
  end

  it "releases held stock exactly once and removes the expiry entry" do
    id = described_class.reserve(sku: sku, qty: 3, idem_key: sku).fetch(:hold_id)
    expect(described_class.release(id)).to eq(1)
    expect(described_class.release(id)).to eq(0)
    expect(redis.call("GET", stock_key)).to eq("10")
    expect(redis.call("EXISTS", "hold:#{id}")).to eq(0)
    expect(redis.call("ZCARD", expiry_key)).to eq(0)
  end

  it "F1.5 grants exactly 10 distinct holds to 50 concurrent buyers with stock 10" do
    ready = Queue.new
    start = Queue.new
    keys = Array.new(50) { SecureRandom.uuid }
    buyers = keys.map do |key|
      Thread.new do
        ready << true
        start.pop
        described_class.reserve(sku: sku, qty: 1, idem_key: key)
      end
    end
    buyers.size.times { ready.pop }
    buyers.size.times { start << true }
    ids = buyers.filter_map(&:value).map { |hold| hold.fetch(:hold_id) }
    redis.call("DEL", *keys.map { |key| "idem:#{key}" })
    expect(ids.size).to eq(10)
    expect(ids.uniq.size).to eq(10)
    expect(redis.call("ZRANGE", expiry_key, 0, -1)).to match_array(ids)
    expect(redis.call("GET", stock_key)).to eq("0")
  end
end
