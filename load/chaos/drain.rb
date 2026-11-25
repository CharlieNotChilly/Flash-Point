require "sidekiq/api"

deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 120
loop do
  break if Reservations::REDIS.call("ZCARD", "confirmed:pending").zero? &&
           Sidekiq::Queue.new.size.zero? && Sidekiq::RetrySet.new.size.zero? &&
           Sidekiq::WorkSet.new.size.zero?
  raise "Timed out waiting for pending confirmations and Sidekiq work" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
  sleep 0.25
end
