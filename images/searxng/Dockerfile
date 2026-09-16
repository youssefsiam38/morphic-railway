# syntax=docker/dockerfile:1
#
# SearXNG as Morphic's private search backend on Railway.
#
# Morphic's compose mounts its settings.yml and limiter.toml into the stock image. Railway has no bind
# mounts, so they are baked in here, and the secret the settings leave as a placeholder must come from
# SEARXNG_SECRET. SearXNG itself is unchanged.
ARG SEARXNG_IMAGE=docker.io/searxng/searxng:2026.9.16-f725cc793@sha256:c6239076c5e36720765d1a7815af3e660e0fcf49239a2e3b161b5477c9cd82b0
FROM ${SEARXNG_IMAGE}

ARG WRAPPER_VERSION=0.0.0-dev
ARG VCS_REF=unknown

COPY --chown=searxng:searxng images/searxng/settings.yml /etc/searxng/settings.yml
COPY --chown=searxng:searxng images/searxng/limiter.toml /etc/searxng/limiter.toml
COPY --chmod=0755 images/searxng/entrypoint.sh /usr/local/bin/morphic-searxng-entrypoint
COPY licenses/ /usr/share/licenses/morphic-railway/

LABEL org.opencontainers.image.title="morphic-railway-searxng" \
      org.opencontainers.image.description="SearXNG configured as the private search backend of the Morphic Railway template." \
      org.opencontainers.image.source="https://github.com/youssefsiam38/morphic-railway" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${WRAPPER_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}"

EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/morphic-searxng-entrypoint"]
