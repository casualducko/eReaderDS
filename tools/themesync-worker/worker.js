// eReaderDS theme sync: keeps one list of your themes per sync key.
//   GET /v1/themes  -> { version: 1, themes: [ { name, fg, bg } ] }
//   PUT /v1/themes  <- the same shape; replaces the list
// The key (header X-Sync-Key, 16 to 64 letters and digits) is never stored,
// only its SHA-256, so the key is the only secret.
const MAX_BODY = 64 * 1024
const MAX_THEMES = 500

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
    if (!/^[\d,\/:.\-]{1,60}$/.test(e.fg) || !/^[\d,\/:.\-]{1,60}$/.test(e.bg)) return null
    if (seen.has(e.name.toLowerCase())) continue
    seen.add(e.name.toLowerCase())
    out.push({ name: e.name, fg: e.fg, bg: e.bg })
  }
  return out
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url)
    if (url.pathname !== "/v1/themes") return json({ error: "not found" }, 404)
    const key = request.headers.get("X-Sync-Key") || ""
    if (!/^[A-Za-z0-9]{16,64}$/.test(key)) return json({ error: "bad key" }, 401)
    const id = await slot(key)

    if (request.method === "GET") {
      const saved = await env.THEMES.get(id)
      return json({ version: 1, themes: saved ? JSON.parse(saved) : [] })
    }
    if (request.method === "PUT") {
      const text = await request.text()
      if (text.length > MAX_BODY) return json({ error: "too big" }, 413)
      let body
      try { body = JSON.parse(text) } catch { return json({ error: "bad json" }, 400) }
      const themes = clean(body && body.themes)
      if (!themes) return json({ error: "bad themes" }, 400)
      await env.THEMES.put(id, JSON.stringify(themes))
      return json({ version: 1, themes })
    }
    return json({ error: "method not allowed" }, 405)
  },
}
