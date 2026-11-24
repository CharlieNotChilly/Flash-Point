local stock_key, hold_key, expiry_key = KEYS[1], KEYS[2], KEYS[3]
local sku, qty, hold_id, idem_key, expires_at = unpack(ARGV)
if not string.match(qty, "^[1-9]%d*$") then
  return redis.error_reply("invalid quantity")
end

if tonumber(redis.call("GET", stock_key) or "0") < tonumber(qty) then
  return "SOLD_OUT"
end

redis.call("DECRBY", stock_key, qty)
redis.call("HSET", hold_key, "sku", sku, "qty", qty, "idem_key", idem_key, "state", "held")
redis.call("ZADD", expiry_key, expires_at, hold_id)
return "HELD"
