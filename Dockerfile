FROM ruby:3.4.9
WORKDIR /app
ENV BUNDLE_FROZEN=true
COPY .ruby-version Gemfile Gemfile.lock ./
RUN bundle install
COPY . .
