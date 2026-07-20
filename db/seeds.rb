# Seeds the curated gallery shown on the public index (2A).
#
# These are pre-computed featured extractions so the demo always shows working
# output, even if a live fetch fails at the moment a reviewer visits. Idempotent:
# keyed on url so re-running updates in place rather than duplicating.

GALLERY = [
  {
    url: "https://books.toscrape.com/catalogue/category/books/travel_2/index.html",
    prompt: "Extract every book title and its price.",
    result: {
      "items" => [
        { "title" => "It's Only the Himalayas", "price" => "£45.17" },
        { "title" => "Full Moon over Noah's Ark", "price" => "£49.43" },
        { "title" => "See America: A Celebration of the National Parks", "price" => "£48.87" },
        { "title" => "Vagabonding: An Uncommon Guide to the Art of Long-Term World Travel", "price" => "£36.94" }
      ],
      "notes" => ""
    }
  },
  {
    url: "https://quotes.toscrape.com/",
    prompt: "Extract each quote with its author and the first tag.",
    result: {
      "items" => [
        { "quote" => "The world as we have created it is a process of our thinking.", "author" => "Albert Einstein", "tag" => "change" },
        { "quote" => "It is our choices, Harry, that show what we truly are, far more than our abilities.", "author" => "J.K. Rowling", "tag" => "abilities" },
        { "quote" => "There are only two ways to live your life.", "author" => "Albert Einstein", "tag" => "inspirational" }
      ],
      "notes" => ""
    }
  },
  {
    url: "https://www.iana.org/help/example-domains",
    prompt: "List each reserved example domain mentioned and what it is reserved for.",
    result: {
      "items" => [
        { "domain" => "example.com", "reserved_for" => "documentation examples" },
        { "domain" => "example.net", "reserved_for" => "documentation examples" },
        { "domain" => "example.org", "reserved_for" => "documentation examples" }
      ],
      "notes" => "Reserved by RFC 2606 / RFC 6761 for use in documentation."
    }
  }
]

GALLERY.each do |entry|
  job = ScrapeJob.find_or_initialize_by(url: entry[:url], prompt: entry[:prompt])
  job.featured = true
  job.status = "done"
  job.error_message = nil
  job.result = entry[:result]
  job.save!
end

puts "Seeded #{ScrapeJob.gallery.count} gallery extractions."
