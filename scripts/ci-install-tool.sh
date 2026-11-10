#!/usr/bin/env bash
# CI only: installs a pinned, checksum-verified tool binary into ~/.local/bin and adds it
# to GITHUB_PATH. Usage: scripts/ci-install-tool.sh gitleaks|lychee
# To update: change the version and the sha256 from the release's published checksums.
set -euo pipefail

case "${1:-}" in
  gitleaks)
    url="https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz"
    sha="551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb"
    member="gitleaks" ;;
  lychee)
    url="https://github.com/lycheeverse/lychee/releases/download/lychee-v0.24.2/lychee-x86_64-unknown-linux-gnu.tar.gz"
    sha="1f4e0ef7f6554a6ed33dd7ac144fb2e1bbed98598e7af973042fc5cd43951c9a"
    member="lychee-x86_64-unknown-linux-gnu/lychee" ;;
  *) echo "ci-install-tool: unknown tool '${1:-}'" >&2; exit 1 ;;
esac

bin="$HOME/.local/bin"; tmp=$(mktemp -d)
mkdir -p "$bin"
curl -sSfL -o "$tmp/tool.tar.gz" "$url"
echo "$sha  $tmp/tool.tar.gz" | sha256sum -c --quiet -
tar -xzf "$tmp/tool.tar.gz" -C "$tmp" "$member"
install -m 0755 "$tmp/$member" "$bin/$1"
echo "$bin" >> "${GITHUB_PATH:-/dev/null}"
"$bin/$1" --version
