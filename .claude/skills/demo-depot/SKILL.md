---
name: demo-depot
description: Build LaunchDarkly SE demos that are ready to publish to Demo Depot, the one-click demo catalog on AWS. Use this skill whenever you build, scaffold, containerize, or refactor any SE or sales demo; whenever you create or edit a demo.yaml, a DEMO.md, or an ld/seed.json; whenever someone says "make this depot-ready", "publish to the depot", or "add this to Demo Depot"; and whenever you build a demo app that uses LaunchDarkly flags, AI Configs, guarded rollouts, or experiments, even if the depot is never mentioned. Without this skill, demos usually break in the depot because of build-time keys, amd64 images, hostname-based service discovery, or missing seed flags.
---

# Building depot-ready demos

Demo Depot launches a fresh, isolated copy of a demo for each SE. Every launch gets its own Fargate task, its own HTTPS URL, and its own brand-new LaunchDarkly project.

That changes how a demo has to be built. A demo that works on your laptop with a hand-configured LaunchDarkly project will often fail in the depot. This skill lists the rules that prevent that, explains why each one exists, and ends with the files to produce and a validator to run.

## Workflow

1. **Plan the story first.** Decide which LaunchDarkly features the demo shows, what the SE clicks in what order, and what the "aha" moment is. That story becomes `DEMO.md` and the seed file.
2. **Build the app against the runtime contract** below. Retrofitting is harder than starting right.
3. **Write the manifest** from `assets/demo.yaml.template`. See `references/manifest.md` for every field.
4. **Write `ld/seed.json`** with every flag, segment, and AI Config the code references. See `references/seed.md`.
5. **Containerize** using `assets/Dockerfile.node` as the starting point: multi-stage, arm64-safe, non-root.
6. **Add the media and `DEMO.md`**, using `assets/DEMO.md.template`.
7. **Add the publish workflow** from `assets/publish.yml`.
8. **Validate:** `python3 scripts/validate_demo.py <repo-root>`. Fix every error, and fix the warnings unless you have a reason not to.
9. **Run it locally** with `dd run` if the CLI is installed, and walk through the story end to end.
10. **Hand off.** Tell the owner what to set in the portal (demo secrets), and to tag `v0.1.0` to publish.

## The runtime contract

These rules exist because of how the depot runs demos. Each one explains the failure it prevents.

### 1. Read every key and setting from env vars at runtime, never at build time

Images are built once at publish time and reused by every launch. Each launch then gets a different LaunchDarkly project, so different keys.

Anything baked in at build time is wrong for every instance. That includes Vite `import.meta.env.VITE_*`, Next.js `NEXT_PUBLIC_*`, CRA `REACT_APP_*`, and Docker `ARG`/`ENV` used for keys.

For browser code, have the server hand config to the client at request time:

```ts
// server: one endpoint (or server-render it into the HTML)
app.get("/api/config", (_req, res) => res.json({
  ldClientSideId: process.env.LD_CLIENT_SIDE_ID,
  customerName: process.env.CUSTOMER_NAME ?? "Acme Corp",
}));
// client: fetch /api/config before initializing the LaunchDarkly JS/React SDK
```

In Next.js, read `process.env` in a server component or route handler and pass the values down. Never use `NEXT_PUBLIC_` for depot-injected values.

### 2. Use the injected variable names

These are the defaults. A manifest can rename them under `launchdarkly.inject`, but don't do that without a reason.

| Variable | Contents |
| --- | --- |
| `LD_SDK_KEY` | Server SDK key |
| `LD_CLIENT_SIDE_ID` | Client-side ID |
| `LD_MOBILE_KEY` | Mobile key |
| `LD_PROJECT_KEY` | Project key |
| `LD_ENV_KEY` | Environment key |
| `LD_API_TOKEN` | API token, only when `apiToken: project-writer` is set |
| `DD_INSTANCE_ID`, `DD_PUBLIC_URL`, `DD_OWNER_EMAIL`, `DD_DEMO_VERSION` | Always present |

Names starting with `DD_`, and the LaunchDarkly names above, are reserved. Don't declare them yourself.

### 3. Use `DD_PUBLIC_URL` for anything that needs the demo's absolute URL

That includes OAuth redirects, webhook targets, share links, and email links. Everywhere else in the frontend, use relative URLs.

TLS terminates at the load balancer, so the app sees plain HTTP. Trust `X-Forwarded-Proto` (for example, `app.set("trust proxy", true)` in Express), and never hardcode `https://localhost`.

### 4. Containers talk over `localhost`, not service names

All of a demo's containers run in one Fargate task and share a network namespace. A Docker Compose hostname like `http://api:4000` does not resolve there.

Use `http://localhost:4000`, read from an env var with that default, for example `API_URL`. Give every container a distinct port. `dd run` mirrors this by sharing one network namespace locally.

### 5. Listen on `0.0.0.0` on the declared ingress port, and expose a cheap health endpoint

The health check path (usually `/healthz`) must return 200 within a second, as soon as the server can serve traffic. It must not depend on LaunchDarkly, an LLM, or any network call. If the health check depends on an external service, a blip there takes the demo down.

Put deeper checks in a separate endpoint such as `/api/health`, and reference it from `verify.http` instead.

The demo should be healthy within 60 seconds of starting.

### 6. Build arm64-compatible images

Fargate runs on Graviton (ARM64). To stay compatible:

- Don't use `--platform=linux/amd64`.
- Don't download amd64-only binaries.
- Pin base images to a specific tag (for example, `node:22-slim`), never `latest`.
- Prefer slim or distroless images.

Native npm modules must build on arm64, which most do.

### 7. Treat the container as disposable

Pausing a demo scales it to zero, and Resume starts a fresh container. The LaunchDarkly project survives, but local state (SQLite files, in-memory stores, uploaded files) does not.

- Seed demo data on boot so every start looks the same.
- If the demo genuinely can't survive a restart, set `lifecycle.pausable: false`.
- If the demo truly needs object storage, use the `s3-scratch` capability and write under the `${DD_INSTANCE_ID}/` prefix.

### 8. Use flags exactly as the seed defines them, and handle the fallback gracefully

Each launch starts from an empty LaunchDarkly project, so the seed has to contain everything. Every flag key, AI Config key, and segment the code references must be in `ld/seed.json`.

Hardcoded fallbacks in SDK calls must produce a sensible "off" experience, never a crash. The validator scans the code for flag keys that are missing from the seed.

The easiest correct path is to build the demo against a real LaunchDarkly project, then run `dd ld export --project <key>` to generate the seed.

### 9. Keep third-party secrets out of the repo

If the demo needs an external API key, list its name under the container's `secrets`. The owner sets the value in the portal under `/owners/<slug>`.

Never commit `.env` files, and never paste a key into the code or the manifest. Add `.env*` to `.gitignore` and `.dockerignore`.

For LLM calls, prefer Bedrock with `capabilities: [bedrock]`. The task role then provides credentials automatically, so there's no key to manage. Use the AWS SDK's default credential chain and the `AWS_REGION` env var.

### 10. Size for the default limits

Start each container at `cpu: 512` and `memory: 1024`. A task over 2 vCPU or 4 GB needs admin approval.

Log to stdout and stderr, as JSON lines if convenient. The portal tails these logs for the SE.

## Make demos SE-friendly

- **Personalize with `parameters`.** A `CUSTOMER_NAME` parameter, and optionally a logo URL or industry enum, lets an SE tailor the demo on the launch form. Read them as env vars.
- **Simulate traffic.** Demos for guarded rollouts, experiments, or metrics need events flowing to produce interesting charts. Add a small `traffic` sidecar container that drives realistic requests, with `dependsOn: [web]`. Make its intensity a parameter if that helps the story.
- **Keep the SE in control during a call.** Show the current flag state in the UI, and offer a visible "reset demo" action that restores seed data.
- **Fail visibly but gracefully.** If an LLM call or the LaunchDarkly connection fails, show a clear in-app banner. Never show a blank page.

## Files to produce

```
demo.yaml                        manifest (assets/demo.yaml.template)
DEMO.md                          detail-page content (assets/DEMO.md.template)
ld/seed.json                     LaunchDarkly seed (references/seed.md)
media/cover.png                  16:9, ≥1600×900, <2 MB
media/loop.mp4                   optional: 5–15 s, muted, <10 MB
<container>/Dockerfile           one per container (assets/Dockerfile.node)
.github/workflows/publish.yml    assets/publish.yml
.dockerignore / .gitignore       must exclude .env*, node_modules, build output
```

**Cover image.** If the app runs locally and Playwright is available, take a 1600×900 screenshot of the most visually compelling screen, with a flag in its "on" state, and save it as `media/cover.png`. If you can't, create a clean placeholder and tell the owner to replace it before tagging a release. Don't leave the cover missing, because the validator fails without it.

**Slug, name, and summary.** The slug is kebab-case, 3–40 characters, and describes the demo, for example `ai-configs-support-agent`. The summary is one sentence of 140 characters or fewer that names the LaunchDarkly capability and the outcome.

**Owners.** Use the requesting SE's email address. If you don't know it, ask. Don't invent one.

## Final checklist

Before you call a demo done:

- [ ] `python3 scripts/validate_demo.py .` reports 0 errors.
- [ ] Every flag, AI Config, and segment the code uses is in the seed. The app also works with every flag at its fallback.
- [ ] No keys or URLs are baked in at build time. The browser gets its config from the server.
- [ ] Containers reach each other through `localhost`, and the health check has no external dependencies.
- [ ] The Dockerfiles are multi-stage, arm64-safe, use pinned bases, and run as non-root.
- [ ] `DEMO.md` walks through the story beat by beat, including which flags to toggle and when.
- [ ] The owner knows which demo secrets to set in the portal, and that tagging `vX.Y.Z` publishes the demo.
