#!/usr/bin/env bash
# Packages the public deposit of a staged reproduction archive
# (stage_archive.sh): the archive as one gzipped tar, a source snapshot of the
# commit in its CODE_COMMIT, its README and, when given, the report and console
# log of its clean-container rebuild (reproduce_paper_tables.sh), with
# SHA256SUMS over them. The archive guide (docs/reproduction-archive.md) tells
# readers that the deposit carries the snapshot and the rebuild report beside
# the archive, so the data keep the exact code that rebuilt them even if the
# repository moves.
#
# The staged tree is first verified against its SHA256SUMS (VERIFY=0 skips
# that). Its tar holds one top-level directory, lidar-tree-benchmark-archive/,
# whatever the staged directory is called; entries are sorted by name, the job
# directories' relative links stay symlinks, modification times are kept, and
# owner and group are recorded as 0 with no names, so no local user name enters
# it. The snapshot is `git archive` of CODE_COMMIT, which this checkout must
# hold. Compresses with pigz when it is installed (its options, such as -p for
# threads, can be set in the PIGZ environment variable), gzip otherwise.
#
#   bash scripts/package_deposit.sh ARCHIVE=<staged dir> OUT=<new dir> \
#     [REPORT=<reproduction_report.csv>] [LOG=<console log>] [VERIFY=1]
#
# Writes into OUT: lidar-tree-benchmark-archive.tar.gz,
# lidar-tree-benchmark-code-<first 7 characters of the commit>.tar.gz,
# README.md, reproduction_report.csv and reproduction_console.log (when given)
# and SHA256SUMS over the other files. Each tarball is written under a .tmp
# name and renamed when complete, and OUT is removed if any step fails.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE=""; OUT=""; REPORT=""; LOG=""; VERIFY=1
for a in "$@"; do
  case "$a" in
    ARCHIVE=*) ARCHIVE="${a#ARCHIVE=}" ;;
    OUT=*) OUT="${a#OUT=}" ;;
    REPORT=*) REPORT="${a#REPORT=}" ;;
    LOG=*) LOG="${a#LOG=}" ;;
    VERIFY=*) VERIFY="${a#VERIFY=}" ;;
    *) echo "unknown argument: $a" >&2; exit 2 ;;
  esac
done
[ -n "$ARCHIVE" ] && [ -n "$OUT" ] || { echo "ARCHIVE= and OUT= are required" >&2; exit 2; }
[ ! -e "$OUT" ] && [ ! -L "$OUT" ] || { echo "OUT exists: $OUT (use a new directory)" >&2; exit 2; }
case "$VERIFY" in 0|1) ;; *) echo "VERIFY must be 0 or 1: $VERIFY" >&2; exit 2 ;; esac
for f in SHA256SUMS CODE_COMMIT README.md; do
  [ -f "$ARCHIVE/$f" ] || { echo "no $f in $ARCHIVE (not a staged archive)" >&2; exit 1; }
done
for v in REPORT LOG; do
  [ -z "${!v}" ] || [ -f "${!v}" ] || { echo "$v is not a file: ${!v}" >&2; exit 1; }
done
ARCHIVE="$(realpath -e -- "$ARCHIVE")"; OUT="$(realpath -m -- "$OUT")"
case "$OUT/" in "$ARCHIVE"/*) echo "OUT must lie outside ARCHIVE: $OUT" >&2; exit 2 ;; esac

# A full commit id (a ref name such as HEAD would pass cat-file but name
# nothing fixed) that this checkout holds.
COMMIT="$(tr -d '[:space:]' < "$ARCHIVE/CODE_COMMIT")"
[[ "$COMMIT" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]] ||
  { echo "CODE_COMMIT does not hold a full commit id: $COMMIT" >&2; exit 1; }
git -C "$REPO" cat-file -e "$COMMIT^{commit}" 2> /dev/null ||
  { echo "CODE_COMMIT $COMMIT is not a commit of $REPO (fetch it first)" >&2; exit 1; }
SHORT="${COMMIT:0:7}"
NAME=lidar-tree-benchmark-archive
CODE="lidar-tree-benchmark-code-$SHORT.tar.gz"

say() { echo "$(date '+%F %T') $*"; }
if command -v pigz > /dev/null; then GZ=(pigz -n -c); else GZ=(gzip -n -c); fi

if [ "$VERIFY" = 1 ]; then
  say "verifying archive checksums"
  (cd "$ARCHIVE" && sha256sum --quiet -c SHA256SUMS) ||
    { echo "$ARCHIVE does not match its SHA256SUMS" >&2; exit 1; }
fi

mkdir -p "$(dirname "$OUT")"
mkdir "$OUT"
trap 'st=$?; rm -rf -- "$OUT"; echo "stopped with status $st; removed $OUT" >&2' EXIT
trap 'exit 1' HUP INT TERM

say "archive tar ($NAME/, ${GZ[0]})"
# The S flag keeps the rename off symlink targets (../../neon/<root>).
tar --create --format=gnu --sort=name --owner=0 --group=0 --numeric-owner \
  --transform="s,^\\.,${NAME},S" -C "$ARCHIVE" . | "${GZ[@]}" > "$OUT/$NAME.tar.gz.tmp"
mv "$OUT/$NAME.tar.gz.tmp" "$OUT/$NAME.tar.gz"

say "source snapshot of $COMMIT"
git -C "$REPO" archive --format=tar --prefix="lidar-tree-benchmark-$SHORT/" "$COMMIT" |
  "${GZ[@]}" > "$OUT/$CODE.tmp"
mv "$OUT/$CODE.tmp" "$OUT/$CODE"

cp -- "$ARCHIVE/README.md" "$OUT/README.md"
[ -z "$REPORT" ] || cp -- "$REPORT" "$OUT/reproduction_report.csv"
[ -z "$LOG" ] || cp -- "$LOG" "$OUT/reproduction_console.log"

say "checksums"
(cd "$OUT" && find . -maxdepth 1 -type f ! -name 'SHA256SUMS*' -printf '%f\0' |
   LC_ALL=C sort -z | xargs -0 -r sha256sum --) > "$OUT/SHA256SUMS.tmp"
mv "$OUT/SHA256SUMS.tmp" "$OUT/SHA256SUMS"
trap - EXIT HUP INT TERM

say "deposit in $OUT: $(cd "$OUT" && find . -maxdepth 1 -type f -printf '%f %s\n' |
  LC_ALL=C sort | numfmt --field=2 --to=iec --suffix=B --padding=1 | paste -sd ';' - |
  sed 's/;/; /g')"
