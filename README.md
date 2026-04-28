# epartment/ubuntu-packages

Prebuilt Debian packages of NGINX dynamic modules for our Ubuntu fleet, built against the official [nginx.org](https://nginx.org) NGINX packages (since Ondrej Sury's repository dropped NGINX support).

Currently builds:

- `libnginx-mod-http-geoip2` — [leev/ngx_http_geoip2_module](https://github.com/leev/ngx_http_geoip2_module)

Targets: Ubuntu 22.04 (jammy), 24.04 (noble), and 26.04 (once released), on both `amd64` and `arm64`.

## How it works

A GitHub Actions matrix builds the module as a dynamic `.so` against a specific NGINX version, with `--with-compat` so it loads cleanly into nginx.org's stock binary. Each `.deb` is pinned (`Depends: nginx (= <version>-1~<codename>)`) to the NGINX version it was built against — apt will refuse to install a mismatch, which is the failure mode we want.

Each successful run smoke-tests the package by installing it next to the matching nginx.org NGINX and running `nginx -t`. Artifacts are attached to a GitHub Release tagged `nginx-<version>-geoip2-<version>`.

## Installing on a server

First-time setup (add nginx.org's repo):

```bash
sudo apt-get install -y curl ca-certificates gnupg lsb-release

curl -fsSL https://nginx.org/keys/nginx_signing.key \
    | sudo gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/mainline/ubuntu $(lsb_release -cs) nginx" \
    | sudo tee /etc/apt/sources.list.d/nginx.list

sudo apt-get update
sudo apt-get install -y nginx
```

Install the geoip2 module from a release:

```bash
NGINX_VER="1.27.3"
GEOIP2_VER="3.4"
CODENAME="$(lsb_release -cs)"
ARCH="$(dpkg --print-architecture)"

curl -fsSL -o /tmp/geoip2.deb \
    "https://github.com/epartment/ubuntu-packages/releases/download/nginx-${NGINX_VER}-geoip2-${GEOIP2_VER}/libnginx-mod-http-geoip2_${NGINX_VER}+${GEOIP2_VER}-1~${CODENAME}_${ARCH}.deb"

sudo apt-get install -y /tmp/geoip2.deb
sudo nginx -t && sudo systemctl reload nginx
```

The package drops a load directive into `/etc/nginx/modules-enabled/50-mod-http-geoip2.conf` so the module is active immediately.

## Triggering a build

Go to **Actions → Build geoip2 module packages → Run workflow**.

- Leave `nginx_version` blank to auto-detect the latest mainline from nginx.org.
- Set it explicitly (e.g. `1.27.3`) to pin to a known version.
- The workflow also runs weekly on a cron, but won't republish if the tag already exists.

## When NGINX upstream releases a new version

Re-run the workflow with the new `nginx_version`. Servers stay on their current NGINX/module pair until you `apt upgrade` — at which point apt will pull the new NGINX **and** the new module together, because of the strict version pin.

## Adding more modules later

The build script is structured so a second module is mostly a copy of `scripts/build.sh` with different module sources. If we add more, consider parameterizing the script over a list of modules rather than duplicating it.

## Caveats

- **Ubuntu 26.04**: not released yet. Uncomment the matrix entry in `.github/workflows/build.yml` once Canonical publishes the codename and the `ubuntu:26.04` Docker tag exists.
- **Mainline vs. stable**: smoke test pulls from `nginx.org/packages/mainline`. If you want stable-line builds, change both the build's nginx version detection and the smoke test to use `nginx.org/packages/ubuntu` (stable) instead.
- **`--with-compat`**: this is what makes the module load into a separately-built NGINX. nginx.org builds with `--with-compat` too, which is why this works. Don't remove it.
