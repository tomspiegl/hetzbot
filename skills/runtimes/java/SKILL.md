---
name: hetzbot-java
description: Install Eclipse Temurin JDK on a host for building/running Maven (Spring Boot) services. Triggers: install-service.sh detects ./mvnw + pom.xml, or user says "install java". Idempotent.
---

# java

Installs Eclipse Temurin JDK from the official Adoptium apt repo. Runs
on-demand, not in cloud-init.

## What `install.sh` does

1. **Early-exit** if `java -version` already matches `JAVA_MAJOR`. Idempotent.
2. **Adds Adoptium** with a `signed-by:` keyring under `/etc/apt/keyrings/adoptium.gpg`.
3. **`apt-get install -y temurin-25-jdk`** pulls JDK + JRE.
4. **Registers Adoptium with unattended-upgrades** via a drop-in at
   `/etc/apt/apt.conf.d/51unattended-upgrades-adoptium` so security
   releases land nightly.

## Lockfile model

Maven has no separate "lockfile". Versions are pinned in `pom.xml`;
the build tool itself is pinned by `mvnw` + `.mvn/wrapper/maven-wrapper.properties`.
`install-service.sh` accepts the `pom.xml` + `mvnw` combo as the
equivalent of a lockfile. **A repo without `mvnw` is rejected** — the
agent will not call a system Maven, only the repo's wrapper.

## Default build

`mvn -B -DskipTests package` (apt's Maven, installed alongside the JDK)
— non-interactive, skip tests (they run in CI), produce shaded/fat
jars under `target/`. Multi-module projects build all modules in
topological order.

**Why apt's `mvn` and not the repo's `./mvnw` wrapper.** `mvnw`
self-downloads its pinned Maven distribution from
`repo.maven.apache.org` (Cloudflare-fronted) on first run. From
Hetzner Cloud nodes, that single ~9 MB download has been observed to
stall mid-stream — see `docs/operations.md § Egress slowdowns`. Apt's
3.8.x is close enough to mvnw's 3.9.x for Spring Boot multi-module +
frontend-maven-plugin builds. Service `build.sh` files should
prefer `mvn` if found, falling back to `./mvnw`:

```bash
if command -v mvn >/dev/null 2>&1; then
  mvn -B -DskipTests package
else
  ./mvnw -B -DskipTests package
fi
```

For Spring Boot multi-module projects with a frontend module
(typically using `frontend-maven-plugin`), the wrapper transparently
downloads its own Node into the build dir during `generate-resources`
phase. No extra setup needed on the host.

## Java version bumps

Pin `JAVA_MAJOR` in `install.sh`. When LTS transitions (currently 25),
update once, redeploy, test. Coordinate across services — a JDK major
bump is fleet-wide.

## When it runs

- First deploy of any Maven service to a host.
- Any deploy, idempotently — if already installed, exits in ~10ms.
- Never from cloud-init (hosts that run no JVM services don't install JDK).
