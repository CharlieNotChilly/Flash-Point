Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  post "naive/checkout" => "checkouts#naive"
  post "locked/checkout" => "checkouts#locked"
  post "reserve" => "reservations#reserve"
  post "confirm" => "reservations#confirm"
  post "release" => "reservations#release"
end
