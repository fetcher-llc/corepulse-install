#!/usr/bin/env bash
# CorePulse installer: downloads a release, checks it against its published SHA-256 and its Sigstore
# signature (made by CorePulse's release workflow on GitHub), unpacks it and runs ./corepulsectl install. Usage:
#   curl -fsSL https://raw.githubusercontent.com/fetcher-llc/corepulse-install/main/install.sh | bash
# Options (environment variables, before "bash"):
#   COREPULSE_DIR=/opt/corepulse   where to install (created if needed; sudo is used if you cannot write there)
#   COREPULSE_RELEASE=0.9.0        a particular version instead of the newest
#   COREPULSE_CHANNEL=beta         also offer early (beta) releases
#   COREPULSE_HOSTNAME="corepulse.example.com, 192.168.1.20"   the site's names: no question (unattended installs)
#   COREPULSE_VERIFY=warn|off      what to do when a signature cannot be verified (default: required = stop)
set -euo pipefail

FEED="${COREPULSE_UPDATE_URL:-https://raw.githubusercontent.com/fetcher-llc/corepulse-install/main/releases.txt}"
DIR="${COREPULSE_DIR:-/opt/corepulse}"
WANT="${COREPULSE_RELEASE:-}"
CHANNEL="${COREPULSE_CHANNEL:-stable}"

die() { echo "CorePulse installer: $*" >&2; exit 1; }
COSIGN_IMAGE="ghcr.io/sigstore/cosign/cosign:v2.4.1@sha256:b03690aa52bfe94054187142fba24dc54137650682810633901767d8a3e15b31"
VERIFY="${COREPULSE_VERIFY:-required}"
SIGNED_SINCE=0.9.2   # releases before this one have no signed bundle

for c in curl tar sha256sum openssl docker; do command -v "$c" >/dev/null || die "$c is needed (Docker: see https://docs.docker.com/engine/install/)"; done
docker compose version >/dev/null 2>&1 || die "the Docker compose plugin is needed (package docker-compose-plugin)"
docker info >/dev/null 2>&1 || die "this user cannot use Docker: run with sudo, or add the user to the docker group and sign in again"
case "$(uname -m)" in x86_64|amd64|aarch64|arm64) ;; *) die "CorePulse runs on x86-64 and ARM64 servers, not $(uname -m)";; esac
[[ -f "$DIR/.env" ]] && die "CorePulse is already installed in $DIR: upgrade it there with ./corepulsectl upgrade"

echo "Reading the list of releases..."
releases=$(curl -fsSL --max-time 30 "$FEED" | grep -v '^#' | grep -v '^[[:space:]]*$') || die "could not read $FEED"
if [[ -n "$WANT" ]]; then
  line=$(awk -F'|' -v v="$WANT" '$1 == v' <<<"$releases" | head -1)
  [[ -n "$line" ]] || die "there is no CorePulse $WANT"
else
  version=$(awk -F'|' -v c="$CHANNEL" '$3 == "stable" || (c == "beta" && $3 == "beta") {print $1}' <<<"$releases" | sort -V | tail -1)
  [[ -n "$version" ]] || die "no release found on the $CHANNEL channel"
  line=$(awk -F'|' -v v="$version" '$1 == v' <<<"$releases" | head -1)
fi
IFS='|' read -r version _date _channel url sum _notes <<<"$line"
[[ -n "$url" && -n "$sum" ]] || die "the release list has no download for $version"

tmpdir=$(mktemp -d)
tmp="$tmpdir/corepulse.tar.gz"
trap 'rm -rf "${tmpdir:?}"' EXIT
echo "Downloading CorePulse $version..."
curl -fsSL --max-time 300 -o "$tmp" "$url" || die "could not download $url"
[[ "$(sha256sum "$tmp" | cut -d' ' -f1)" == "$sum" ]] || die "the download does not match its published SHA-256; nothing was installed"
echo "Checksum OK."

# The signature proves the bundle was made by CorePulse's release workflow (the checksum alone comes from the
# same place as the download). Checked with cosign, run from its own container (Docker is needed anyway).
signature_failed() {
  [[ "$VERIFY" == required ]] && die "$1; nothing was installed. (If this server cannot reach the signature log, see 'Signatures' in the install guide.)"
  echo "CorePulse installer: WARNING: $1; carrying on because COREPULSE_VERIFY=$VERIFY." >&2
}
if [[ "$VERIFY" == off ]]; then
  echo "Signature not checked (COREPULSE_VERIFY=off)."
elif [[ "$(printf '%s\n%s\n' "$version" "$SIGNED_SINCE" | sort -V | head -1)" != "$SIGNED_SINCE" ]]; then
  echo "CorePulse $version is from before signed bundles; its checksum was checked."
elif ! curl -fsSL --max-time 60 -o "$tmp.sigstore.json" "$url.sigstore.json"; then
  signature_failed "could not download the signature of the bundle"
elif docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp --tmpfs /tmp -v "$tmpdir:/w:ro" "$COSIGN_IMAGE" verify-blob --bundle /w/corepulse.tar.gz.sigstore.json \
       --certificate-oidc-issuer https://token.actions.githubusercontent.com \
       --certificate-identity-regexp '^https://github.com/fetcher-llc/corepulse/\.github/workflows/release\.yml@refs/tags/v' \
       /w/corepulse.tar.gz >/dev/null 2>&1; then
  echo "Signature verified: the bundle was made and signed by CorePulse's release workflow."
else
  signature_failed "the bundle's signature could not be verified"
fi

if ! mkdir -p "$DIR" 2>/dev/null || [[ ! -w "$DIR" ]]; then
  echo "Creating $DIR (needs sudo)..."
  sudo mkdir -p "$DIR" && sudo chown "$(id -u):$(id -g)" "$DIR"
fi
tar -xzf "$tmp" -C "$DIR" --strip-components=1
rm -rf "${tmpdir:?}"; trap - EXIT
cd "$DIR"
echo "CorePulse $version unpacked in $DIR."
# The questions are answered on the keyboard (stdin is this script when it was piped from curl). Without a
# terminal (automation), set COREPULSE_HOSTNAME=... beforehand and there is no question.
export COREPULSE_VERIFY="$VERIFY"   # corepulsectl checks the images' signatures the same way
if [[ -z "${COREPULSE_HOSTNAME:-}" ]] && { exec 3</dev/tty; } 2>/dev/null; then exec ./corepulsectl install <&3; fi
exec ./corepulsectl install </dev/null
