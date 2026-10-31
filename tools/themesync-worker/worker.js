// eReaderDS theme sync: keeps one list of themes per sync code.
//   POST /v1/new    -> { code }: a fresh, unused 8-character code (a list is reserved for it)
//   GET  /v1/themes -> { version: 1, themes: [ { name, fg, bg } ] }; 404 if no list has that code
//   PUT  /v1/themes <- the same shape; replaces the list (404 if the code is unknown)
// The code (header X-Sync-Key, 8 to 64 letters and digits, any case) is never stored,
// only its SHA-256, so the code is the only secret. Codes are made here from
// 31 symbols (no 0 O 1 I L), so 8 characters is about 40 bits.
// Shared by every user of the app, so it is kept small: 200 themes and 32 KB a list,
// a request limit per address (LIMITER), a tighter one for new codes (NEWLIM),
// and a write only when the list changed.
const MAX_BODY = 32 * 1024
const MAX_THEMES = 200
const ALPHABET = "abcdefghjkmnpqrstuvwxyz23456789"

async function slot(key) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode("eReaderDS themes " + key))
  return "themes:" + [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, "0")).join("")
}

const json = (data, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json" } })

function clean(list) {
  if (!Array.isArray(list) || list.length > MAX_THEMES) return null
  const out = [], seen = new Set()
  for (const e of list) {
    if (!e || typeof e.name !== "string" || typeof e.fg !== "string" || typeof e.bg !== "string") return null
    if (e.name.length < 1 || e.name.length > 60 || /[\u0000-\u001f]/.test(e.name)) return null
    if (!/^[\d,\/:\-]{1,60}$/.test(e.fg) || !/^[\d,\/:\-]{1,60}$/.test(e.bg)) return null
    if (seen.has(e.name.toLowerCase())) continue
    seen.add(e.name.toLowerCase())
    out.push({ name: e.name, fg: e.fg, bg: e.bg })
  }
  return out
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
  const ip = request.headers.get("CF-Connecting-IP") || "unknown"
  const { success } = await limiter.limit({ key: ip })
  return !success
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url)
    if (await limited(env.LIMITER, request)) return json({ error: "slow down" }, 429)

    if (url.pathname === "/v1/new" && request.method === "POST") {
      if (await limited(env.NEWLIM, request)) return json({ error: "slow down" }, 429)
      for (let tries = 0; tries < 5; tries++) {
        const code = newCode()
        const id = await slot(code)
        if (await env.THEMES.get(id)) continue
        await env.THEMES.put(id, "[]")
        return json({ code })
      }
      return json({ error: "try again" }, 503)
    }

    if (url.pathname !== "/v1/themes") return json({ error: "not found" }, 404)
    const key = (request.headers.get("X-Sync-Key") || "").toLowerCase()
    if (!/^[a-z0-9]{8,64}$/.test(key)) return json({ error: "bad code" }, 401)
    const id = await slot(key)
    const saved = await env.THEMES.get(id)
    if (saved === null) return json({ error: "unknown code" }, 404)

    if (request.method === "GET") return json({ version: 1, themes: JSON.parse(saved) })
    if (request.method === "PUT") {
      const text = await request.text()
      if (text.length > MAX_BODY) return json({ error: "too big" }, 413)
      let body
      try { body = JSON.parse(text) } catch { return json({ error: "bad json" }, 400) }
      const themes = clean(body && body.themes)
      if (!themes) return json({ error: "bad themes" }, 400)
      const next = JSON.stringify(themes)
      if (saved !== next) await env.THEMES.put(id, next)
      return json({ version: 1, themes })
    }
    return json({ error: "method not allowed" }, 405)
  },
}
