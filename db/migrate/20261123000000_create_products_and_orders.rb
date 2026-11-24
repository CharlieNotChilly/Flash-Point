class CreateProductsAndOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :products do |t|
      t.string :sku, null: false, index: { unique: true }
      t.string :name, null: false
      t.integer :initial_stock, null: false
      t.integer :stock, null: false
    end

    create_table :orders do |t|
      t.references :product, null: false, foreign_key: true
      t.integer :quantity, null: false
      t.string :idempotency_key, null: false, index: { unique: true }
      t.string :hold_id, index: { unique: true }
      t.string :design, null: false
      t.datetime :created_at, null: false
    end
  end
end
