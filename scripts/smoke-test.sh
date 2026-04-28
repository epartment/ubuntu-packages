#!/bin/bash
# Smoke test: install the just-built .deb alongside nginx.org's nginx and
# verify `nginx -t` succeeds with the module loaded. Run inside a matching
# Ubuntu container.
set -euo pipefail

DEB_FILE="${1:?usage: smoke-test.sh <path-to-deb>}"
NGINX_VERSION="${NGINX_VERSION:?must be set}"
UBUNTU_CODENAME="${UBUNTU_CODENAME:?must be set}"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates gnupg lsb-release

# Add nginx.org repository
curl -fsSL https://nginx.org/keys/nginx_signing.key \
    | gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/mainline/ubuntu ${UBUNTU_CODENAME} nginx" \
    > /etc/apt/sources.list.d/nginx.list

apt-get update

# Pin to the version we built against
apt-get install -y "nginx=${NGINX_VERSION}-1~${UBUNTU_CODENAME}"

# Install our module
apt-get install -y "${DEB_FILE}"

# Verify
echo "==> nginx -V output:"
nginx -V

echo "==> Modules directory:"
ls -la /usr/lib/nginx/modules/

echo "==> nginx -t:"
nginx -t

echo "==> Smoke test PASSED"
