# For The People — Lead Engine CRM

A lightweight, shared CRM for an FE/insurance team: a shared lead pool, per‑agent
pipelines, call notes, follow‑ups & appointments, a deals leaderboard, and an
owner command center.

- **Frontend:** a single static `index.html` (no build step).
- **Backend:** one serverless function, `api/storage.js`, a tiny shared key/value
  store backed by **Upstash Redis**.
- **Hosting:** Vercel (static file + serverless function, zero config).

## How data is stored

The UI reads/writes through `window.storage`:

| Data | Scope | Where it lives |
| --- | --- | --- |
| Leads, deals, agents, notes | **Shared** across everyone | Upstash Redis via `/api/storage` |
| Your login session | **Per device** | the browser's `localStorage` |

If Redis isn't connected yet, the app still loads — it just runs in a local
demo mode (shared reads come back empty, writes are no‑ops).

## Deploy on Vercel

1. Import this GitHub repo into Vercel (Add New → Project).
   - Framework preset: **Other**. No build command needed.
2. Add the shared store: project → **Storage** → connect an **Upstash Redis**
   (or Vercel KV) database. Vercel auto‑injects the connection env vars
   (`KV_REST_API_URL` / `KV_REST_API_TOKEN`, or the `UPSTASH_REDIS_REST_*`
   equivalents).
3. **Redeploy** so the function picks up the env vars.

That's it — the live URL is your CRM, with data shared across all agents.

## Demo logins

Username `owner`, `marcus`, `jasmine`, `derek`, or `tanya` — password `demo123`
for all. The owner sees the **Command** and **Admin** tabs.

> ⚠️ **Security note (MVP):** logins use a simple client‑side hash and demo
> passwords. Change passwords after first login, and treat this as an internal
> tool until real auth is added.
