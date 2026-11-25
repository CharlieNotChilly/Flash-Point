require_relative "../rails_helper"
require_relative "../support/reservation_stock"

RSpec.describe "Reservation endpoints", type: :request do
  include ActiveSupport::Testing::TimeHelpers
  include_context "reservation stock"

  before { allow(PersistOrderJob).to receive(:perform_async) }

  let(:headers) { { "Idempotency-Key" => sku } }

  it "reserves, confirms, and acknowledges the pending order" do
    post "/reserve", params: { sku: sku, qty: 1 }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body.fetch("hold_id")
    expect(response.parsed_body.fetch("expires_at")).to be_a(Integer)
    confirmed_ids << id
    post "/confirm", params: { hold_id: id }, headers: headers, as: :json
    expect(response).to have_http_status(:accepted)
    expect(response.parsed_body).to eq("status" => "pending")
  end

  it "keeps a confirmed order recoverable when enqueue loses its Redis connection" do
    id = Reservations.reserve(sku: sku, qty: 1, idem_key: sku).fetch(:hold_id)
    confirmed_ids << id
    allow(PersistOrderJob).to receive(:perform_async).and_raise(RedisClient::ConnectionError)
    post "/confirm", params: { hold_id: id }, headers: headers, as: :json
    expect(response).to have_http_status(:accepted)
    expect(redis.call("ZSCORE", "confirmed:pending", id)).to be_present
  end

  it "F1.3 rejects confirmation at expiry without creating an order or a pending entry" do
    now = Time.utc(2026, 1, 1)
    id = Reservations.reserve(sku: sku, qty: 1, idem_key: sku, now: now).fetch(:hold_id)
    travel_to(now + Reservations::TTL) do
      expect { post "/confirm", params: { hold_id: id }, headers: headers, as: :json }.not_to change(Order, :count)
    end
    expect(response).to have_http_status(:gone)
    expect(response.parsed_body).to eq("error" => "HOLD_EXPIRED")
    expect(redis.call("ZSCORE", "confirmed:pending", id)).to be_nil
    expect(redis.call("ZSCORE", expiry_key, id)).to be_present
  end

  it "rejects invalid and unavailable quantities without creating a hold" do
    post "/reserve", params: { sku: sku, qty: -1 }, headers: headers, as: :json
    expect(response).to have_http_status(:bad_request)
    post "/reserve", params: { sku: sku, qty: 11 }, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body).to eq("error" => "SOLD_OUT")
    expect(redis.call("ZCARD", expiry_key)).to eq(0)
    expect(redis.call("GET", stock_key)).to eq("10")
  end

  it "releases a hold and rejects subsequent confirmation" do
    id = Reservations.reserve(sku: sku, qty: 1, idem_key: sku).fetch(:hold_id)
    post "/release", params: { hold_id: id }, headers: headers, as: :json
    expect(response).to have_http_status(:no_content)
    post "/confirm", params: { hold_id: id }, headers: headers, as: :json
    expect(response).to have_http_status(:gone)
    expect(redis.call("GET", stock_key)).to eq("10")
  end

  it "requires a nonblank key on reserve and confirm" do
    post "/reserve", params: { sku: sku, qty: 1 }, as: :json
    expect(response).to have_http_status(:bad_request)
    expect(redis.call("GET", stock_key)).to eq("10")
    post "/confirm", params: { hold_id: "missing" }, headers: { "Idempotency-Key" => "  " }, as: :json
    expect(response).to have_http_status(:bad_request)
  end

  it "F1.4 replays the original reservation body, including after release" do
    reserve = -> { post "/reserve", params: { sku: sku, qty: 1 }, headers: headers, as: :json }
    reserve.call
    original = response.body
    id = response.parsed_body.fetch("hold_id")
    travel 1.second do
      reserve.call
      expect(response).to have_http_status(:created)
      expect(response.body).to eq(original)
      expect(redis.call("GET", stock_key)).to eq("9")
      post "/release", params: { hold_id: id }, as: :json
      reserve.call
      expect(response.body).to eq(original)
      expect(redis.call("GET", stock_key)).to eq("10")
      expect(redis.call("ZCARD", expiry_key)).to eq(0)
    end
  end

  it "replays a sold-out response after stock becomes available" do
    redis.call("SET", stock_key, 0)
    post "/reserve", params: { sku: sku, qty: 1 }, headers: headers, as: :json
    original = response.body
    redis.call("SET", stock_key, 10)
    post "/reserve", params: { sku: sku, qty: 1 }, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.body).to eq(original)
    expect(redis.call("GET", stock_key)).to eq("10")
  end

  it "F1.4 handles 20 concurrent duplicate requests with one hold and one pending confirmation" do
    reserve = concurrent_requests("/reserve", { sku: sku, qty: 1 }, headers)
    expect(reserve.uniq.size).to eq(1)
    status, body = reserve.first
    expect(status).to eq(201)
    id = JSON.parse(body).fetch("hold_id")
    confirmed_ids << id
    expect(redis.call("ZRANGE", expiry_key, 0, -1)).to eq([id])
    expect(redis.call("GET", stock_key)).to eq("9")

    post "/confirm", params: { hold_id: id }, headers: { "Idempotency-Key" => "wrong" }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(redis.call("HGET", "hold:#{id}", "state")).to eq("held")
    replies = concurrent_requests("/confirm", { hold_id: id }, headers)
    expect(replies.uniq).to eq([[202, { status: "pending" }.to_json]])
    first_confirmation = redis.call("ZSCORE", "confirmed:pending", id)
    expect(first_confirmation).to be_present
    travel 1.minute do
      post "/confirm", params: { hold_id: id }, headers: headers, as: :json
      expect(response.body).to eq(replies.first.last)
      expect(response).to have_http_status(:accepted)
      expect(redis.call("ZSCORE", "confirmed:pending", id)).to eq(first_confirmation)
    end
    expect(PersistOrderJob).to have_received(:perform_async).with(id).once
    Product.create!(sku: sku, name: "Retry test", stock: 10, initial_stock: 10)
    2.times { PersistOrderJob.new.perform(id) }
    expect(Order.where(hold_id: id).count).to eq(1)
  end

  def concurrent_requests(path, params, headers)
    ready = Queue.new
    start = Queue.new
    clients = Array.new(20) do
      Thread.new do
        session = ActionDispatch::Integration::Session.new(Rails.application)
        ready << true
        start.pop
        session.post(path, params: params, headers: headers, as: :json)
        [session.response.status, session.response.body]
      end
    end
    clients.size.times { ready.pop }
    clients.size.times { start << true }
    clients.map(&:value)
  end
end
