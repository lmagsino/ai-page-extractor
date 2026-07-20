# Throttle: keeps outbound requests to a single host polite by enforcing a
# minimum interval between them. Called from the background job, so sleeping to
# space requests out is fine. Backed by Rails.cache (shared across workers).
class Throttle
  MIN_INTERVAL = 1.0 # seconds between requests to the same host

  def self.wait(host, now: Time.now.to_f)
    key = "throttle:#{host}"
    last = Rails.cache.read(key)

    if last
      elapsed = now - last.to_f
      pause(MIN_INTERVAL - elapsed) if elapsed < MIN_INTERVAL
    end

    Rails.cache.write(key, now, expires_in: 1.minute)
  end

  # Isolated so tests can assert on the wait without actually sleeping.
  def self.pause(seconds)
    sleep(seconds) if seconds.positive?
  end
end
