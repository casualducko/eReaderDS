# Theme sync server

A tiny Cloudflare Worker that keeps your eReaderDS themes in one place so every
device can compare and sync them (Settings → Themes → Sync themes). Free tier is plenty.

## Set up (once)

```
cd tools/themesync-worker
npx wrangler login
npx wrangler kv namespace create THEMES      # paste the id it prints into wrangler.toml
npx wrangler deploy                          # prints https://ereaderds-themes.<you>.workers.dev
```

In the app: Settings → Themes → Sync themes, enter that address, then **Make a key**.
On each other device, enter the same address and the same key.

## How it works

- One list per sync key. The server keeps only a hash of the key.
- `GET /v1/themes` and `PUT /v1/themes` with header `X-Sync-Key`.
- Anyone with the key can read and change your list, so keep it to yourself. Themes are
  just names and two colours; nothing else is stored.

## Try it locally

```
npx wrangler dev
curl -H 'X-Sync-Key: abcdefghjkmnpqrstuvw' http://localhost:8787/v1/themes
```
