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

  SCRIPTS = %w[reserve confirm release].to_h do |name|
    source = Rails.root.join("lib/lua", "#{name}.lua").read
    [name, [Digest::SHA1.hexdigest(source), source]]
  end

  def self.reserve(sku:, qty:, idem_key: nil, now: Time.current)
    hold_id = SecureRandom.uuid
    expires_at = (now.to_r * 1000).floor + TTL * 1000
    result = run("reserve", ["stock:#{sku}", "hold:#{hold_id}", "holds:expiry:#{sku}"],
                 sku, qty, hold_id, idem_key || hold_id, expires_at)
    return if result == "SOLD_OUT"

    { hold_id: hold_id, expires_at: expires_at }
  end

  def self.confirm(hold_id, now: Time.current)
    run("confirm", ["hold:#{hold_id}", "confirmed:pending"], hold_id, (now.to_r * 1000).floor)
  end

  def self.release(hold_id)
    run("release", ["hold:#{hold_id}"], hold_id)
  end

  def self.run(name, keys, *args)
    sha, source = SCRIPTS.fetch(name)
    REDIS.call("EVALSHA", sha, keys.size, *keys, *args)
  rescue RedisClient::CommandError => error
    raise unless error.message.start_with?("NOSCRIPT")
    REDIS.call("EVAL", source, keys.size, *keys, *args)
  end
  private_class_method :run
end
