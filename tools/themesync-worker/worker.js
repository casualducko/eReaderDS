// eReaderDS theme sync: keeps one list of themes per sync code.
//   POST /v1/new    -> { code }: a fresh, unused 8-character code (a list is made for it)
//   GET  /v1/themes -> { version: 1, themes: [ { name, fg, bg } ] }; 404 if no list has that code
//   PUT  /v1/themes <- { version: 2, set: [ { name, fg, bg } ], remove: [ "name" ] }
//                      adds or replaces the themes in `set` and removes the names in `remove`,
//                      all at once, against the list as it is now (so two devices syncing
//                      together can't undo each other); answers with the list. 404 if the code
//                      is unknown. (The older { themes: [...] } replaces the whole list.)
// The code (header X-Sync-Key, 8 to 64 letters and digits, any case) is never stored,
// only its SHA-256, so the code is the only secret. Codes are made here from
// 31 symbols (no 0 O 1 I L), so 8 characters is about 40 bits.
// Shared by every user of the app, so it is kept small: 200 themes and 32 KB a request,
// a request limit per address (LIMITER), a tighter one for new codes (NEWLIM).
// The data is in D1 (schema.sql), which answers from one place, so it is always current.
const MAX_BODY = 32 * 1024
const MAX_THEMES = 200
const ALPHABET = "abcdefghjkmnpqrstuvwxyz23456789"
const COLOUR = /^[\d,\/:\-]{1,60}$/

async function hash(key) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode("eReaderDS themes " + key))
  return [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, "0")).join("")
}

const json = (data, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json" } })

function validName(n) { return typeof n === "string" && n.length >= 1 && n.length <= 60 && !/[\u0000-\u001f]/.test(n) }

// A theme to set: { name, fg, bg } or null if it isn't whole.
function oneTheme(e) {
  if (!e || !validName(e.name) || typeof e.fg !== "string" || typeof e.bg !== "string") return null
  if (!COLOUR.test(e.fg) || !COLOUR.test(e.bg)) return null
  return { name: e.name, fg: e.fg, bg: e.bg }
}

// A list of themes (the last of two with the same name wins), or null.
function themeList(list) {
  if (!Array.isArray(list) || list.length > MAX_THEMES) return null
  const byKey = new Map()
  for (const e of list) {
    const t = oneTheme(e)
    if (!t) return null
    byKey.set(t.name.toLowerCase(), t)
  }
  return [...byKey.values()]
}

function nameList(list) {
  if (!Array.isArray(list) || list.length > MAX_THEMES) return null
  for (const n of list) if (!validName(n)) return null
  return list.map(n => n.toLowerCase())
}

// Eight symbols, without the bias of a plain modulo (248 = 31 * 8).
function newCode() {
  let code = ""
  while (code.length < 8) {
    for (const b of crypto.getRandomValues(new Uint8Array(16))) {
      if (b < 248 && code.length < 8) code += ALPHABET[b % 31]
    }
  }
  return code
}

async function limited(limiter, request) {
  if (!limiter) return false
  const ip = request.headers.get("CF-Connecting-Ip") || request.headers.get("CF-Connecting-IP") || "unknown"
  const { success } = await limiter.limit({ key: ip })
  return !success
}

async function readList(db, id) {
  const { results } = await db.prepare("SELECT name, fg, bg FROM themes WHERE list_id = ? ORDER BY key").bind(id).all()
  return results.map(r => ({ name: r.name, fg: r.fg, bg: r.bg }))
}

// One theme in: added, or replaced if the name is there; not past the limit for a new one.
function setStatement(db, id, t) {
  return db.prepare(
    "INSERT INTO themes (list_id, key, name, fg, bg) SELECT ?1, ?2, ?3, ?4, ?5 " +
    "WHERE EXISTS (SELECT 1 FROM themes WHERE list_id = ?1 AND key = ?2) " +
    "OR (SELECT COUNT(*) FROM themes WHERE list_id = ?1) < ?6 " +
    "ON CONFLICT (list_id, key) DO UPDATE SET name = excluded.name, fg = excluded.fg, bg = excluded.bg")
    .bind(id, t.name.toLowerCase(), t.name, t.fg, t.bg, MAX_THEMES)
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url)
    if (await limited(env.LIMITER, request)) return json({ error: "slow down" }, 429)

    if (url.pathname === "/v1/new" && request.method === "POST") {
      if (await limited(env.NEWLIM, request)) return json({ error: "slow down" }, 429)
      for (let tries = 0; tries < 5; tries++) {
        const code = newCode()
        const made = await env.DB.prepare("INSERT OR IGNORE INTO lists (id, created) VALUES (?, ?)")
          .bind(await hash(code), Math.floor(Date.now() / 1000)).run()
        if (made.meta.changes === 1) return json({ code })
      }
      return json({ error: "try again" }, 503)
    }

    if (url.pathname !== "/v1/themes") return json({ error: "not found" }, 404)
    const key = (request.headers.get("X-Sync-Key") || "").toLowerCase()
    if (!/^[a-z0-9]{8,64}$/.test(key)) return json({ error: "bad code" }, 401)
    const id = await hash(key)
    const known = await env.DB.prepare("SELECT 1 AS x FROM lists WHERE id = ?").bind(id).first()
    if (!known) return json({ error: "unknown code" }, 404)

    if (request.method === "GET") return json({ version: 1, themes: await readList(env.DB, id) })
    if (request.method === "PUT") {
      const text = await request.text()
      if (text.length > MAX_BODY) return json({ error: "too big" }, 413)
      let body
      try { body = JSON.parse(text) } catch { return json({ error: "bad json" }, 400) }
      if (!body || typeof body !== "object") return json({ error: "bad json" }, 400)
      const statements = []
      if (Array.isArray(body.themes)) {                    // (older apps: the whole list)
        const all = themeList(body.themes)
        if (!all) return json({ error: "bad themes" }, 400)
        statements.push(env.DB.prepare("DELETE FROM themes WHERE list_id = ?").bind(id))
        for (const t of all) statements.push(setStatement(env.DB, id, t))
      } else {
        const set = body.set === undefined ? [] : themeList(body.set)
        const remove = body.remove === undefined ? [] : nameList(body.remove)
        if (!set || !remove) return json({ error: "bad themes" }, 400)
        for (const k of remove) statements.push(env.DB.prepare("DELETE FROM themes WHERE list_id = ? AND key = ?").bind(id, k))
        for (const t of set) statements.push(setStatement(env.DB, id, t))
      }
      if (statements.length > 0) await env.DB.batch(statements)
      return json({ version: 1, themes: await readList(env.DB, id) })
    }
    return json({ error: "method not allowed" }, 405)
  },
}
