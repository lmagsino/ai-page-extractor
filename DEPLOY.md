# Deploy

Deployment is via [Kamal](https://kamal-deploy.org) (Docker under the hood).
The app is a single container: Puma serves web requests and runs the Solid Queue
worker in-process (`SOLID_QUEUE_IN_PUMA: true`), so one small box is enough.

The image already includes Chromium for the headless-fetch path (see `Dockerfile`).

## One-time prerequisites

1. **Pick a host.** Any Linux box with Docker you can SSH into (Hetzner, a DO
   droplet, an EC2 instance). This was the design's highest-risk unknown, mainly
   because of Chromium's memory footprint — give it **at least 1 GB RAM**.
2. **A container registry** the host can pull from (Docker Hub, GHCR, etc.).
3. **A domain** (optional but recommended) pointed at the host for HTTPS.

## Configure

Edit `config/deploy.yml`:

- `image:` → `your-registry-user/ai_page_extractor`
- `servers.web:` → your host's IP
- `registry.server` / `registry.username` → your registry
- `proxy:` → uncomment and set `host:` to your domain for Let's Encrypt TLS
  (then set `config.assume_ssl` / `config.force_ssl` in `production.rb`)

Secrets (never commit raw values — `.kamal/secrets` reads from env / a manager):

```bash
export RAILS_MASTER_KEY=$(cat config/master.key)
export ANTHROPIC_API_KEY=sk-ant-...      # your real key
export KAMAL_REGISTRY_PASSWORD=...        # registry token
```

## Ship it

```bash
bin/kamal setup     # first deploy: installs Docker on the host, boots the app
# subsequent deploys:
bin/kamal deploy
```

Useful:

```bash
bin/kamal logs -f          # tail logs
bin/kamal app exec --interactive --reuse "bin/rails console"
```

## Cost controls (do this before sharing the URL)

Rate limiting ships in the app (`config/initializers/rack_attack.rb`): 10
submits/hour per IP and a global ceiling of 200/day. Per-IP limits are defeated
by rotating IPs, so they are **not** the real ceiling.

**Set a hard spend cap on the Anthropic account** — this is the only control
that actually bounds the bill, and it lives in the Anthropic Console, not in
code:

1. Anthropic Console → **Billing → Usage limits**.
2. Set a monthly spend limit (and an email alert threshold below it).

Also worth tuning:

- `Rack::Attack` limits in `config/initializers/rack_attack.rb`.
- Worker concurrency in `config/queue.yml` (default caps concurrent Chrome at 2)
  and `JOB_CONCURRENCY` in `config/deploy.yml`.

## Smoke test after deploy

1. Open the URL — the gallery (seeded) should render immediately.
2. Submit a simple public URL + prompt; watch the status update live.
3. Submit an internal URL (e.g. `http://169.254.169.254/`) — it must be rejected.
