local stock = redis.call("GET", KEYS[1])
local held = 0
for _, id in ipairs(redis.call("ZRANGE", KEYS[2], 0, -1)) do
  held = held + tonumber(redis.call("HGET", "hold:" .. id, "qty"))
end
return {stock or false, held}
