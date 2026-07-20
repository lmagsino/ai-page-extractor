# RobotsPolicy: minimal robots.txt honoring.
#
# Fetches the target host's /robots.txt, picks the rule group that applies to
# our user-agent (most specific non-* match, else "*"), and applies the standard
# longest-match Allow/Disallow rule to the requested path.
#
# Scope/limitation: prefix matching only — no `*` / `$` wildcard expansion.
# Fails OPEN: if robots.txt is missing, unreachable, or unparseable, the fetch
# is allowed (that's the convention). An explicit Disallow fails CLOSED.
class RobotsPolicy
  ROBOTS_TIMEOUT = 5

  def self.allowed?(uri, user_agent: Fetcher::USER_AGENT_TOKEN)
    txt = fetch_robots(uri)
    return true if txt.nil?

    new(txt, user_agent).allowed?(request_path(uri))
  rescue StandardError
    true # fail open on any fetch/parse trouble
  end

  def self.request_path(uri)
    path = uri.path.to_s
    path = "/" if path.empty?
    uri.query ? "#{path}?#{uri.query}" : path
  end

  def self.fetch_robots(uri)
    robots_url = "#{uri.scheme}://#{uri.host}#{uri.port ? ":#{uri.port}" : ""}/robots.txt"
    conn = Faraday.new do |f|
      f.options.timeout = ROBOTS_TIMEOUT
      f.options.open_timeout = ROBOTS_TIMEOUT
      f.headers["User-Agent"] = Fetcher::USER_AGENT
    end
    resp = conn.get(robots_url)
    resp.success? ? resp.body : nil
  rescue Faraday::Error
    nil
  end

  def initialize(robots_txt, user_agent)
    @rules = applicable_rules(parse_groups(robots_txt), user_agent)
  end

  # Longest-match Allow/Disallow; ties go to Allow. An empty Disallow matches
  # nothing (i.e. allow everything).
  def allowed?(path)
    best = nil # [pattern_length, allow?]
    @rules.each do |type, pattern|
      next if pattern.empty? # empty Disallow / Allow -> no constraint
      next unless path.start_with?(pattern)

      candidate = [ pattern.length, type == :allow ]
      best = candidate if best.nil? || candidate[0] > best[0] || (candidate[0] == best[0] && candidate[1])
    end

    best.nil? || best[1]
  end

  private

  # => [ {agents: [...], rules: [[:disallow, "/x"], ...]}, ... ]
  def parse_groups(txt)
    groups = []
    current = nil
    last_was_agent = false

    txt.to_s.each_line do |raw|
      line = raw.sub(/#.*/, "").strip
      next if line.empty?

      key, _, value = line.partition(":")
      key = key.strip.downcase
      value = value.strip

      case key
      when "user-agent"
        if !last_was_agent || current.nil?
          current = { agents: [], rules: [] }
          groups << current
        end
        current[:agents] << value.downcase
        last_was_agent = true
      when "disallow", "allow"
        current&.fetch(:rules) << [ key.to_sym, value ]
        last_was_agent = false
      else
        last_was_agent = false
      end
    end

    groups
  end

  def applicable_rules(groups, user_agent)
    ua = user_agent.downcase
    # Most specific non-"*" match wins (longest agent token that our UA contains).
    specific = groups
      .select { |g| g[:agents].any? { |a| a != "*" && !a.empty? && ua.include?(a) } }
      .max_by { |g| g[:agents].reject { |a| a == "*" }.map(&:length).max || 0 }

    chosen = specific || groups.find { |g| g[:agents].include?("*") }
    chosen ? chosen[:rules] : []
  end
end
