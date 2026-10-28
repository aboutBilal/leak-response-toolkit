#!/usr/bin/env bash
# Install Spillkit from a signed GitHub release. Downloads the release archive, checks
# its SHA-256, verifies its Sigstore signature when cosign is installed, unpacks it under
# ~/.local/share/spillkit/<version> and links `leak` into ~/.local/bin. Needs no root.
#
# Usage: curl -fsSL https://github.com/aboutBilal/spillkit/releases/latest/download/install.sh | bash
#        bash install.sh [--version vX.Y.Z] [--prefix DIR] [--require-signature]
#   --version vX.Y.Z      install this release (default: the latest)
#   --prefix DIR          install into DIR/share/spillkit and DIR/bin (default: ~/.local)
#   --require-signature   stop unless cosign is installed and the signature verifies
# Env:   SPILLKIT_RELEASES  where releases are downloaded from (default: GitHub), for mirrors
# Runs on bash 3.2 as well (macOS), so it can check what the toolkit itself needs.
set -euo pipefail

repo="aboutBilal/spillkit"
releases="${SPILLKIT_RELEASES:-https://github.com/$repo/releases}"
version=""; prefix="$HOME/.local"; require_sig=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) sed -n '2,/^set -/{/^#/s/^# \{0,1\}//p;}' "$0" 2>/dev/null || echo "see https://github.com/$repo#install"; exit 0 ;;
    --version) [ -n "${2:-}" ] || { echo "--version needs a value" >&2; exit 2; }; version="$2"; shift 2 ;;
    --prefix) [ -n "${2:-}" ] || { echo "--prefix needs a value" >&2; exit 2; }; prefix="$2"; shift 2 ;;
    --require-signature) require_sig=1; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

say() { printf '==> %s\n' "$*"; }
die() { printf 'install failed: %s\n' "$*" >&2; exit 1; }
for c in curl tar; do command -v "$c" >/dev/null 2>&1 || die "missing: $c"; done
if command -v sha256sum >/dev/null 2>&1; then sha_check() { sha256sum -c "$1" >/dev/null; }
elif command -v shasum >/dev/null 2>&1; then sha_check() { shasum -a 256 -c "$1" >/dev/null; }
else die "missing: sha256sum or shasum"; fi

if [ -z "$version" ]; then
  # The latest release page redirects to .../tag/vX.Y.Z; no API call, so no rate limit.
  latest="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "$releases/latest")" || die "could not reach $releases"
  version="${latest##*/}"
fi
case "$version" in
  v[0-9]*.[0-9]*.[0-9]*) ;;
  [0-9]*.[0-9]*.[0-9]*) version="v$version" ;;
  *) die "not a release version: $version" ;;
esac

name="spillkit-$version"
stage=""
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp" ${stage:+"$stage"}' EXIT
say "Downloading Spillkit $version"
for f in "$name.tar.gz" "$name.tar.gz.sha256" "$name.tar.gz.sigstore.json"; do
  curl -fsSL -o "$tmp/$f" "$releases/download/$version/$f" || die "could not download $f (does release $version exist?)"
done

(cd "$tmp" && sha_check "$name.tar.gz.sha256") || die "the archive does not match its SHA-256: not installed"
say "SHA-256 matches"
if command -v cosign >/dev/null 2>&1; then
  # Releases use the Sigstore bundle format of cosign 3; cosign 2.4 and later read it with a flag.
  bundle_flag=""
  case "$(cosign version 2>/dev/null | sed -n 's/^GitVersion:[[:space:]]*v\{0,1\}//p')" in
    2.*) bundle_flag="--new-bundle-format" ;;
  esac
  cosign verify-blob "$tmp/$name.tar.gz" --bundle "$tmp/$name.tar.gz.sigstore.json" ${bundle_flag:+"$bundle_flag"} \
    --certificate-identity "https://github.com/$repo/.github/workflows/release.yml@refs/tags/$version" \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com >/dev/null 2>&1 \
    || die "the Sigstore signature does not verify (or cosign is older than 2.4): not installed"
  say "Signature verified: built by this repository's release workflow for $version"
elif [ "$require_sig" = 1 ]; then
  die "--require-signature needs cosign: https://docs.sigstore.dev/cosign/system_config/installation/"
else
  echo "    cosign is not installed, so the signature was not checked. The checksum guards against a"
  echo "    damaged download only. To verify the signature too, install cosign and run this again."
fi

mkdir -p "$prefix/share/spillkit" "$prefix/bin" || die "could not create $prefix"
prefix="$(cd "$prefix" && pwd)"   # absolute, so the link resolves from bin/
dest="$prefix/share/spillkit/$version"
# Unpack beside the destination and swap it in only when complete: a failed install keeps the old one.
stage="$(mktemp -d "$prefix/share/spillkit/.install.XXXXXX")" || die "could not write to $prefix/share/spillkit"
tar -xzf "$tmp/$name.tar.gz" -C "$stage" --strip-components=1 || die "could not unpack the archive: not installed"
[ -x "$stage/leak" ] || die "the archive has no leak command"
chmod 755 "$stage"   # mktemp made it private; the installed version must be readable by everyone
rm -rf "$dest" && mv "$stage" "$dest" || die "could not move the new version into $dest"
ln -sfn "$dest/leak" "$prefix/bin/leak"
[ -x "$prefix/bin/leak" ] || die "$prefix/bin/leak does not lead to the installed command"
say "Installed $("$prefix/bin/leak" version 2>/dev/null || echo "spillkit $version") in $dest"
echo "    leak -> $prefix/bin/leak"

# What the toolkit needs at run time (leak doctor checks all of it in detail).
bash_ok="$(bash -c 'if ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4))); then echo yes; fi' 2>/dev/null || true)"
if [ "$bash_ok" != yes ]; then
  echo "    Note: leak needs bash 4.4 or later on PATH. On macOS, brew install bash, or install"
  echo "    Spillkit with Homebrew instead, which takes care of it: brew install aboutbilal/tap/spillkit"
fi
case ":$PATH:" in
  *":$prefix/bin:"*) ;;
  *) echo "    Add $prefix/bin to your PATH:  export PATH=\"$prefix/bin:\$PATH\"" ;;
esac
echo
echo "Next: leak doctor   (checks this machine)   then   leak demo   (see it work in a minute)"
