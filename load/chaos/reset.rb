# Only run inside the disposable chaos project, between completed runs.
abort "Expected isolated chaos stack" unless ENV["CHAOS_PROJECT"] == "1"
redis = Reservations::REDIS
raise "Confirmations still pending" unless redis.call("ZCARD", "confirmed:pending").zero?
Order.where(design: "flashpoint").delete_all
# One local product, bounded by the fixed buyer count. Unlink only benchmark state.
redis.call("EVAL", <<~LUA, 0)
  for _, pattern in ipairs({"hold:*", "idem:*", "holds:expiry:*"}) do
    for _, key in ipairs(redis.call("KEYS", pattern)) do redis.call("UNLINK", key) end
  end
LUA
product = Product.find_by!(sku: "FLASH-1")
raise "Unexpected initial allocation" unless product.initial_stock == 1000
redis.call("SET", "stock:FLASH-1", product.initial_stock)
