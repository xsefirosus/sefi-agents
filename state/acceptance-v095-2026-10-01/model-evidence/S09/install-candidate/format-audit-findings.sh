#!/usr/bin/env bash
# Format tab-separated systems-audit findings by department and severity with five-item caps.
set -uo pipefail

[ $# -eq 0 ] || { echo 'usage: format-audit-findings.sh < findings.tsv' >&2; exit 2; }

awk '
BEGIN {
  split("Critical Major Minor Nice", order, " ")
  for (i = 1; i <= 4; i++) rank[order[i]] = i
  split("Research Product Design Build Quality Docs Delivery", departments, " ")
  for (i = 1; i <= 7; i++) department_rank[departments[i]] = i
}
{
  columns = split($0, field, "\t")
  if (columns != 3) {
    print "ERROR: finding must be Department<TAB>Severity<TAB>text" > "/dev/stderr"
    invalid = 1
    next
  }
  department = field[1]
  severity = field[2]
  finding_text = field[3]
  if (!(department in department_rank) || !(severity in rank) || finding_text == "") {
    print "ERROR: finding has an unsupported department, unsupported severity, or empty text" > "/dev/stderr"
    invalid = 1
    next
  }
  count[department SUBSEP severity]++
  finding[department SUBSEP severity SUBSEP count[department SUBSEP severity]] = finding_text
}
END {
  if (invalid) exit 2
  for (d = 1; d <= 7; d++) {
    department = departments[d]
    remaining = 5
    for (i = 1; i <= 4; i++) {
      severity = order[i]
      key = department SUBSEP severity
      shown = 0
      for (j = 1; j <= count[key] && remaining > 0; j++) {
        printf "[%s] %s\n", severity, finding[department SUBSEP severity SUBSEP j]
        shown++
        remaining--
      }
      withheld = count[key] - shown
      if (withheld > 0) printf "+%d further %s findings withheld (cap 5)\n", withheld, severity
    }
  }
}
'
