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
ENV LT_HOST=0.0.0.0 \
    LT_PORT=5000 \
    LT_API_KEYS=false \
    LT_DISABLE_WEB_UI=false \
    LT_UPDATE_MODELS=false

EXPOSE 5000
