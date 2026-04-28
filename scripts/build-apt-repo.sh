#!/bin/bash
# Build (or update) a signed apt repository from a directory of .deb files.
#
# Usage:
#   GPG_KEY_ID=<fingerprint> build-apt-repo.sh <debs-dir> <repo-dir>
#
# Inputs:
#   <debs-dir>  — flat directory containing all *.deb files to publish
#   <repo-dir>  — output directory that will become the apt repository root
#                 (safe to point at an existing gh-pages checkout)
#
# Env:
#   GPG_KEY_ID          — GPG key fingerprint/ID used to sign the Release file
#   COMPONENT           — apt component name (default: nginx)
#   SUPPORTED_CODENAMES — space-separated list (default: jammy noble)
#
# Output layout:
#   <repo-dir>/
#     pool/<codename>/<pkg>_<ver>_<arch>.deb
#     dists/<codename>/nginx/binary-amd64/Packages
#     dists/<codename>/nginx/binary-amd64/Packages.gz
#     dists/<codename>/nginx/binary-arm64/Packages
#     dists/<codename>/nginx/binary-arm64/Packages.gz
#     dists/<codename>/InRelease          (cleartext-signed)
#     dists/<codename>/Release
#     dists/<codename>/Release.gpg
set -euo pipefail

DEBS_DIR="${1:?usage: build-apt-repo.sh <debs-dir> <repo-dir>}"
REPO_DIR="${2:?usage: build-apt-repo.sh <debs-dir> <repo-dir>}"
GPG_KEY_ID="${GPG_KEY_ID:?GPG_KEY_ID env var must be set}"
COMPONENT="${COMPONENT:-nginx}"
SUPPORTED_CODENAMES="${SUPPORTED_CODENAMES:-jammy noble resolute}"

DEBS_DIR="$(realpath "${DEBS_DIR}")"
REPO_DIR="$(realpath "${REPO_DIR}")"
mkdir -p "${REPO_DIR}"

echo "==> Building apt repo"
echo "    debs:      ${DEBS_DIR}"
echo "    repo root: ${REPO_DIR}"
echo "    key:       ${GPG_KEY_ID}"
echo "    codenames: ${SUPPORTED_CODENAMES}"

# Ensure required tools are available
for tool in dpkg-scanpackages apt-ftparchive gpg gzip; do
    if ! command -v "${tool}" &>/dev/null; then
        echo "ERROR: '${tool}' not found. Install: apt-get install dpkg-dev apt-utils gnupg" >&2
        exit 1
    fi
done

# ── Pool: copy .deb files into pool/<codename>/ ─────────────────────────────
for deb in "${DEBS_DIR}"/*.deb; do
    [ -f "${deb}" ] || { echo "WARNING: no .deb files found in ${DEBS_DIR}"; break; }
    filename="$(basename "${deb}")"

    # Detect codename from the version string (e.g. 1.28.3+3.4-1~noble_amd64.deb → noble)
    codename=""
    for cn in ${SUPPORTED_CODENAMES}; do
        if [[ "${filename}" == *"~${cn}_"* ]]; then
            codename="${cn}"
            break
        fi
    done

    if [ -z "${codename}" ]; then
        echo "WARNING: cannot detect codename from '${filename}', skipping" >&2
        continue
    fi

    pool_dir="${REPO_DIR}/pool/${codename}"
    mkdir -p "${pool_dir}"
    cp -u "${deb}" "${pool_dir}/"
    echo "  pool: ${codename}/${filename}"
done

# ── dists/: generate Packages + Release + signatures ────────────────────────
for codename in ${SUPPORTED_CODENAMES}; do
    pool_dir="${REPO_DIR}/pool/${codename}"
    if [ ! -d "${pool_dir}" ] || [ -z "$(ls -A "${pool_dir}" 2>/dev/null)" ]; then
        echo "  skip ${codename}: no packages in pool"
        continue
    fi

    echo "==> Processing ${codename}"

    for arch in amd64 arm64; do
        binary_dir="${REPO_DIR}/dists/${codename}/${COMPONENT}/binary-${arch}"
        mkdir -p "${binary_dir}"

        # Scan only the .deb files for this arch (dpkg-scanpackages handles arch filtering)
        # Run from repo root so Filename: paths are relative to repo root
        (
            cd "${REPO_DIR}"
            dpkg-scanpackages \
                --arch "${arch}" \
                "pool/${codename}" \
                /dev/null \
                2>/dev/null \
            > "${binary_dir}/Packages"
        )

        gzip -9 -k -f "${binary_dir}/Packages"
        echo "  ${codename}/${COMPONENT}/binary-${arch}: $(wc -l < "${binary_dir}/Packages") lines"
    done

    # Generate Release file for this codename
    dist_dir="${REPO_DIR}/dists/${codename}"

    # Build apt-ftparchive config on-the-fly
    AFT_CONF="$(mktemp)"
    cat > "${AFT_CONF}" <<EOF
APT::FTPArchive::Release {
    Origin "Epartment";
    Label "Epartment nginx geoip2";
    Suite "${codename}";
    Codename "${codename}";
    Architectures "amd64 arm64";
    Components "${COMPONENT}";
    Description "Prebuilt ngx_http_geoip2_module for nginx.org's nginx";
};
EOF

    apt-ftparchive \
        -c "${AFT_CONF}" \
        release \
        "${dist_dir}" \
        > "${dist_dir}/Release"

    rm -f "${AFT_CONF}"

    # Sign: InRelease (cleartext) + Release.gpg (detached)
    gpg --default-key "${GPG_KEY_ID}" \
        --armor --clearsign \
        --batch --yes \
        --output "${dist_dir}/InRelease" \
        "${dist_dir}/Release"

    gpg --default-key "${GPG_KEY_ID}" \
        --armor --detach-sign \
        --batch --yes \
        --output "${dist_dir}/Release.gpg" \
        "${dist_dir}/Release"

    echo "  signed: ${codename}/InRelease + Release.gpg"
done

echo "==> apt repo built at ${REPO_DIR}"
