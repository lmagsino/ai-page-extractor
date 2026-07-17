# ScrapeJob: one extraction request and its lifecycle.
#
# State machine (status enum, string-backed):
#
#   pending ──► fetching ──► extracting ──► done
#      │           │             │
#      └───────────┴─────────────┴──► failed  (error_message set; user can resubmit)
#
# Each transition is driven by ScrapeJobProcessor as it walks the
# fetch -> clean -> extract -> validate pipeline. `featured` marks curated
# gallery items surfaced on the public index; ordinary user runs stay unlisted
# (viewable only via their own show URL).
class ScrapeJob < ApplicationRecord
  STATUSES = %w[pending fetching extracting done failed].freeze

  enum :status, STATUSES.index_with(&:itself), default: "pending", validate: true

  validates :url, presence: true,
                  format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]),
                            message: "must be a valid http(s) URL" }
  validates :prompt, presence: true

  scope :gallery, -> { where(featured: true).order(created_at: :desc) }

  # Parsed extraction result, or nil if not done / unparseable.
  def result
    return nil if result_json.blank?

    JSON.parse(result_json)
  rescue JSON::ParserError
    nil
  end

  def result=(hash)
    self.result_json = hash.nil? ? nil : hash.to_json
  end
end
