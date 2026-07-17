# AI Page Extractor

Give it a URL and a plain-English instruction — "extract every product name and
price" — and it fetches the page, cleans it up, and asks Claude to return
structured JSON. No per-site CSS selectors, no brittle scrapers to maintain.

> **Status:** in active development. The Rails 8 scaffold and infrastructure are
> in place; the extraction pipeline is being built out milestone by milestone
> (see [Roadmap](#roadmap)).

## What it does

```
┌──────────────┐   "extract every product name and price"
│  Any web URL │ ───────────────────────────────────────────►  Structured JSON
└──────────────┘                                                 (rendered as a table)
```

Point it at a listing page, an article, a directory — anything — describe what
you want in ordinary language, and get back clean, structured data you can read
or export. The instruction is the schema; you don't write one.

## How it works

The request runs through a background pipeline so the page stays responsive and
updates live as each stage completes:

```
POST /scrapes → ScrapeJob(pending) → enqueue background job
                                            │
   ┌────────────────────────────────────────┘
   ▼
 [cache hit? (url, prompt)] ──yes──► return cached result ─────────► done
   │ no
   ▼
 Fetch      static HTTP GET first (fast); fall back to headless Chrome
            only for JS-rendered pages. SSRF-guarded; respects robots.txt.
   ▼
 Clean      strip nav/script/style noise → convert to markdown
            (cuts token count before the model ever sees it)
   ▼
 Extract    Claude with enforced structured output (tool-use) →
            guaranteed-valid JSON, no "please return JSON and pray"
   ▼
 Validate   sanity-check the shape before we trust and store it
   ▼
 ScrapeJob(done) ──Turbo Stream──► the page updates live, no refresh
```

Failure at any stage lands the job in a `failed` state with a clear message —
never a silent hang.

## Tech stack

- **Rails 8.1** on **Ruby 3.3**
- **Solid Queue** — background job processing
- **Solid Cable** — Turbo Stream live updates (no polling)
- **Solid Cache** — short-TTL cache so repeat scrapes don't re-pay for Chrome or the API
- **Ferrum** — headless Chrome (via CDP) for JavaScript-rendered pages
- **Nokogiri** + **reverse_markdown** — HTML cleanup and markdown conversion
- **Anthropic Claude API** — the extraction engine (tool-use / structured output)
- **Kamal** + Docker — deployment
- **Minitest** — test suite

## Engineering notes

A few decisions worth calling out, because the interesting part of this project
is the reliability work, not the happy path:

- **Structured output over prompt-and-pray.** Extraction uses Claude's tool-use
  so the JSON contract is enforced by the API, not by regex-stripping markdown
  fences off a text response.
- **SSRF protection on both fetch paths.** User-supplied URLs are fetched
  server-side, so private/loopback/cloud-metadata addresses are blocked — on the
  headless-Chrome path too, where Chrome's own DNS resolution needs network-level
  pinning to prevent DNS-rebinding.
- **Designed for a cheap, always-on demo.** Headless Chrome is concurrency-capped
  and given a hard per-job wall-clock timeout so one pathological page can't OOM
  or freeze the box. A curated gallery of pre-run extractions means the demo never
  looks broken even if a live fetch fails.
- **Cost control is a first-class concern**, not an afterthought: caching,
  per-IP rate limiting, and a spend ceiling.

## Getting started

Requires Ruby 3.3.x (see `.ruby-version`) and an Anthropic API key.

```bash
git clone git@github.com:lmagsino/ai-page-extractor.git
cd ai-page-extractor
bundle install

export ANTHROPIC_API_KEY=your-key-here

bin/rails db:prepare
bin/jobs &          # start the Solid Queue worker
bin/rails server
```

Visit http://localhost:3000.

## Testing

```bash
bin/rails test
```

The goal is full coverage of the pipeline: every service, every error path, the
controller and job, an end-to-end journey test, and an extraction-quality eval
run against saved page fixtures.

## Roadmap

- [x] **M0** — Rails 8 scaffold, CI, repository setup
- [ ] **M1** — Core pipeline: model, fetch → clean → extract → validate, SSRF guard
- [ ] **M2** — Live updates (Turbo Streams), curated gallery, repeat-scrape cache
- [ ] **M3** — Deploy to a live URL, rate limiting, cost controls

## Responsible use

This tool fetches pages on your behalf. It honors `robots.txt`, identifies itself
with a clear User-Agent, and throttles requests per host. Point it at sites you
own or have permission to scrape.

## License

Personal portfolio project.
