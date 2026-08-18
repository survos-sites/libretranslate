# Public, reproducible production image for https://babel.survos.com.
# The FROM tag is the version pin: bump it, validate, commit, and deploy.
#
# Pinned to the version that was running when this repo was created, so the
# move to Dokku is a pure relocation and not a silent upgrade. Bump separately
# and deliberately -- especially for the hoped-for 2.0.
FROM libretranslate/libretranslate:v1.9.5

# Non-secret production configuration belongs in this public image.
#
# babel is DISPOSABLE BY DESIGN: text in, text out. Nothing in the Survos stack
# writes to it -- caching, translation memory and suggestions all live in
# `lingua`. So this image is configured to hold no state worth keeping:
#
#   LT_API_KEYS      was `true` on the old container, but api_keys.db held ZERO
#                    rows. Enabling it only forces a persistent /app/db mount
#                    for a feature nobody uses.
#   --suggestions    was passed on the old container. It is why suggestions.db
#                    existed (1 row, from someone clicking the web UI once).
#                    Dropped for the same reason.
#
# Net effect: the only thing worth persisting is the ~8.7 GB model cache, and
# even that is re-downloadable. A rebuilt babel loses nothing.
#
# To restore either behaviour, set LT_API_KEYS=true (and mount /app/db), or add
# `--suggestions` back via CMD.
# ---------------------------------------------------------------------------
# Throughput
# ---------------------------------------------------------------------------
#
# Verified against the running container (2026-08-18), not assumed:
#
#   LT_BATCH_LIMIT  -1  unlimited — `q` may be an ARRAY of any length
#   LT_CHAR_LIMIT   -1  unlimited
#   LT_REQ_LIMIT    -1  unlimited
#   LT_THREADS       4  (default; was never set here)
#
# So nothing server-side is throttling us. Batching on the caller side helps,
# but MEASURED against this server (2026-08-18, en->fr) it is far less than the
# 5-20x that CTranslate2's batched-inference reputation suggests:
#
#   40 short strings ("Harbour 3", facet-like)   11.31s solo -> 4.51s batched = 2.5x
#   20 long strings  (description-like)          11.50s solo -> 7.72s batched = 1.5x
#
# The gain scales with how much of a request is OVERHEAD, not with batch size —
# which means LibreTranslate is iterating the `q` array rather than running one
# batched forward pass. We are recovering HTTP/round-trip cost, nothing more.
#
# Practical consequence: batching is worth having (2.5x on the short strings
# that dominate our corpus, and it removes the client-timeout failure seen on
# mus/saveoursigns), but CONCURRENCY is the larger remaining lever. Four
# parallel requests measured ~1s each with no degradation, i.e. ~4x available —
# and the two multiply, since concurrency runs several batches at once.
#
# LT_THREADS is therefore left at its default rather than raised: with the array
# processed sequentially, each string already gets 4 threads, and short strings
# cannot use more. The lever to reach for next is parallel requests (gunicorn
# workers here, or `messenger:consume --concurrency` in 8.2 on the caller).
#
# The other reason to be conservative: this host is 8 vCPU shared with ~32
# dokku apps INCLUDING the Postgres cluster that lingua, mediary and harvest
# all run on. Postgres connection timeouts were already observed from one-off
# containers on 2026-08-17. Starving that to speed up translation would be a
# bad trade.
#
# NOTE: the image's entrypoint runs gunicorn (confirmed: passing a stray arg to
# `dokku run` produces "gunicorn: error: argument -w/--workers"), while
# LT_THREADS is documented against waitress in upstream's main.py. The worker
# count is therefore set by the image, not by us, and is not currently
# controllable from here. Raising concurrency deliberately means either an
# explicit CMD with `-w`, or moving to a dedicated host.
ENV LT_HOST=0.0.0.0 \
    LT_PORT=5000 \
    LT_API_KEYS=false \
    LT_DISABLE_WEB_UI=false \
    LT_UPDATE_MODELS=false \
    LT_THREADS=4

EXPOSE 5000
