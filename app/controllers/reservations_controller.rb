class ReservationsController < ApplicationController
  before_action :require_idempotency_key, only: [:reserve, :confirm]

  def reserve
    sku = params.expect(:sku)
    qty = params[:qty].to_s
    unless qty.match?(/\A[1-9][0-9]*\z/)
      return render json: { error: "INVALID_QUANTITY" }, status: :bad_request
    end

    hold = Reservations.reserve(sku: sku, qty: qty, idem_key: @idem_key)
    if hold
      render json: hold, status: :created
    else
      render json: { error: "SOLD_OUT" }, status: :conflict
    end
  end

  def confirm
    case Reservations.confirm(params.expect(:hold_id), idem_key: @idem_key)
    when "CONFIRMED"
      render json: { status: "pending" }, status: :accepted
    when "KEY_MISMATCH"
      render json: { error: "KEY_MISMATCH" }, status: :conflict
    else
      render json: { error: "HOLD_EXPIRED" }, status: :gone
    end
  end

  def release
    Reservations.release(params.expect(:hold_id))
    head :no_content
  end

  private

  def require_idempotency_key
    @idem_key = request.headers["Idempotency-Key"]
    if @idem_key.blank?
      render json: { error: "IDEMPOTENCY_KEY_REQUIRED" }, status: :bad_request
    end
  end
end
