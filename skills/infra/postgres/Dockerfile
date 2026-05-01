# Postgres image, customisable per-host.
#
# Build args:
#   BASE              — base image (default: pgvector/pgvector:pg16)
#   EXTRA_PKGS        — apt packages to install on top (e.g. extra extensions)
#   PARTMAN_VERSION   — if set, build pg_partman from this upstream git tag
#                       (e.g. "v4.7.4"). Overrides any postgresql-XX-partman
#                       that EXTRA_PKGS may bring in. Use this when you need
#                       partman v4 against a service whose migrations were
#                       written before pg_partman 5 (which Debian PGDG now
#                       ships exclusively, breaking migrations like iam's
#                       V000_2/R__vendor_pg_partman.sql).

ARG BASE=pgvector/pgvector:pg16
FROM $BASE

ARG EXTRA_PKGS=
ARG PARTMAN_VERSION=

RUN set -eux; \
    if [ -n "$EXTRA_PKGS" ]; then \
      apt-get update; \
      apt-get install -y --no-install-recommends $EXTRA_PKGS; \
      rm -rf /var/lib/apt/lists/*; \
    fi; \
    if [ -n "$PARTMAN_VERSION" ]; then \
      apt-get update; \
      apt-get install -y --no-install-recommends \
        ca-certificates git build-essential postgresql-server-dev-all; \
      git clone --depth 1 --branch "$PARTMAN_VERSION" \
        https://github.com/pgpartman/pg_partman.git /tmp/pg_partman; \
      make -C /tmp/pg_partman NO_BGW=1 install; \
      rm -rf /tmp/pg_partman; \
      apt-get purge -y --auto-remove \
        git build-essential postgresql-server-dev-all; \
      rm -rf /var/lib/apt/lists/*; \
    fi
