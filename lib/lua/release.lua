local hold_key, hold_id = KEYS[1], ARGV[1]
if redis.call("HGET", hold_key, "state") ~= "held" then return 0 end

local sku = redis.call("HGET", hold_key, "sku")
if redis.call("EXISTS", "stock:" .. sku) == 0 then
  return redis.error_reply("missing stock during release")
end
redis.call("INCRBY", "stock:" .. sku, redis.call("HGET", hold_key, "qty"))
redis.call("ZREM", "holds:expiry:" .. sku, hold_id)
redis.call("DEL", hold_key)
return 1
