#!/bin/bash
# Smoke test: install the just-built .deb alongside nginx.org's nginx and
# verify `nginx -t` succeeds with the module loaded. Run inside a matching
# Ubuntu container.
#
# If the exact nginx version is no longer in the apt repo (older releases
# get pruned by nginx.org over time), falls back to validating that the
# compiled .so is a well-formed ELF shared object.
set -euo pipefail

DEB_FILE="${1:?usage: smoke-test.sh <path-to-deb>}"
NGINX_VERSION="${NGINX_VERSION:?must be set}"
UBUNTU_CODENAME="${UBUNTU_CODENAME:?must be set}"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends curl ca-certificates gnupg

# Add nginx.org STABLE repository
curl -fsSL https://nginx.org/keys/nginx_signing.key \
    | gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/ubuntu ${UBUNTU_CODENAME} nginx" \
    > /etc/apt/sources.list.d/nginx.list

apt-get update -qq

PINNED="nginx=${NGINX_VERSION}-1~${UBUNTU_CODENAME}"

if apt-cache show "${PINNED}" > /dev/null 2>&1; then
    # ── Full smoke test ──────────────────────────────────────────────────────
    echo "==> Full smoke test: installing ${PINNED}"

    apt-get install -y "${PINNED}"
    apt-get install -y "${DEB_FILE}"

    echo "==> nginx -V:"
    nginx -V

    echo "==> Modules directory:"
    ls -la /usr/lib/nginx/modules/

    echo "==> nginx -t:"
    nginx -t

    echo "==> Smoke test PASSED (full)"
else
    # ── Lightweight .so validation ───────────────────────────────────────────
    # nginx.org prunes older patch releases from their apt repo; the source
    # tarball is still available and the build succeeded, so we just confirm
    # the resulting shared object is a valid ELF binary.
    echo "==> ${NGINX_VERSION} not in stable apt repo; running lightweight .so check"

    apt-get install -y --no-install-recommends binutils

    TMPDIR=$(mktemp -d)
    dpkg-deb -x "${DEB_FILE}" "${TMPDIR}"
    SO_FILE=$(find "${TMPDIR}" -name "*.so" | head -1)

    if [ -z "${SO_FILE}" ]; then
        echo "ERROR: no .so found in ${DEB_FILE}" >&2
        exit 1
    fi

    echo "==> .so: ${SO_FILE}"
    readelf -h "${SO_FILE}" | grep -E "Type:|Machine:"

    if ! readelf -h "${SO_FILE}" 2>/dev/null | grep -q "DYN"; then
        echo "ERROR: ${SO_FILE} is not a shared object" >&2
        exit 1
    fi

    echo "==> Smoke test PASSED (lightweight .so check)"
fi
