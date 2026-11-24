class PersistOrderJob
  include Sidekiq::Job

  def perform(hold_id)
    redis = Reservations::REDIS
    sku, qty, key, state = redis.call("HMGET", "hold:#{hold_id}", "sku", "qty", "idem_key", "state")
    raise "Missing confirmed hold #{hold_id}" unless state == "confirmed"

    attributes = { product_id: Product.find_by!(sku: sku).id, quantity: Integer(qty),
                   idempotency_key: key, hold_id: hold_id, design: "flashpoint" }
    Order.transaction do |transaction|
      inserted = Order.insert_all([attributes], returning: [:id])
      if inserted.rows.empty? && !Order.exists?(attributes)
        raise "Conflicting order for confirmed hold #{hold_id}"
      end
      transaction.after_commit { redis.call("ZREM", "confirmed:pending", hold_id) }
    end
  end
end
