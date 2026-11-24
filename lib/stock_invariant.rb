class StockInvariant < Data.define(:initial_stock, :remaining_stock, :active_hold_qty, :order_qty,
                                   :order_count, :distinct_idempotency_keys)
  def self.read(sku)
    product = Product.find_by!(sku: sku)
    new(product.initial_stock, product.stock, 0, product.orders.sum(:quantity),
        Order.count, Order.distinct.count(:idempotency_key))
  end

  def oversold
    [order_qty - initial_stock, 0].max
  end

  def valid?
    initial_stock == remaining_stock + active_hold_qty + order_qty &&
      oversold.zero? && order_count == distinct_idempotency_keys
  end
end
