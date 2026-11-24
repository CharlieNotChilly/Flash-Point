class ReservationMaintenance
  def self.sweep(now: Time.current)
    Product.pluck(:sku).each { |sku| Reservations.expire(sku, now: now) }
    cutoff = (now.to_r * 1000).floor - 5000
    ids = Reservations::REDIS.call("ZRANGEBYSCORE", "confirmed:pending", "-inf", "(#{cutoff}")
    ids.each { |id| PersistOrderJob.perform_async(id) }
  end

  def self.restore_stock(product)
    sku = product.sku
    stock = "stock:#{sku}"
    expiry = "holds:expiry:#{sku}"
    pending = "confirmed:pending"
    Reservations::REDIS.with do |redis|
      until redis.call("EXISTS", stock) == 1
        # Retry if a hold changes or a worker acknowledges an order during the rebuild.
        redis.multi(watch: [stock, expiry, pending]) do |tx|
          next if redis.call("EXISTS", stock) == 1
          held_ids = redis.call("ZRANGE", expiry, 0, -1)
          active_qty = held_ids.sum { |id| Integer(redis.call("HGET", "hold:#{id}", "qty")) }
          pending_ids = []
          pending_qty = 0
          redis.call("ZRANGE", pending, 0, -1).each do |id|
            hold_sku, qty = redis.call("HMGET", "hold:#{id}", "sku", "qty")
            next unless hold_sku == sku
            pending_ids << id
            pending_qty += Integer(qty)
          end
          # A committed order can still be pending in Redis. Count that hold only once.
          orders = product.orders.where(design: "flashpoint").where.not(hold_id: pending_ids)
          remaining = product.initial_stock - orders.sum(:quantity) - pending_qty - active_qty
          raise "Negative recovered stock for #{sku}" if remaining.negative?
          tx.call("SET", stock, remaining, "NX")
        end
      end
    end
  end
end
