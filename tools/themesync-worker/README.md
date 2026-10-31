# Theme sync server

A tiny Cloudflare Worker that keeps eReaderDS themes in one place so every
device can compare and sync them (Themes → Custom → Sync with your other devices).
The app comes set to a shared one, so you only need this to run your own.

## Set up (once)

```
cd tools/themesync-worker
npx wrangler login
npx wrangler d1 create ereaderds-themes      # paste the id it prints into wrangler.toml
npx wrangler d1 execute ereaderds-themes --remote --file=schema.sql
npx wrangler deploy                          # prints https://ereaderds-themes.<you>.workers.dev
```

In the app: Themes → Custom → **Sync**, press Y → **Use Another Server** and enter that
address, then **Start syncing**. On each other device, do the same with the address, then
choose **Join with a code** and type the code from **Show my sync code**.

## How it works

- One list per sync code (8 letters and digits made by the server, `POST /v1/new`). The server keeps only a hash of the code.
- `PUT /v1/themes` carries changes (`set` and `remove`), which the database applies to the list as it is then, so two devices syncing together can't undo each other. The data is in D1, which is always current (unlike KV, which can show an old list for a minute).
- Kept small for sharing: 200 themes and 32 KB per request, and 60 requests a minute per address (5 new codes).
- `GET /v1/themes` and `PUT /v1/themes` with header `X-Sync-Key`.
- Anyone with the key can read and change your list, so keep it to yourself. Themes are
  just names and two colours; nothing else is stored.

## Try it locally

```
npx wrangler dev
curl -H 'X-Sync-Key: abcdefghjkmnpqrstuvw' http://localhost:8787/v1/themes
```

## Tests

```
node tools/themesync-worker/test.mjs      # needs Node 22.5 or newer (node:sqlite)
```
