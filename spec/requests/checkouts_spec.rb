require_relative "../rails_helper"

RSpec.describe "PostgreSQL checkouts", type: :request do
  %w[naive locked].each do |design|
    describe "POST /#{design}/checkout" do
      let!(:product) { Product.create!(sku: "SPEC-ITEM", name: "Test item", stock: 2, initial_stock: 2) }

      def checkout(design, product, quantity)
        post "/#{design}/checkout", params: { sku: product.sku, qty: quantity }, as: :json
      end

      it "sells the last units to one buyer and records the order" do
        expect { checkout(design, product, 2) }.to change(Order, :count).by(1)
        expect(response).to have_http_status(:created)
        order = Order.find(response.parsed_body.fetch("order_id"))
        expect(order).to have_attributes(product: product, quantity: 2, design: design, hold_id: nil)
        expect(order.idempotency_key).to be_present
        expect(product.reload.stock).to eq(0)
      end

      it "rejects a request larger than the remaining stock" do
        expect { checkout(design, product, 3) }.not_to change(Order, :count)
        expect(response).to have_http_status(:conflict)
        expect(response.parsed_body).to eq("error" => "SOLD_OUT")
        expect(product.reload.stock).to eq(2)
      end

      it "rejects a negative quantity without changing stock" do
        expect { checkout(design, product, -1) }.not_to change(Order, :count)
        expect(response).to have_http_status(:bad_request)
        expect(product.reload.stock).to eq(2)
      end
    end
  end
end
