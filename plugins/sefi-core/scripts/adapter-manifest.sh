#!/usr/bin/env bash
# adapter-manifest.sh -- parse and validate the small, portable adapter manifest contract.
# Source this file; adapter_manifest_load <path> sets ADAPTER_* only after validation.

adapter_manifest_load() {
  local manifest="$1" line key value required seen_keys=""
  [ -f "$manifest" ] || { echo "adapter-manifest: manifest not found: $manifest" >&2; return 1; }

  ADAPTER_SCHEMA=""; ADAPTER_ID=""; ADAPTER_VERIFICATION=""; ADAPTER_SUPPORT=""
  ADAPTER_INSTALL_METHOD=""; ADAPTER_AGENT_FORMAT=""; ADAPTER_PERMISSION_TRANSFORM=""
  ADAPTER_HOOK_STRATEGY=""; ADAPTER_DELEGATION=""; ADAPTER_HEADLESS=""
  ADAPTER_MODEL_STRATEGY=""; ADAPTER_ROUTE_EVIDENCE=""; ADAPTER_DRIVER=""; ADAPTER_DESTINATION=""

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    case "$line" in
      *:*) key="${line%%:*}"; value="${line#*:}" ;;
      *) echo "adapter-manifest: invalid line in $manifest: $line" >&2; return 1 ;;
    esac
    value="${value# }"
    case " $seen_keys " in
      *" $key "*) echo "adapter-manifest: duplicate key '$key' in $manifest" >&2; return 1 ;;
    esac
    seen_keys="$seen_keys $key"
    case "$key" in
      schema) ADAPTER_SCHEMA="$value" ;; id) ADAPTER_ID="$value" ;;
      verification) ADAPTER_VERIFICATION="$value" ;; support) ADAPTER_SUPPORT="$value" ;;
      install_method) ADAPTER_INSTALL_METHOD="$value" ;; agent_format) ADAPTER_AGENT_FORMAT="$value" ;;
      permission_transform) ADAPTER_PERMISSION_TRANSFORM="$value" ;; hook_strategy) ADAPTER_HOOK_STRATEGY="$value" ;;
      delegation) ADAPTER_DELEGATION="$value" ;; headless) ADAPTER_HEADLESS="$value" ;;
      model_strategy) ADAPTER_MODEL_STRATEGY="$value" ;; route_evidence) ADAPTER_ROUTE_EVIDENCE="$value" ;;
      driver) ADAPTER_DRIVER="$value" ;; destination) ADAPTER_DESTINATION="$value" ;;
      *) echo "adapter-manifest: unknown key '$key' in $manifest" >&2; return 1 ;;
    esac
  done < "$manifest"

  for required in SCHEMA ID VERIFICATION SUPPORT INSTALL_METHOD AGENT_FORMAT PERMISSION_TRANSFORM HOOK_STRATEGY DELEGATION HEADLESS MODEL_STRATEGY ROUTE_EVIDENCE DRIVER DESTINATION; do
    key="ADAPTER_$required"
    value="${!key}"
    [ -n "$value" ] || { echo "adapter-manifest: missing ${required,,} in $manifest" >&2; return 1; }
  done
  [ "$ADAPTER_SCHEMA" = "sefi-adapter/v1" ] || { echo "adapter-manifest: unsupported schema '$ADAPTER_SCHEMA'" >&2; return 1; }
  case "$ADAPTER_ID" in *[!a-z0-9-]*|'') echo "adapter-manifest: invalid id '$ADAPTER_ID'" >&2; return 1 ;; esac
  case "$ADAPTER_VERIFICATION:$ADAPTER_SUPPORT" in verified:shipped|local:custom) : ;; *) echo "adapter-manifest: verification/support must be verified:shipped or local:custom" >&2; return 1 ;; esac
  case "$ADAPTER_INSTALL_METHOD" in filesystem|native) : ;; *) echo "adapter-manifest: invalid install_method '$ADAPTER_INSTALL_METHOD'" >&2; return 1 ;; esac
  case "$ADAPTER_DRIVER" in filesystem|codex-bootstrap|opencode-native) : ;; *) echo "adapter-manifest: invalid driver '$ADAPTER_DRIVER'" >&2; return 1 ;; esac
  case "$ADAPTER_DESTINATION" in '${HOME}'/*) : ;; *) echo "adapter-manifest: destination must begin with \${HOME}/" >&2; return 1 ;; esac
  return 0
}
