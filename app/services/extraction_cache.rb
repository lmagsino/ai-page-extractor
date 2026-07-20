# ExtractionCache: short-TTL cache of validated results keyed on (url, prompt).
#
# A cache hit skips the whole expensive pipeline — no headless Chrome, no paid
# Claude call — which is the point: the demo's hottest paths (a reviewer hitting
# refresh, retrying, or re-running a gallery example) cost nothing after the
# first run (5A). Backed by Rails.cache (Solid Cache in production).
class ExtractionCache
  TTL = 1.hour

  def self.read(url, prompt)
    Rails.cache.read(key(url, prompt))
  end

  def self.write(url, prompt, result)
    Rails.cache.write(key(url, prompt), result, expires_in: TTL)
  end

  def self.key(url, prompt)
    "extraction:v1:#{Digest::SHA256.hexdigest("#{url}\n#{prompt}")}"
  end
end
