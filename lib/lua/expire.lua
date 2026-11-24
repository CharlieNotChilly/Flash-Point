local stock_key, expiry_key = KEYS[1], KEYS[2]
local ids = redis.call("ZRANGEBYSCORE", expiry_key, "-inf", ARGV[1])
if #ids > 0 and redis.call("EXISTS", stock_key) == 0 then
  return redis.error_reply("missing stock during expiry")
end
for _, id in ipairs(ids) do
  local key = "hold:" .. id
  if redis.call("HGET", key, "state") == "held" then
    redis.call("INCRBY", stock_key, redis.call("HGET", key, "qty"))
    redis.call("DEL", key)
  end
  redis.call("ZREM", expiry_key, id)
end
return #ids
