# Rate limiting for cost control. Every extraction submit spins up a fetch and a
# paid Claude call, so a public URL must be bounded (this was promoted to a
# launch-blocker in the eng review, not a nice-to-have).
#
# Two throttles on POST /scrapes:
#   * per-IP    — stop one visitor from hammering it
#   * global    — a hard daily ceiling that bounds the total bill regardless of
#                 how many IPs show up (per-IP alone is defeated by rotation)
#
# NOTE: per-IP limits are trivially bypassed with rotating IPs — the real
# spend ceiling is the Anthropic account budget alarm (see config/deploy docs).
# This is defense in depth, not the last line.
class Rack::Attack
  SUBMIT_PATH = "/scrapes".freeze

  def self.submit?(req)
    req.post? && req.path == SUBMIT_PATH
  end

  # Per-IP: 10 submits/hour.
  throttle("scrapes/ip", limit: 10, period: 1.hour) do |req|
    req.ip if submit?(req)
  end

  # Global: 200 submits/day across everyone — the cost ceiling.
  throttle("scrapes/global-daily", limit: 200, period: 1.day) do |req|
    "global" if submit?(req)
  end

  self.throttled_responder = lambda do |request|
    match = request.env["rack.attack.match_data"] || {}
    retry_after = match[:period].to_i
    [
      429,
      { "Content-Type" => "text/plain", "Retry-After" => retry_after.to_s },
      [ "Rate limit reached. This is a cost-limited demo — please try again later.\n" ]
    ]
  end
end
