#!/usr/bin/env bash
# CorePulse installer: downloads a release, checks it against its published SHA-256, unpacks it and runs
# ./corepulsectl install. Usage:
#   curl -fsSL https://raw.githubusercontent.com/fetcher-llc/corepulse-install/main/install.sh | bash
# Options (environment variables, before "bash"):
#   COREPULSE_DIR=/opt/corepulse   where to install (created if needed; sudo is used if you cannot write there)
#   COREPULSE_RELEASE=0.9.0        a particular version instead of the newest
#   COREPULSE_CHANNEL=beta         also offer early (beta) releases
#   COREPULSE_HOSTNAME="corepulse.example.com, 192.168.1.20"   the site's names: no question (unattended installs)
set -euo pipefail

FEED="${COREPULSE_UPDATE_URL:-https://raw.githubusercontent.com/fetcher-llc/corepulse-install/main/releases.txt}"
DIR="${COREPULSE_DIR:-/opt/corepulse}"
WANT="${COREPULSE_RELEASE:-}"
CHANNEL="${COREPULSE_CHANNEL:-stable}"

die() { echo "CorePulse installer: $*" >&2; exit 1; }

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

tmp=$(mktemp)
trap 'rm -f "${tmp:?}"' EXIT
echo "Downloading CorePulse $version..."
curl -fsSL --max-time 300 -o "$tmp" "$url" || die "could not download $url"
[[ "$(sha256sum "$tmp" | cut -d' ' -f1)" == "$sum" ]] || die "the download does not match its published SHA-256; nothing was installed"
echo "Checksum OK."

if ! mkdir -p "$DIR" 2>/dev/null || [[ ! -w "$DIR" ]]; then
  echo "Creating $DIR (needs sudo)..."
  sudo mkdir -p "$DIR" && sudo chown "$(id -u):$(id -g)" "$DIR"
fi
tar -xzf "$tmp" -C "$DIR" --strip-components=1
rm -f "${tmp:?}"; trap - EXIT
cd "$DIR"
echo "CorePulse $version unpacked in $DIR."
# The questions are answered on the keyboard (stdin is this script when it was piped from curl). Without a
# terminal (automation), set COREPULSE_HOSTNAME=... beforehand and there is no question.
if [[ -z "${COREPULSE_HOSTNAME:-}" ]] && { exec 3</dev/tty; } 2>/dev/null; then exec ./corepulsectl install <&3; fi
exec ./corepulsectl install </dev/null
