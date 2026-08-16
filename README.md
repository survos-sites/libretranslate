# LibreTranslate — babel.survos.com

Self-hosted LibreTranslate, the translation *engine* behind `lingua`. Follows the
same service-repo pattern as `~/sites/meilisearch`, `~/sites/imgproxy` and
`~/sites/postgres`: the Dockerfile is the version pin, non-secret configuration is
baked into the public image, no secrets in the repo.

## Where this sits

    app → lingua-bundle → lingua.survos.com → babel.survos.com
                          (translation memory,   (stateless engine,
                           3M translations,       text in / text out)
                           orchestrator)

**lingua is the asset. babel is cattle.** Everything worth keeping — the
translation memory, caching, corrections — lives in lingua. babel holds nothing
but a re-downloadable model cache, so it can be rebuilt from scratch, moved to a
faster box for a big batch job, or destroyed and recreated, with no data loss.

Smoke-test the whole chain from any app using lingua-bundle:

```bash
bin/console lingua:demo
```

## Why this repo exists

The previous deployment was a container started from
`/root/LibreTranslate/docker-compose.yml` **on a directory that no longer
exists**, plus a hand-written `/etc/nginx/conf.d/libretranslate.conf` and a
`.bak` beside it. Nothing was in git. The service worked, but it could not be
reproduced, moved, or upgraded without reverse-engineering a running container.

That is the whole argument for the pattern, and babel is the clearest case of
it: a production service with no recoverable definition.

## Version

    FROM libretranslate/libretranslate:v1.9.5

Pinned to what was running when this repo was created, so adopting Dokku is a
pure relocation rather than a silent upgrade. Bump deliberately — particularly
for the hoped-for 2.0, which is expected to fix long-standing quirks such as the
capitalization handling.

## Deliberately stateless

The old container ran with `LT_API_KEYS=true` and `--suggestions`. Both were
dropped, because both were creating state nobody wanted:

| Setting | Old | Now | Why |
|---|---|---|---|
| `LT_API_KEYS` | `true` | `false` | `api_keys.db` held **0 rows**. Enabling it only forces a persistent `/app/db` mount for an unused feature. |
| `--suggestions` | on | off | Why `suggestions.db` existed — **1 row**, from someone clicking the web UI once in 2024. |

Also cleaned up: `sessions/` had accumulated **8,261** Werkzeug session/temp
files between Sep 2024 and May 2025, none of them useful.

The only mount worth having is the model cache (~8.7 GB at
`/home/libretranslate/.local`), and even that is re-downloadable. If a migration
would take longer than a re-download, just re-download.

To restore either behaviour: set `LT_API_KEYS=true` and mount `/app/db`, or add
`--suggestions` back via `CMD`.

## Caching — do it in lingua, not here

Putting a POST cache in front of babel is possible in nginx but a bad idea:

* `proxy_cache` ignores POST unless you set `proxy_cache_methods POST`
* the cache key must include `$request_body`, since the URL is identical for
  every translation
* **when a body exceeds `client_body_buffer_size`, nginx buffers it to disk and
  `$request_body` evaluates EMPTY** — so every oversized request collides on one
  cache key and gets served someone else's translation. Silent and wrong.
* it puts state back into the service whose whole value is having none

`lingua` is the right layer: it is already the translation memory, it can
normalize on `(source, target, text)` rather than raw request bytes, it can
store results permanently instead of under a TTL, and its cache survives babel
being rebuilt or moved — which is exactly the flexibility this repo is for.

See also the 2026-07-09 imgproxy outage, where an nginx `proxy_cache`
misconfiguration served one cached 502 to every client indefinitely.

## Dokku deployment

```bash
dokku apps:create libretranslate
dokku ports:add libretranslate http:80:5000
dokku domains:set libretranslate babel.survos.com
dokku storage:mount libretranslate /mnt/volume-1/libretranslate/models:/home/libretranslate/.local
dokku checks:disable libretranslate            # model download exceeds the deploy check window
git remote add dokku dokku@ssh.survos.com:libretranslate
git push dokku main
```

First boot downloads ~8.7 GB of models and takes a long time — hence
`checks:disable` and the generous `app.json` healthcheck window (40 attempts,
15s apart, 60s initial delay).

Optionally seed the models from the old container's volume to skip the download:

```bash
# on the host, BEFORE first boot
mkdir -p /mnt/volume-1/libretranslate/models
cp -a /mnt/volume-1/docker-data/volumes/libretranslate_libretranslate_models/_data/. \
      /mnt/volume-1/libretranslate/models/
```

Do **not** copy the old `/app/db` volume — it is 8,261 stale session files, an
empty `api_keys.db`, and a 1-row `suggestions.db`.

### Cleanup after cutover

* remove `/etc/nginx/conf.d/libretranslate.conf` and `libre_translate.conf.bak`
  (Dokku owns the vhost now)
* stop and remove the old `libretranslate` container and its two named volumes
* delete `/mnt/volume-1/libre-translate` — a **14 GB** bare-metal venv superseded
  in May 2024, untouched since, referenced by nothing

## Placement

babel's data is local (the model cache), so it has no storage affinity — unlike
`imgproxy`, whose buckets are in `fsn1` and which pays ~293 ms per cache miss
from Ashburn. lingua calls babel, but model inference dominates, so ~100 ms of
transatlantic latency is proportionally small and bulk jobs are async anyway.

Practically: babel can live wherever is cheapest, and can be moved to a fast box
for a few days to run a large corpus, then moved back. That portability is the
point of this repo.

## Local validation

```bash
cp .env.example .env     # set LT_STORAGE_ROOT
docker compose up -d --build
curl -s http://127.0.0.1:5001/languages | head -c 200
```

Port 5001 locally; 5000 is commonly taken.
