require "resolv"
require "ipaddr"
require "timeout"
require "private_address_check"
require "private_address_check/tcpsocket_ext"

# Fetcher: retrieves raw HTML for a user-supplied URL, safely.
#
#   guard(url) ─► static GET (Faraday) ─► rendered? ──yes──► html
#      │                    │                       └─no──┐
#      │                    └─ Faraday error ─────────────┤
#      ▼                                                  ▼
#   BlockedError                                  headless Chrome (Ferrum)
#   (private/loopback/                            host-resolver pinned to the
#    metadata / bad scheme)                       validated public IP; container
#                                                 flags; hard wall-clock deadline
#
# SSRF is the central risk: the URL comes from an untrusted user and we fetch it
# server-side. Both fetch paths are guarded:
#   * scheme + up-front DNS check rejects private/loopback/link-local/metadata
#   * static path fetches inside `only_public_connections` so a redirect or
#     DNS-rebind to an internal IP is blocked at socket-connect time
#   * Ferrum path pins Chrome's own resolver to the pre-validated public IP
#     (Chrome does its own DNS; handing it a hostname alone is not enough)
class Fetcher
  class FetchError < StandardError; end
  class BlockedError < FetchError; end # SSRF / disallowed target

  MIN_TEXT_RATIO = 0.02 # visible-text bytes vs total HTML bytes
  STATIC_TIMEOUT = 10
  OPEN_TIMEOUT = 5
  BROWSER_TIMEOUT = 20
  BROWSER_DEADLINE = 25 # hard wall-clock kill for a hung Chrome (3A)
  USER_AGENT = "AIPageExtractor/1.0 (+https://github.com/lmagsino/ai-page-extractor)".freeze

  def self.call(url)
    new(url).call
  end

  def initialize(url)
    @url = url
  end

  def call
    uri = parse_and_guard!(@url)
    html = fetch_static(uri)
    return html if sufficiently_rendered?(html)

    fetch_with_browser(uri)
  rescue Faraday::Error => e
    # static fetch blew up (timeout, refused, etc.) — try a real browser
    begin
      fetch_with_browser(uri)
    rescue BlockedError
      raise
    rescue => browser_error
      raise FetchError, "Failed to fetch #{@url}: #{e.message} / #{browser_error.message}"
    end
  end

  # Pure helper, exposed for testing: is there enough visible text that we can
  # trust the static HTML, or does it look like a JS shell needing a browser?
  def sufficiently_rendered?(html)
    return false if html.nil? || html.empty?

    # Measure VISIBLE text only — Nokogiri#text otherwise counts inline <script>
    # bodies, which would make a JS shell look "rendered" and skip the browser.
    doc = Nokogiri::HTML(html)
    doc.css("script, style, noscript").remove
    text_length = doc.text.strip.length
    (text_length.to_f / html.length) >= MIN_TEXT_RATIO
  end

  private

  def parse_and_guard!(url)
    uri = URI.parse(url.to_s)
    unless uri.is_a?(URI::HTTP) && uri.hostname.present?
      raise BlockedError, "Only http(s) URLs are allowed"
    end
    # uri.hostname strips IPv6 brackets ("[::1]" -> "::1") so literals resolve.
    if PrivateAddressCheck.resolves_to_private_address?(uri.hostname)
      raise BlockedError, "Refusing to fetch a private or internal address (#{uri.hostname})"
    end
    uri
  rescue URI::InvalidURIError
    raise BlockedError, "Not a valid URL"
  end

  def fetch_static(uri)
    conn = Faraday.new do |f|
      f.options.timeout = STATIC_TIMEOUT
      f.options.open_timeout = OPEN_TIMEOUT
      f.headers["User-Agent"] = USER_AGENT
    end

    response = PrivateAddressCheck.only_public_connections { conn.get(uri.to_s) }
    raise FetchError, "HTTP #{response.status} fetching #{@url}" unless response.success?

    response.body
  rescue PrivateAddressCheck::PrivateConnectionAttemptedError
    raise BlockedError, "Redirected to a private or internal address"
  end

  def fetch_with_browser(uri)
    ip = resolve_public_ip!(uri.hostname)
    browser = Ferrum::Browser.new(
      headless: true,
      timeout: BROWSER_TIMEOUT,
      browser_options: {
        "no-sandbox" => nil,
        "disable-dev-shm-usage" => nil,
        "host-resolver-rules" => "MAP #{uri.hostname} #{ip}"
      }
    )

    Timeout.timeout(BROWSER_DEADLINE, FetchError, "Browser timed out fetching #{@url}") do
      browser.go_to(uri.to_s)
      begin
        browser.network.wait_for_idle(timeout: 10)
      rescue StandardError
        nil # idle wait is best-effort
      end
      browser.body
    end
  ensure
    browser&.quit
  end

  def resolve_public_ip!(host)
    ip = Resolv.getaddress(host)
    if PrivateAddressCheck.private_address?(IPAddr.new(ip))
      raise BlockedError, "Refusing to browse a private or internal address (#{host})"
    end
    ip
  rescue Resolv::ResolvError => e
    raise FetchError, "Could not resolve #{host}: #{e.message}"
  end
end
