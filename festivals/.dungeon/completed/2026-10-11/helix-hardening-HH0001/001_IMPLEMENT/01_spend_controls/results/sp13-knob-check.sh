#!/usr/bin/env bash
# SP-13 knob documentation check — run from helix repo root
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../../../../../projects/helix" && pwd)"
cd "$ROOT"
miss=0
check_env() {
  local name="$1"
  for f in apps/edge/src/config.ts .env.example apps/docs/src/deploy/configuration.md infra/azure/main.bicep; do
    if ! grep -q "$name" "$f"; then
      echo "MISS: $name not in $f"
      miss=1
    fi
  done
  if [[ "$name" == EDGE_FETCH_* ]] || [[ "$name" != EDGE_FETCH_* ]]; then
    if [[ "$name" == EDGE_LLM_* ]] && ! grep -q "$name" docs/features/llm-gateway.md; then
      echo "MISS: $name not in docs/features/llm-gateway.md"
      miss=1
    fi
  fi
}
for v in EDGE_LLM_DEFAULT_DOLLARS_PER_DAY EDGE_LLM_PLATFORM_DOLLARS_PER_DAY EDGE_LLM_MAX_APP_IN_FLIGHT EDGE_LLM_MAX_USER_IN_FLIGHT EDGE_LLM_MAX_IN_FLIGHT EDGE_LLM_MAX_CALL_MS EDGE_FETCH_MAX_APP_IN_FLIGHT; do
  check_env "$v"
done
for p in llmDefaultDollarsPerDay llmPlatformDollarsPerDay llmMaxAppInFlight llmMaxUserInFlight llmMaxInFlight llmMaxCallMs fetchMaxAppInFlight; do
  if ! grep -q "$p" apps/docs/src/deploy/configuration.md; then
    echo "MISS: Bicep param $p not in configuration.md"
    miss=1
  fi
done
if [[ "$miss" -eq 0 ]]; then
  echo "OK: all knobs documented"
fi
exit "$miss"
