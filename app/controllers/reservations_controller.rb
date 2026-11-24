class ReservationsController < ApplicationController
  def reserve
    sku = params.expect(:sku)
    qty = params[:qty].to_s
    unless qty.match?(/\A[1-9][0-9]*\z/)
      return render json: { error: "INVALID_QUANTITY" }, status: :bad_request
    end

    hold = Reservations.reserve(sku: sku, qty: qty, idem_key: request.headers["Idempotency-Key"])
    if hold
      render json: hold, status: :created
    else
      render json: { error: "SOLD_OUT" }, status: :conflict
    end
  end

  def confirm
    if Reservations.confirm(params.expect(:hold_id)) == "CONFIRMED"
      render json: { status: "pending" }, status: :accepted
    else
      render json: { error: "HOLD_EXPIRED" }, status: :gone
    end
  end

  def release
    Reservations.release(params.expect(:hold_id))
    head :no_content
  end
end
