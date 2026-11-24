local hold_key, pending_key = KEYS[1], KEYS[2]
local hold_id, now = ARGV[1], tonumber(ARGV[2])
local sku = redis.call("HGET", hold_key, "sku")
if not sku then return "HOLD_EXPIRED" end
if redis.call("HGET", hold_key, "idem_key") ~= ARGV[3] then return "KEY_MISMATCH" end
if redis.call("HGET", hold_key, "state") == "confirmed" then return "CONFIRMED" end

local expiry_key = "holds:expiry:" .. sku
local expiry = redis.call("ZSCORE", expiry_key, hold_id)
if not expiry or tonumber(expiry) <= now then return "HOLD_EXPIRED" end

redis.call("HSET", hold_key, "state", "confirmed")
redis.call("ZREM", expiry_key, hold_id)
redis.call("ZADD", pending_key, now, hold_id)
return "CONFIRMED"
