#!/usr/bin/env bash
# stage-release.sh - copy a board's build output into fpga/release-staging/ under
# the canonical release name (board_clock_baud), then regenerate SHA256SUMS.
#
# WHY THIS EXISTS. Every board's build tool emits a generic name
# (nd120_nexys4ddr.bit, nd120_mega65_r6.cor, ...). The download name that carries
# the clock and baud is a RELEASE convention, and it used to be applied by hand -
# which once shipped a MEGA65 .cor named for a build it was not. The canonical
# names live in release-manifest.txt; this script stages by name from there, so
# the convention is declared once and never retyped.
#
# Usage:
#   ./stage-release.sh <release-name> [<release-name> ...]   stage those artifacts + refresh SHA256SUMS
#   ./stage-release.sh --sums                                just regenerate SHA256SUMS
#   ./stage-release.sh --list                                print the manifest (the valid names)
#
# The console is 115200 7E1 on every board.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
manifest="$here/release-manifest.txt"
staging="$here/release-staging"
sums="$staging/SHA256SUMS"
mkdir -p "$staging"

# The sub(/\r$/,"") is not decoration. This repo is checked out on a Windows
# drive as well, where git hands the manifest over with CRLF line endings; the
# trailing carriage return then rides along on the LAST field and every lookup
# fails with "build output not found" against a path that plainly exists.
# Measured 04-SEP-2026: on the Windows checkout NO artifact could be staged.
all_names()     { awk '!/^#/ && NF>=2 {sub(/\r$/,"",$1); sub(/\r$/,"",$2); print $1}' "$manifest"; }
lookup_source() { awk -v n="$1" '!/^#/ && NF>=2 {sub(/\r$/,"",$1); sub(/\r$/,"",$2)}
                                 $1==n {print $2; exit}' "$manifest"; }

regen_sums() {
  ( cd "$staging" && : > "$sums"
    for n in $(all_names); do [ -f "$n" ] && sha256sum "$n" >> "$sums"; done )
  echo "SHA256SUMS regenerated ($(grep -c . "$sums" 2>/dev/null || echo 0) files) -> fpga/release-staging/SHA256SUMS"
}

stage_one() { # $1 = release name
  src="$(lookup_source "$1")"
  if [ -z "$src" ]; then
    echo "ERROR: '$1' is not a release artifact. Valid names (release-manifest.txt):" >&2
    all_names | sed 's/^/  /' >&2
    exit 1
  fi
  if [ ! -f "$here/$src" ]; then
    echo "ERROR: build output not found: fpga/$src" >&2
    echo "       Build that config first, then stage its name." >&2
    exit 1
  fi
  cp -f "$here/$src" "$staging/$1"
  sz=$(wc -c < "$staging/$1")
  sh=$(sha256sum "$staging/$1" | cut -d' ' -f1)
  echo "staged  $1  ($sz bytes)  sha256 $sh   <- fpga/$src"
}

case "${1:-}" in
  ""      ) echo "usage: stage-release.sh <release-name>|--sums|--list  (see --list for the names)" >&2; exit 2 ;;
  --list  ) sed 's/^/  /' "$manifest"; exit 0 ;;
  --sums  ) regen_sums; exit 0 ;;
  --*     ) echo "unknown option: $1" >&2; exit 2 ;;
  *       ) for n in "$@"; do stage_one "$n"; done; regen_sums; exit 0 ;;
esac
