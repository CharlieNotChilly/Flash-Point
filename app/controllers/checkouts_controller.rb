class CheckoutsController < ApplicationController
  before_action :read_checkout_params

  def naive
    checkout(Product.all)
  end

  def locked
    checkout(Product.lock)
  end

  private

  def read_checkout_params
    @sku = params.expect(:sku)
    qty = params[:qty].to_s
    if qty.match?(/\A[1-9][0-9]*\z/)
      @quantity = qty.to_i
    else
      render json: { error: "INVALID_QUANTITY" }, status: :bad_request
    end
  end

  def checkout(products)
    # Both writes commit together. Only the locked relation protects the stock read.
    order = Product.transaction do
      product = products.find_by!(sku: @sku)
      next if product.stock < @quantity

      product.update!(stock: product.stock - @quantity)
      product.orders.create!(quantity: @quantity, design: action_name, idempotency_key: SecureRandom.uuid)
    end

    if order
      render json: { order_id: order.id }, status: :created
    else
      render json: { error: "SOLD_OUT" }, status: :conflict
    end
  end
end
