require "digest/sha1"
require "redis-client"

class Reservations
  url = ENV.fetch("REDIS_URL", "redis://localhost:6379/0")
  if Rails.env.test?
    url = ENV.fetch("TEST_REDIS_URL") { URI.parse(url).tap { |uri| uri.path = "/15" }.to_s }
  end
  REDIS = RedisClient.config(url: url).new_pool(size: Integer(ENV.fetch("RAILS_MAX_THREADS", 5)))
  TTL = Integer(ENV.fetch("HOLD_TTL_SECONDS", 60))
  raise ArgumentError, "HOLD_TTL_SECONDS must be positive" unless TTL.positive?

  SCRIPTS = %w[reserve confirm release expire inventory].to_h do |name|
    source = Rails.root.join("lib/lua", "#{name}.lua").read
    [name, [Digest::SHA1.hexdigest(source), source]]
  end

  def self.reserve(sku:, qty:, idem_key: nil, now: Time.current)
    expires_at = (now.to_r * 1000).floor + TTL * 1000
    # The opaque ID carries the original deadline so retries still work after release deletes the hold.
    hold_id = "#{SecureRandom.uuid}.#{expires_at}"
    idem_key ||= hold_id
    result = run("reserve", ["stock:#{sku}", "hold:#{hold_id}", "holds:expiry:#{sku}", "idem:#{idem_key}"],
                 sku, qty, hold_id, idem_key, expires_at)
    return if result == "SOLD_OUT"

    { hold_id: result, expires_at: Integer(result.split(".").last) }
  end

  def self.confirm(hold_id, idem_key: hold_id, now: Time.current)
    run("confirm", ["hold:#{hold_id}", "confirmed:pending"], hold_id, (now.to_r * 1000).floor, idem_key)
  end

  def self.release(hold_id)
    run("release", ["hold:#{hold_id}"], hold_id)
  end

  def self.expire(sku, now: Time.current)
    run("expire", ["stock:#{sku}", "holds:expiry:#{sku}"], (now.to_r * 1000).floor)
  end

  def self.inventory(sku)
    run("inventory", ["stock:#{sku}", "holds:expiry:#{sku}"])
  end

  def self.run(name, keys, *args)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    begin
      eval_script(name, keys, args)
    rescue RedisClient::ConnectionError
      # The same keys and arguments are replayed if Redis restarts before its reply arrives.
      raise if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      sleep 0.1
      retry
    end
  end

  def self.eval_script(name, keys, args)
    sha, source = SCRIPTS.fetch(name)
    REDIS.call("EVALSHA", sha, keys.size, *keys, *args)
  rescue RedisClient::CommandError => error
    raise unless error.message.start_with?("NOSCRIPT")
    REDIS.call("EVAL", source, keys.size, *keys, *args)
  end
  private_class_method :run, :eval_script
end
