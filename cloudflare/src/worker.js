/**
 * IIS Trainings calendar on Cloudflare.
 *
 * - Static files in ./public (the calendar page, icons, manifest) are served
 *   by Workers Static Assets.
 * - GET /api/trainings reads the three monday boards behind the Calendar
 *   dashboard with the MONDAY_API_TOKEN secret and returns their raw items.
 *   The page turns them into calendar entries, exactly as it does inside
 *   claude.ai.
 *
 * Everything sits behind Cloudflare Access. As a second lock, /api refuses
 * any request without an Access token, and fully verifies that token when
 * ACCESS_TEAM_DOMAIN and ACCESS_AUD are set.
 */

const MONDAY_URL = "https://api.monday.com/v2";
const API_VERSION = "2025-04";

const BOARDS = [
  { key: "trainings", id: "18402638125", subitems: false },
  { key: "bootcamps", id: "18407475639", subitems: true },
  { key: "completed", id: "18408627394", subitems: false },
];

const FIELDS =
  "id text value ... on StatusValue { label label_style { color } } " +
  "... on BoardRelationValue { display_value } ... on MirrorValue { display_value }";
const ITEM = (sub) =>
  `id name group { title } column_values { ${FIELDS} }` +
  (sub ? ` subitems { id name column_values { ${FIELDS} } }` : "");
const Q_FIRST = (sub) =>
  `query ($b: ID!) { boards(ids: [$b]) { items_page(limit: ${sub ? 40 : 100}) { cursor items { ${ITEM(sub)} } } } }`;
const Q_NEXT = (sub) =>
  `query ($c: String!) { next_items_page(limit: ${sub ? 40 : 100}, cursor: $c) { cursor items { ${ITEM(sub)} } } }`;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === "/api/trainings") {
      if (request.method !== "GET") return json({ error: "method_not_allowed" }, 405);
      const access = await checkAccess(request, env);
      if (!access.ok) return json({ error: "signed_out", message: access.reason }, 401);
      if (!env.MONDAY_API_TOKEN) return json({ error: "missing_token" }, 500);
      try {
        const boards = {};
        await Promise.all(
          BOARDS.map(async (b) => {
            boards[b.key] = await readBoard(b, env.MONDAY_API_TOKEN);
          }),
        );
        return json({ syncedAt: Date.now(), boards });
      } catch (e) {
        return json({ error: e.code || "upstream", message: e.message || String(e) }, e.status || 502);
      }
    }

    if (url.pathname.startsWith("/api/")) return json({ error: "not_found" }, 404);
    return env.ASSETS.fetch(request);
  },
};

async function monday(token, query, variables) {
  const res = await fetch(MONDAY_URL, {
    method: "POST",
    headers: { Authorization: token, "Content-Type": "application/json", "API-Version": API_VERSION },
    body: JSON.stringify({ query, variables }),
  });
  if (res.status === 401 || res.status === 403) throw { code: "bad_token", status: 502, message: "monday rejected the API token" };
  if (res.status === 429) throw { code: "server_unavailable", status: 503, message: "monday rate limit, try again shortly" };
  if (!res.ok) throw { code: "server_unavailable", status: 502, message: `monday returned HTTP ${res.status}` };
  const body = await res.json();
  if (body.errors && body.errors.length) throw { code: "tool_error", status: 502, message: body.errors.map((x) => x.message).join("; ") };
  if (body.error_message) throw { code: "tool_error", status: 502, message: body.error_message };
  return body.data || {};
}

async function readBoard(board, token) {
  const items = [];
  let page = (await monday(token, Q_FIRST(board.subitems), { b: board.id }))?.boards?.[0]?.items_page;
  if (!page) throw { code: "tool_error", status: 502, message: `Board ${board.id} returned no data` };
  items.push(...page.items);
  for (let guard = 0; page.cursor && guard < 50; guard++) {
    page = (await monday(token, Q_NEXT(board.subitems), { c: page.cursor }))?.next_items_page;
    if (!page) break;
    items.push(...page.items);
  }
  return items;
}

// ---------- Cloudflare Access ----------

async function checkAccess(request, env) {
  const jwt = request.headers.get("Cf-Access-Jwt-Assertion");
  if (!jwt) return { ok: false, reason: "No Cloudflare Access sign-in on this request." };
  if (!env.ACCESS_TEAM_DOMAIN || !env.ACCESS_AUD) return { ok: true };
  try {
    const [h, p, s] = jwt.split(".");
    const header = JSON.parse(b64text(h));
    const payload = JSON.parse(b64text(p));
    const team = env.ACCESS_TEAM_DOMAIN.replace(/^https?:\/\//, "").replace(/\/$/, "");
    const certs = await fetch(`https://${team}/cdn-cgi/access/certs`).then((r) => r.json());
    const jwk = (certs.keys || []).find((k) => k.kid === header.kid);
    if (!jwk) return { ok: false, reason: "Unknown signing key." };
    const key = await crypto.subtle.importKey("jwk", jwk, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]);
    const valid = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, b64bytes(s), new TextEncoder().encode(`${h}.${p}`));
    if (!valid) return { ok: false, reason: "Bad signature." };
    const aud = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
    if (!aud.includes(env.ACCESS_AUD)) return { ok: false, reason: "Wrong audience." };
    if (payload.iss !== `https://${team}`) return { ok: false, reason: "Wrong issuer." };
    if (!payload.exp || payload.exp * 1000 < Date.now()) return { ok: false, reason: "Sign-in expired." };
    return { ok: true };
  } catch {
    return { ok: false, reason: "Couldn't verify the sign-in." };
  }
}

function b64bytes(s) {
  const bin = atob(s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4));
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}
function b64text(s) {
  return new TextDecoder().decode(b64bytes(s));
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}
