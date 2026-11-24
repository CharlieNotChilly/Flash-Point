RSpec.shared_context "reservation stock" do
  let(:sku) { "SPEC-#{SecureRandom.uuid}" }
  let(:redis) { Reservations::REDIS }
  let(:stock_key) { "stock:#{sku}" }
  let(:expiry_key) { "holds:expiry:#{sku}" }
  let(:confirmed_ids) { [] }
  before { redis.call("SET", stock_key, 10) }

  after do
    ids = redis.call("ZRANGE", expiry_key, 0, -1) + confirmed_ids
    redis.call("ZREM", "confirmed:pending", *confirmed_ids) if confirmed_ids.any?
    keys = ids.filter_map { |id| redis.call("HGET", "hold:#{id}", "idem_key") }
    redis.call("DEL", "idem:#{sku}", *keys.map { |key| "idem:#{key}" })
    redis.call("DEL", stock_key, expiry_key, *ids.map { |id| "hold:#{id}" })
  end
end
