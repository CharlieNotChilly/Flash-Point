local stock_key, hold_key, expiry_key = KEYS[1], KEYS[2], KEYS[3]
local sku, qty, hold_id, idem_key, expires_at = unpack(ARGV)
local replay = redis.call("GET", KEYS[4])
if replay then return replay end

if not string.match(qty, "^[1-9]%d*$") then
  return redis.error_reply("invalid quantity")
end

if tonumber(redis.call("GET", stock_key) or "0") < tonumber(qty) then
  redis.call("SET", KEYS[4], "SOLD_OUT")
  return "SOLD_OUT"
end

redis.call("DECRBY", stock_key, qty)
redis.call("HSET", hold_key, "sku", sku, "qty", qty, "idem_key", idem_key, "state", "held")
redis.call("ZADD", expiry_key, expires_at, hold_id)
redis.call("SET", KEYS[4], hold_id)
return hold_id
