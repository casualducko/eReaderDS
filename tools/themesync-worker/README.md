# Theme sync server

A tiny Cloudflare Worker that keeps eReaderDS themes in one place so every
device can compare and sync them (Themes → Custom → Sync with your other devices).
The app comes set to a shared one, so you only need this to run your own.

## Set up (once)

```
cd tools/themesync-worker
npx wrangler login
npx wrangler kv namespace create THEMES      # paste the id it prints into wrangler.toml
npx wrangler deploy                          # prints https://ereaderds-themes.<you>.workers.dev
```

In the app: Themes → Custom → Sync with your other devices, press Y → **Use Another
Server** and enter that address, then **Make a new key**. On each other device, enter
the same address and the same key.

## How it works

- One list per sync key. The server keeps only a hash of the key.
- Kept small for sharing: 200 themes and 32 KB per list, 60 requests a minute per address,
  and a write only when the list changed (the free tier allows about 1,000 writes a day).
- `GET /v1/themes` and `PUT /v1/themes` with header `X-Sync-Key`.
- Anyone with the key can read and change your list, so keep it to yourself. Themes are
  just names and two colours; nothing else is stored.

## Try it locally

```
npx wrangler dev
curl -H 'X-Sync-Key: abcdefghjkmnpqrstuvw' http://localhost:8787/v1/themes
```
