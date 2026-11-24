#!/bin/sh
# Run against a freshly seeded Compose stack.
set -eu

curl -fsS http://127.0.0.1:3000/up > /dev/null
echo "PASS Rails health endpoint"

for setting in appendonly:yes appendfsync:always; do
  name=${setting%:*}
  expected=${setting#*:}
  actual=$(docker compose exec -T redis redis-cli --raw CONFIG GET "$name")
  test "$actual" = "$(printf '%s\n%s' "$name" "$expected")"
  echo "PASS Redis $name=$expected"
done

docker compose exec -T web bin/rails runner '
  require "sidekiq/api"
  require "timeout"
  expected = [["FLASH-1", 1000, 1000]]
  abort "Unexpected seed" unless Product.pluck(:sku, :initial_stock, :stock) == expected
  puts "PASS PostgreSQL seed FLASH-1 initial_stock=1000 stock=1000"
  # Compose can return before Sidekiq sends its first heartbeat.
  Timeout.timeout(15, Timeout::Error, "No registered Sidekiq worker") do
    sleep 1 until Sidekiq::ProcessSet.new.size.positive?
  end
  puts "PASS Sidekiq worker registered in Redis"
'

test -n "$(docker compose ps --status running -q sweeper)"
docker compose logs --since 5s sweeper | grep -q 'sweeper heartbeat'
echo "PASS sweeper running with a recent heartbeat"
