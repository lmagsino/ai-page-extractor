# Extractor: sends the cleaned page markdown + the user's natural-language
# instruction to Claude and gets structured data back.
#
# Uses TOOL-USE (structured output): the model is required to call the
# `extract_data` tool, whose input_schema defines the JSON shape. The contract
# is enforced API-side, so there is no "return only JSON" prompt and no regex
# fence-stripping to go wrong (1A). max_tokens is sized for content-rich pages
# so the flagship "extract every item" case isn't truncated (B2).
#
# Requires ANTHROPIC_API_KEY in the environment.
class Extractor
  class ExtractionError < StandardError; end

  API_URL = "https://api.anthropic.com/v1/messages".freeze
  MODEL = "claude-sonnet-5".freeze
  MAX_TOKENS = 8192 # generous: a long listing page can produce many items (B2)
  TOOL_NAME = "extract_data".freeze
  MAX_RETRIES = 2
  REQUEST_TIMEOUT = 60

  def self.call(markdown:, prompt:)
    new(markdown: markdown, prompt: prompt).call
  end

  def initialize(markdown:, prompt:)
    @markdown = markdown
    @prompt = prompt
  end

  def call
    api_key # fail fast if unconfigured
    response = with_retries { perform_request(request_body) }

    unless response.success?
      raise ExtractionError, "Claude API error #{response.status}: #{response.body}"
    end

    parse_response(response.body)
  end

  private

  def request_body
    {
      model: MODEL,
      max_tokens: MAX_TOKENS,
      system: system_prompt,
      tools: [ tool_schema ],
      tool_choice: { type: "tool", name: TOOL_NAME },
      messages: [ { role: "user", content: user_message } ]
    }
  end

  def tool_schema
    {
      name: TOOL_NAME,
      description: "Return the structured data extracted from the page content, following the user's instruction.",
      input_schema: {
        type: "object",
        properties: {
          items: {
            type: "array",
            items: { type: "object" },
            description: "One object per extracted record. Use the fields the user asked for; " \
                         "use null for a requested field that isn't present on an item."
          },
          notes: {
            type: "string",
            description: "Anything you couldn't find or were unsure about. Empty string if nothing to note."
          }
        },
        required: [ "items" ]
      }
    }
  end

  def system_prompt
    "You extract structured data from webpage content based on a user's instruction. " \
    "Call the #{TOOL_NAME} tool with the results. If a requested field is missing for an " \
    "item, use null rather than omitting it."
  end

  def user_message
    <<~MSG
      Instruction: #{@prompt}

      Page content (markdown):
      ---
      #{@markdown}
      ---
    MSG
  end

  def with_retries
    attempt = 0
    loop do
      begin
        response = yield
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
        raise ExtractionError, "Claude API unreachable: #{e.message}" if attempt >= MAX_RETRIES

        attempt += 1
        sleep retry_delay(attempt)
        next
      end

      return response unless retryable_status?(response.status)
      return response if attempt >= MAX_RETRIES

      attempt += 1
      sleep retry_delay(attempt)
    end
  end

  def retryable_status?(status)
    status == 429 || (500..599).cover?(status)
  end

  def retry_delay(attempt)
    2**attempt
  end

  def perform_request(body)
    conn.post do |req|
      req.headers["x-api-key"] = api_key
      req.headers["anthropic-version"] = "2023-06-01"
      req.headers["content-type"] = "application/json"
      req.body = body.to_json
    end
  end

  def conn
    @conn ||= Faraday.new(API_URL) { |f| f.options.timeout = REQUEST_TIMEOUT }
  end

  def api_key
    ENV.fetch("ANTHROPIC_API_KEY") do
      raise ExtractionError, "ANTHROPIC_API_KEY is not set"
    end
  end

  def parse_response(raw_body)
    body = JSON.parse(raw_body)
    block = Array(body["content"]).find { |c| c["type"] == "tool_use" && c["name"] == TOOL_NAME }
    raise ExtractionError, "Claude did not call #{TOOL_NAME}" if block.nil?

    input = block["input"]
    raise ExtractionError, "Tool call had no input" unless input.is_a?(Hash)

    input
  rescue JSON::ParserError => e
    raise ExtractionError, "Claude response was not valid JSON: #{e.message}"
  end
end
