class StockInvariant < Data.define(:initial_stock, :remaining_stock, :active_hold_qty, :order_qty,
                                   :order_count, :distinct_idempotency_keys)
  def self.wait_for_pending!(timeout: 30)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until Reservations::REDIS.call("ZCARD", "confirmed:pending").zero?
      raise "Timed out waiting for confirmed:pending to drain" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      sleep 0.1
    end
  end

  def self.read(sku, design: "postgres")
    product = Product.find_by!(sku: sku)
    if design == "flashpoint"
      remaining, held = Reservations.inventory(sku)
      raise "Missing Redis stock for #{sku}" unless remaining
      orders = Order.where(design: "flashpoint")
    else
      remaining, held = product.stock, 0
      orders = Order.where(design: %w[naive locked])
    end
    new(product.initial_stock, Integer(remaining), held, orders.where(product: product).sum(:quantity),
        orders.count, orders.distinct.count(:idempotency_key))
  end

  def oversold
    [order_qty - initial_stock, 0].max
  end

  def valid?
    initial_stock == remaining_stock + active_hold_qty + order_qty &&
      oversold.zero? && order_count == distinct_idempotency_keys
  end
end
