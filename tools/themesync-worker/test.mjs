// Checks for worker.js with an in-memory SQLite standing in for D1:  node tools/themesync-worker/test.mjs
import w from "./worker.js"
import assert from "node:assert/strict"
import { DatabaseSync } from "node:sqlite"
import { readFileSync } from "node:fs"

const sqlite = new DatabaseSync(":memory:")
sqlite.exec(readFileSync(new URL("./schema.sql", import.meta.url), "utf8"))
const stmt = (sql, args = []) => ({
  bind: (...a) => stmt(sql, a),
  async run() { const r = sqlite.prepare(sql).run(...args); return { meta: { changes: Number(r.changes) } } },
  async all() { return { results: sqlite.prepare(sql).all(...args) } },
  async first() { return sqlite.prepare(sql).get(...args) ?? null },
  _run() { return sqlite.prepare(sql).run(...args) },
})
const env = { DB: {
  prepare: sql => stmt(sql),
  async batch(list) { sqlite.exec("BEGIN"); try { for (const s of list) s._run(); sqlite.exec("COMMIT") } catch (e) { sqlite.exec("ROLLBACK"); throw e } },
} }
const call = async (m, path, key, body) => {
  const r = await w.fetch(new Request("http://x" + path, { method: m, headers: key ? { "X-Sync-Key": key } : {}, body }), env)
  return [r.status, await r.json()]
}
const put = (key, ops) => call("PUT", "/v1/themes", key, JSON.stringify({ version: 2, ...ops }))
const names = r => r[1].themes.map(t => t.name)

const [s, b] = await call("POST", "/v1/new")
assert.equal(s, 200); assert.match(b.code, /^[abcdefghjkmnpqrstuvwxyz23456789]{8}$/)
assert.deepEqual(await call("GET", "/v1/themes", b.code), [200, { version: 1, themes: [] }])
assert.equal((await call("GET", "/v1/themes", b.code.toUpperCase()))[0], 200, "any case")
assert.equal((await call("GET", "/v1/themes", "abcd2345"))[0], 404, "unknown code")
assert.equal((await put("abcd2345", { set: [] }))[0], 404, "no lists made by PUT")
assert.equal((await call("GET", "/v1/themes", "short"))[0], 401)

// Changes are applied to what is there now.
const A = { name: "A", fg: "1:2:3", bg: "4:5:6" }, B = { name: "B", fg: "7:8:9", bg: "1:1:1" }, C = { name: "C", fg: "2:2:2", bg: "3:3:3" }
assert.deepEqual(names(await put(b.code, { set: [A] })), ["A"])
// Two devices that both last saw ["A"]: one adds B, the other adds C. Neither undoes the other.
await put(b.code, { set: [B] })
assert.deepEqual(names(await put(b.code, { set: [C] })), ["A", "B", "C"], "both additions are kept")
// Replace, and remove (any case).
assert.deepEqual((await put(b.code, { set: [{ ...A, fg: "9:9:9" }], remove: ["b"] }))[1].themes.map(t => t.name + t.fg), ["A9:9:9", "C2:2:2"])
// A name's case is the latest one set.
assert.deepEqual(names(await put(b.code, { set: [{ ...C, name: "c" }] })), ["A", "c"])

// Bad requests change nothing.
for (const bad of [{ set: [{ name: "x", fg: "1.5:2:3", bg: "1" }] }, { set: "no" }, { remove: [1] }, { set: [{ name: "", fg: "1", bg: "1" }] }]) {
  assert.equal((await put(b.code, bad))[0], 400, JSON.stringify(bad))
}
assert.equal((await call("PUT", "/v1/themes", b.code, "not json"))[0], 400)
assert.deepEqual(names(await call("GET", "/v1/themes", b.code)), ["A", "c"])

// The older whole-list request still works.
assert.deepEqual(names(await call("PUT", "/v1/themes", b.code, JSON.stringify({ themes: [B, C] }))), ["B", "C"])

// 200 themes at most.
const many = Array.from({ length: 200 }, (_, i) => ({ name: "t" + i, fg: "1:1:1", bg: "2:2:2" }))
assert.equal((await put(b.code, { set: many, remove: ["b", "c"] }))[1].themes.length, 200)
assert.equal((await put(b.code, { set: [A] }))[1].themes.length, 200, "a new one past the limit is not added")
assert.equal((await put(b.code, { set: [{ ...many[0], fg: "5:5:5" }] }))[1].themes.length, 200, "but one that is there can change")

const codes = new Set()
for (let i = 0; i < 200; i++) codes.add((await call("POST", "/v1/new"))[1].code)
assert.equal(codes.size, 200, "codes are unique")
console.log("worker: ok")
