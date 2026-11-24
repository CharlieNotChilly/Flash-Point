require_relative "../rails_helper"
require_relative "../support/reservation_stock"

RSpec.describe "Reservation endpoints", type: :request do
  include ActiveSupport::Testing::TimeHelpers
  include_context "reservation stock"

  it "reserves, confirms, and acknowledges the pending order" do
    post "/reserve", params: { sku: sku, qty: 1 }, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body.fetch("hold_id")
    expect(response.parsed_body.fetch("expires_at")).to be_a(Integer)
    confirmed_ids << id
    post "/confirm", params: { hold_id: id }, as: :json
    expect(response).to have_http_status(:accepted)
    expect(response.parsed_body).to eq("status" => "pending")
  end

  it "F1.3 rejects confirmation at expiry without creating an order or a pending entry" do
    now = Time.utc(2026, 1, 1)
    id = Reservations.reserve(sku: sku, qty: 1, now: now).fetch(:hold_id)
    travel_to(now + Reservations::TTL) do
      expect { post "/confirm", params: { hold_id: id }, as: :json }.not_to change(Order, :count)
    end
    expect(response).to have_http_status(:gone)
    expect(response.parsed_body).to eq("error" => "HOLD_EXPIRED")
    expect(redis.call("ZSCORE", "confirmed:pending", id)).to be_nil
    expect(redis.call("ZSCORE", expiry_key, id)).to be_present
  end

  it "rejects invalid and unavailable quantities without creating a hold" do
    post "/reserve", params: { sku: sku, qty: -1 }, as: :json
    expect(response).to have_http_status(:bad_request)
    post "/reserve", params: { sku: sku, qty: 11 }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body).to eq("error" => "SOLD_OUT")
    expect(redis.call("ZCARD", expiry_key)).to eq(0)
    expect(redis.call("GET", stock_key)).to eq("10")
  end

  it "releases a hold and rejects subsequent confirmation" do
    id = Reservations.reserve(sku: sku, qty: 1).fetch(:hold_id)
    post "/release", params: { hold_id: id }, as: :json
    expect(response).to have_http_status(:no_content)
    post "/confirm", params: { hold_id: id }, as: :json
    expect(response).to have_http_status(:gone)
    expect(redis.call("GET", stock_key)).to eq("10")
  end
end
