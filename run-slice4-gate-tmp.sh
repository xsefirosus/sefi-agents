bash plugins/sefi-core/scripts/ci/run-all.sh > "$TMPDIR_SEFI/slice4-gate.log" 2>&1
code=$?
echo "EXIT=$code" >> "$TMPDIR_SEFI/slice4-gate.log"
exit "$code"
