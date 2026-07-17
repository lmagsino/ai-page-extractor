# Cleaner: turns raw HTML into compact, LLM-friendly markdown.
#
#   raw HTML ─► strip noise (script/style/nav/footer/…) ─► reverse_markdown
#            ─► collapse blank lines ─► truncate at MAX_CHARS ─► Result
#
# Dropping the noise and converting to markdown cuts the token count
# substantially before the content is ever sent to the extraction API.
# Returns a Result carrying the text plus whether truncation happened, so the
# UI can surface a "page was truncated" note.
class Cleaner
  NOISE_SELECTORS = %w[script style noscript svg iframe nav footer header form].freeze
  MAX_CHARS = 20_000 # keep prompts cheap; chunk later for full-page coverage

  Result = Data.define(:text, :truncated)

  def self.call(html)
    new(html).call
  end

  def initialize(html)
    @html = html.to_s
  end

  def call
    doc = Nokogiri::HTML(@html)
    NOISE_SELECTORS.each { |selector| doc.css(selector).remove }

    markdown = ReverseMarkdown.convert(doc.to_html, unknown_tags: :bypass)
    markdown = markdown.gsub(/\n{3,}/, "\n\n").strip

    if markdown.length > MAX_CHARS
      Result.new(text: markdown[0...MAX_CHARS], truncated: true)
    else
      Result.new(text: markdown, truncated: false)
    end
  end
end
