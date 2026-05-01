#!/usr/bin/env bash
# Install Eclipse Temurin JDK on the HOST as root. Idempotent.
# Triggered by install-service.sh when a service repo has ./mvnw + pom.xml.
set -euo pipefail

JAVA_MAJOR=25

if command -v java >/dev/null 2>&1; then
  current=$(java -version 2>&1 | head -1 | sed -nE 's/.*"([0-9]+).*/\1/p' || true)
  if [ "$current" = "$JAVA_MAJOR" ]; then
    echo "[java] already at JDK $current — ok"
    exit 0
  fi
  echo "[java] found JDK $current, expected $JAVA_MAJOR — proceeding to install"
fi

install -d -m 0755 /etc/apt/keyrings

if [ ! -f /etc/apt/keyrings/adoptium.gpg ]; then
  curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public \
    | gpg --dearmor -o /etc/apt/keyrings/adoptium.gpg
  chmod 0644 /etc/apt/keyrings/adoptium.gpg
fi

codename=$(lsb_release -cs)
cat > /etc/apt/sources.list.d/adoptium.list <<EOF
deb [signed-by=/etc/apt/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb ${codename} main
EOF

apt-get update
# JDK + apt's Maven. Maven via apt avoids mvnw self-downloading its own
# Maven distribution from Cloudflare (which has been flaky from Hetzner
# Cloud — see services/iam/build.sh). Build scripts prefer `mvn` if found.
DEBIAN_FRONTEND=noninteractive apt-get install -y "temurin-${JAVA_MAJOR}-jdk" maven

cat > /etc/apt/apt.conf.d/51unattended-upgrades-adoptium <<'EOF'
Unattended-Upgrade::Origins-Pattern {
    "origin=Eclipse Adoptium";
    "origin=packages.adoptium.net";
};
EOF

echo "[java] installed $(java -version 2>&1 | head -1)"
