// Checks for worker.js with an in-memory store:  node tools/themesync-worker/test.mjs
import w from "./worker.js"
import assert from "node:assert/strict"
const kv = new Map()
const env = { THEMES: { get: async k => kv.get(k) ?? null, put: async (k, v) => kv.set(k, v) } }
const call = async (m, path, key, body) => {
  const r = await w.fetch(new Request("http://x" + path, { method: m, headers: key ? { "X-Sync-Key": key } : {}, body }), env)
  return [r.status, await r.json()]
}
const [s, b] = await call("POST", "/v1/new")
assert.equal(s, 200); assert.match(b.code, /^[abcdefghjkmnpqrstuvwxyz23456789]{8}$/)
assert.deepEqual(await call("GET", "/v1/themes", b.code), [200, { version: 1, themes: [] }])
assert.equal((await call("GET", "/v1/themes", b.code.toUpperCase()))[0], 200, "any case")
assert.equal((await call("GET", "/v1/themes", "abcd2345"))[0], 404, "unknown code")
assert.equal((await call("PUT", "/v1/themes", "abcd2345", '{"themes":[]}'))[0], 404, "no lists made by PUT")
assert.equal((await call("GET", "/v1/themes", "short"))[0], 401)
const ok = { themes: [{ name: "A", fg: "1:2:3", bg: "4:5:6" }] }
assert.equal((await call("PUT", "/v1/themes", b.code, JSON.stringify(ok)))[0], 200)
assert.deepEqual((await call("GET", "/v1/themes", b.code))[1].themes, ok.themes)
assert.equal((await call("PUT", "/v1/themes", b.code, JSON.stringify({ themes: [{ name: "x", fg: "1.5:2:3", bg: "1" }] })))[0], 400, "decimals")
assert.equal((await call("PUT", "/v1/themes", b.code, "not json"))[0], 400)
const codes = new Set()
for (let i = 0; i < 200; i++) codes.add((await call("POST", "/v1/new"))[1].code)
assert.equal(codes.size, 200, "codes are unique")
console.log("worker: ok")
