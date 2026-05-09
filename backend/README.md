# Washa API

Production-oriented **Node.js** backend (**Fastify** + **PostgreSQL**) designed for **Railway**, with:

- **Global `config_version`** — bumped on every meaningful admin change so Flutter apps can poll or compare versions.
- **SSE** (`GET /api/v1/stream/events`) — pushes `{ version }` to connected clients immediately on single-instance deploys.
- **Bootstrap** (`GET /api/v1/public/bootstrap`) — one round-trip for settings + pricing + active channels.
- **JWT admin sessions** or optional **`X-Admin-Key`** for automation.

> **Multi-instance:** SSE fan-out is in-memory only. On Railway with multiple replicas, use sticky sessions or add **Redis pub/sub** (or Postgres `LISTEN/NOTIFY`) — structure is ready to plug in.

---

## Requirements

- Node **20+**
- PostgreSQL **14+** (Railway plugin works)

---

## Quick start (local)

```bash
cd backend
cp .env.example .env
# Set DATABASE_URL, JWT_SECRET (≥16 chars), ADMIN_EMAIL,
# ADMIN_PASSWORD_HASH (see below), then:

npm install
npm run migrate:dev
npm run dev
```

`loadEnv()` reads **`process.env`**. Locally, placing variables in `.env` is enough because **`src/index.ts` imports `dotenv/config`** before loading env. Railway injects variables and does not need a `.env` file in the image.

Generate `ADMIN_PASSWORD_HASH`:

```bash
node scripts/hash-password.mjs "your-admin-password"
```

Paste the printed hash into `.env` as `ADMIN_PASSWORD_HASH=...`.

---

## Railway deploy

1. Create a **PostgreSQL** service and copy **`DATABASE_URL`** (internal URL is fine for the API service).
2. Create a **new service** from this repo’s `backend/` directory (Dockerfile build).
3. Set variables:

   | Variable | Example |
   |----------|---------|
   | `DATABASE_URL` | From Railway Postgres |
   | `JWT_SECRET` | Long random string (≥16 chars) |
   | `ADMIN_EMAIL` | Your admin login email |
   | `ADMIN_PASSWORD_HASH` | Output of `hash-password.mjs` |
   | `ADMIN_API_KEY` | Shared secret — use the **same value** as Flutter `--dart-define=WASHA_ADMIN_API_KEY`
   | `CORS_ORIGIN` | `*` dev, or comma-separated origins for prod |
   | `PORT` | Railway sets automatically (match **8080** in Dockerfile or override) |

4. Deploy. On startup, **`index.ts` applies SQL migrations** then starts the HTTP server (`Dockerfile` only runs `node dist/index.js`).
5. Health check: `GET /health`.

---

## API overview

### Public (no auth)

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/health` | Liveness |
| GET | `/api/v1/public/bootstrap?since=` | Full snapshot; returns **304** if `since >= version` |
| GET | `/api/v1/public/config?since=` | Settings + version |
| GET | `/api/v1/public/plans` | Enabled pricing plans |
| GET | `/api/v1/public/channels` | Active channels |
| GET | `/api/v1/stream/events` | SSE `config` events with `{ version }` |

### Admin

**Auth:** `Authorization: Bearer <token>` from `POST /api/v1/admin/auth/login`, **or** `X-Admin-Key: <ADMIN_API_KEY>` if set.

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/api/v1/admin/auth/login` | `{ "email", "password" }` → JWT |
| GET | `/api/v1/admin/meta/version` | Current `config_version` |
| PATCH | `/api/v1/admin/settings` | `site_name`, `subscription_enabled`, `maintenance_mode`, `whatsapp_number` |
| PUT | `/api/v1/admin/pricing/:plan_key` | `gold` \| `platinum` \| `weekly` — full merge update |
| POST | `/api/v1/admin/channels` | Create channel |
| PATCH | `/api/v1/admin/channels/:id` | Update channel |
| DELETE | `/api/v1/admin/channels/:id` | Delete channel |
| GET | `/api/v1/admin/users` | List users |
| POST | `/api/v1/admin/users` | Create user |
| PATCH | `/api/v1/admin/users/:id` | Update user |
| GET | `/api/v1/admin/payments` | Recent payments |
| GET | `/api/v1/admin/notifications` | Notifications |

---

## Flutter apps (next step)

Wire the **viewer** and **admin** Dart clients to:

1. Replace local-only `SharedPreferences` pricing/settings with `GET /api/v1/public/bootstrap` on launch (and on resume).
2. Optionally open **SSE** to refresh when `version` changes without polling.
3. Point admin mutations to `PATCH/PUT/POST` above with JWT.

---

## Scripts

| Script | Command |
|--------|---------|
| Dev server | `npm run dev` |
| Compile | `npm run build` |
| Migrations (compiled) | `npm run migrate` |
| Migrations (tsx) | `npm run migrate:dev` |

---

## License

Private / project use.
