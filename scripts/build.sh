#!/bin/bash
# Build ngx_http_geoip2_module as a .deb package against a specific
# nginx.org NGINX version. Intended to run inside an Ubuntu container
# matching the target distribution.
set -euo pipefail

NGINX_VERSION="${NGINX_VERSION:?must be set, e.g. 1.27.3}"
GEOIP2_VERSION="${GEOIP2_VERSION:?must be set, e.g. 3.4}"
UBUNTU_CODENAME="${UBUNTU_CODENAME:?must be set, e.g. jammy}"
ARCH="${ARCH:?must be set, amd64 or arm64}"
PKG_REVISION="${PKG_REVISION:-1}"
OUTPUT_DIR="${OUTPUT_DIR:-/output}"

mkdir -p "${OUTPUT_DIR}"
WORKDIR="$(mktemp -d)"
cd "${WORKDIR}"

echo "==> Building geoip2 module ${GEOIP2_VERSION} for nginx ${NGINX_VERSION} on ${UBUNTU_CODENAME}/${ARCH}"

# 1. Build dependencies
export DEBIAN_FRONTEND=noninteractive
apt-get -o Acquire::Retries=3 update
apt-get -o Acquire::Retries=3 install -y --no-install-recommends \
    build-essential \
    curl \
    ca-certificates \
    libpcre3-dev \
    libssl-dev \
    zlib1g-dev \
    libxml2-dev \
    libxslt1-dev \
    libgd-dev \
    libgeoip-dev \
    libmaxminddb-dev \
    dpkg-dev \
    fakeroot \
    lsb-release

# 2. Fetch sources
curl -fsSL "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" -o nginx.tar.gz
tar xzf nginx.tar.gz

# Strip leading "v" if user passed e.g. "v3.4"
GEOIP2_TAG="${GEOIP2_VERSION#v}"
curl -fsSL "https://github.com/leev/ngx_http_geoip2_module/archive/refs/tags/${GEOIP2_TAG}.tar.gz" \
    -o geoip2.tar.gz
tar xzf geoip2.tar.gz

# 3. Configure NGINX with --with-compat (binary-compat with nginx.org's build)
#    and the geoip2 module as a dynamic module. We only build modules, not nginx.
cd "nginx-${NGINX_VERSION}"

./configure \
    --prefix=/etc/nginx \
    --sbin-path=/usr/sbin/nginx \
    --modules-path=/usr/lib/nginx/modules \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --pid-path=/var/run/nginx.pid \
    --lock-path=/var/run/nginx.lock \
    --http-client-body-temp-path=/var/cache/nginx/client_temp \
    --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
    --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
    --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
    --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
    --user=nginx \
    --group=nginx \
    --with-compat \
    --with-file-aio \
    --with-threads \
    --add-dynamic-module="../ngx_http_geoip2_module-${GEOIP2_TAG}"

make modules -j"$(nproc)"

# 4. Stage the .deb
PKG_NAME="libnginx-mod-http-geoip2"
PKG_VERSION="${NGINX_VERSION}+${GEOIP2_TAG}-${PKG_REVISION}~${UBUNTU_CODENAME}"
# GitHub Releases replaces ~ with . in asset filenames, so we match that
# in the filename while keeping ~ in the Version: field for correct apt ordering.
DEB_FILENAME_VERSION="${NGINX_VERSION}+${GEOIP2_TAG}-${PKG_REVISION}.${UBUNTU_CODENAME}"
PKG_DIR="${WORKDIR}/pkg"

mkdir -p "${PKG_DIR}/DEBIAN"
mkdir -p "${PKG_DIR}/usr/lib/nginx/modules"
mkdir -p "${PKG_DIR}/usr/share/nginx/modules-available"
mkdir -p "${PKG_DIR}/etc/nginx/modules-enabled"
mkdir -p "${PKG_DIR}/usr/share/doc/${PKG_NAME}"

cp objs/ngx_http_geoip2_module.so "${PKG_DIR}/usr/lib/nginx/modules/"

cat > "${PKG_DIR}/usr/share/nginx/modules-available/mod-http-geoip2.conf" <<'EOF'
load_module modules/ngx_http_geoip2_module.so;
EOF

cat > "${PKG_DIR}/DEBIAN/control" <<EOF
Package: ${PKG_NAME}
Version: ${PKG_VERSION}
Architecture: ${ARCH}
Maintainer: epartment Ops <ops@epartment.example>
Depends: nginx (= ${NGINX_VERSION}-1~${UBUNTU_CODENAME}), libmaxminddb0
Section: httpd
Priority: optional
Homepage: https://github.com/leev/ngx_http_geoip2_module
Description: GeoIP2 dynamic module for nginx
 Dynamic module that uses the MaxMind GeoIP2 databases to set
 variables in nginx based on the client IP address. Built against
 nginx ${NGINX_VERSION} from nginx.org for Ubuntu ${UBUNTU_CODENAME}.
EOF

cat > "${PKG_DIR}/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = "configure" ]; then
    ln -sf /usr/share/nginx/modules-available/mod-http-geoip2.conf \
        /etc/nginx/modules-enabled/50-mod-http-geoip2.conf
fi
EOF
chmod 755 "${PKG_DIR}/DEBIAN/postinst"

cat > "${PKG_DIR}/DEBIAN/prerm" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
    rm -f /etc/nginx/modules-enabled/50-mod-http-geoip2.conf
fi
EOF
chmod 755 "${PKG_DIR}/DEBIAN/prerm"

cp "${WORKDIR}/../debian/copyright" "${PKG_DIR}/usr/share/doc/${PKG_NAME}/" 2>/dev/null || true

DEB_FILE="${PKG_NAME}_${DEB_FILENAME_VERSION}_${ARCH}.deb"
fakeroot dpkg-deb --build "${PKG_DIR}" "${OUTPUT_DIR}/${DEB_FILE}"

echo "==> Built ${OUTPUT_DIR}/${DEB_FILE}"
ls -lh "${OUTPUT_DIR}/${DEB_FILE}"
