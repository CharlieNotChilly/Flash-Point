thread_count = Integer(ENV.fetch("RAILS_MAX_THREADS", 5))
threads thread_count, thread_count
workers Integer(ENV.fetch("WEB_CONCURRENCY", 4))
port ENV.fetch("PORT", 3000)
