#!/usr/bin/env bash
# Prepare one systems-audit report destination without creating or overwriting it.
set -uo pipefail

usage() {
  echo 'usage: prepare-audit-report-path.sh --root <absolute-project-directory> --scope <scope> --report <absolute-report-path>' >&2
  exit 2
}

root=""
scope=""
report=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || usage; root="$2"; shift 2 ;;
    --scope) [ $# -ge 2 ] || usage; scope="$2"; shift 2 ;;
    --report) [ $# -ge 2 ] || usage; report="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[ -n "$root" ] && [ -n "$scope" ] && [ -n "$report" ] || usage
case "$root" in /*|[A-Za-z]:[\\/]*) : ;; *) usage ;; esac
case "$report" in /*|[A-Za-z]:[\\/]*) : ;; *) usage ;; esac
case "$scope" in complete|research|product|design|build|quality|docs|delivery) : ;; *) usage ;; esac
[ -d "$root" ] || { echo "ERROR: project root is unavailable: $root" >&2; exit 2; }

root="$(cd -P -- "$root" && pwd -P)" || exit 2
audits="$root/audits"
[ -d "$audits" ] || { echo "ERROR: audits directory is unavailable: $audits" >&2; exit 2; }
[ ! -L "$audits" ] || { echo "ERROR: audits directory must not be a symlink" >&2; exit 2; }
audits="$(cd -P -- "$audits" && pwd -P)" || exit 2

report_dir="$(dirname -- "$report")"
case "$(basename -- "$report")" in "audit-report-$scope"-*.md) : ;; *) echo "ERROR: report path does not match scope '$scope'" >&2; exit 2 ;; esac

physical_dir="$(cd -P -- "$report_dir" && pwd -P)" || exit 2
[ "$physical_dir" = "$audits" ] || { echo "ERROR: report path must be directly beneath the physical audits directory" >&2; exit 2; }

if [ -e "$report" ] || [ -L "$report" ]; then
  printf 'AUDIT-REPORT: %s\nSTATUS: REFUSED-OVERWRITE\n' "$report"
  exit 1
fi

printf 'AUDIT-REPORT: %s\nSTATUS: READY-WRITE\n' "$report"
