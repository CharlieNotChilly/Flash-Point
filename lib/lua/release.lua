local hold_key, hold_id = KEYS[1], ARGV[1]
if redis.call("HGET", hold_key, "state") ~= "held" then return 0 end

local sku = redis.call("HGET", hold_key, "sku")
redis.call("INCRBY", "stock:" .. sku, redis.call("HGET", hold_key, "qty"))
redis.call("ZREM", "holds:expiry:" .. sku, hold_id)
redis.call("DEL", hold_key)
return 1
