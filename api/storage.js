// Shared key/value storage for the Lead Engine CRM.
//
// The browser calls:
//   GET  /api/storage?key=crm:leads        -> { value: "<json string>" | null }
//   POST /api/storage  { key, value }       -> { ok: true }
//
// Data is stored in Upstash Redis (a Vercel Marketplace add-on). Connect an
// Upstash Redis (or Vercel KV) store to this project and Vercel injects the
// REST URL + token below automatically. Until then the endpoint returns 503
// and the app runs in a local/demo mode.

import { Redis } from "@upstash/redis";

const url =
  process.env.KV_REST_API_URL || process.env.UPSTASH_REDIS_REST_URL || "";
const token =
  process.env.KV_REST_API_TOKEN || process.env.UPSTASH_REDIS_REST_TOKEN || "";

// automaticDeserialization:false keeps values as the raw JSON strings the
// client sends, so we never double-encode/decode.
const redis =
  url && token ? new Redis({ url, token, automaticDeserialization: false }) : null;

const PREFIX = "fp:"; // namespace so this app's keys don't collide with others

export default async function handler(req, res) {
  if (!redis) {
    return res
      .status(503)
      .json({ error: "storage not configured", value: null });
  }

  try {
    if (req.method === "GET") {
      const key = req.query.key;
      if (!key) return res.status(400).json({ error: "missing key" });
      const value = await redis.get(PREFIX + key);
      return res.status(200).json({ value: value == null ? null : value });
    }

    if (req.method === "POST") {
      const body =
        typeof req.body === "string" ? JSON.parse(req.body || "{}") : req.body || {};
      const { key, value } = body;
      if (!key) return res.status(400).json({ error: "missing key" });
      await redis.set(PREFIX + key, value);
      return res.status(200).json({ ok: true });
    }

    res.setHeader("Allow", "GET, POST");
    return res.status(405).json({ error: "method not allowed" });
  } catch (e) {
    return res
      .status(500)
      .json({ error: String((e && e.message) || e), value: null });
  }
}
