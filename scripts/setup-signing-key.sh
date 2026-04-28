#!/bin/bash
# One-time helper: generate a GPG signing key for the apt repository and
# print the steps to add it as a GitHub Actions secret.
#
# Run this ONCE locally. Keep the private key secret.
# Usage: bash scripts/setup-signing-key.sh
set -euo pipefail

KEY_NAME="${KEY_NAME:-Epartment Apt Repo}"
KEY_EMAIL="${KEY_EMAIL:-ops@epartment.example}"
KEY_COMMENT="${KEY_COMMENT:-nginx geoip2 packages}"

echo "==> Generating GPG key for: ${KEY_NAME} <${KEY_EMAIL}>"

# Generate a non-interactive ed25519 key (no passphrase — needed for CI)
gpg --batch --gen-key <<EOF
%no-protection
Key-Type: eddsa
Key-Curve: ed25519
Subkey-Type: ecdh
Subkey-Curve: cv25519
Name-Real: ${KEY_NAME}
Name-Comment: ${KEY_COMMENT}
Name-Email: ${KEY_EMAIL}
Expire-Date: 0
%commit
EOF

KEY_ID=$(gpg --list-secret-keys --with-colons "${KEY_EMAIL}" \
    | awk -F: '/^sec/{print $5; exit}')

echo ""
echo "==> Key generated: ${KEY_ID}"
echo ""
echo "==> Public key (add this to your README for users to trust the repo):"
echo "-----------------------------------------------------------------------"
gpg --armor --export "${KEY_ID}"
echo "-----------------------------------------------------------------------"
echo ""
echo "==> NEXT STEPS:"
echo ""
echo "1. Copy the private key below and add it as a GitHub Actions secret"
echo "   named GPG_PRIVATE_KEY (Settings → Secrets and variables → Actions):"
echo ""
echo "-----------------------------------------------------------------------"
gpg --armor --export-secret-keys "${KEY_ID}"
echo "-----------------------------------------------------------------------"
echo ""
echo "2. Also add GPG_KEY_ID as a secret (or variable) with value: ${KEY_ID}"
echo ""
echo "3. Save the public key to debian/apt-key.asc in your repo so users can"
echo "   easily import it:"
echo ""
echo "   gpg --armor --export ${KEY_ID} > debian/apt-key.asc"
echo "   git add debian/apt-key.asc && git commit -m 'chore: add apt repo signing key'"
