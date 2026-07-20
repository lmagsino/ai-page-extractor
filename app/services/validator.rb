# Validator: sanity-checks the OUTER shape of whatever the extractor returned
# before we trust it enough to store and display.
#
# With tool-use structured output (see Extractor), the schema is already
# enforced API-side, so this is belt-and-suspenders: it guards against
# valid-JSON-but-wrong-shape and gives us a clean, well-tested seam. It does
# NOT enforce per-field types — those vary per user prompt.
#
# Note (B1): `notes` is optional AND may be an empty string. The extractor's
# instructions explicitly allow `notes: ""`, so the schema must accept it —
# using `filled(:string)` here would reject the common empty-notes case and
# wrongly fail the job.
class Validator
  class ValidationError < StandardError; end

  SCHEMA = Dry::Schema.JSON do
    required(:items).array(:hash)
    optional(:notes).maybe(:string)
  end

  def self.call(data)
    result = SCHEMA.call(data)

    if result.errors.any?
      raise ValidationError, "Extraction result failed validation: #{result.errors.to_h}"
    end

    # Return string keys so validated output matches the extractor's JSON shape
    # and the DB round-trip (job.result). dry-schema's to_h symbolizes top-level
    # keys, which would otherwise desync the cache from the stored value.
    result.to_h.deep_stringify_keys
  end
end
