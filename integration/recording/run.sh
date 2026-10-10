#!/bin/sh
# THROWAWAY: run the whole recording experiment from the fork checkout.
set -eu
experiment_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$experiment_root"
gleam format --check src test integration/recording/src integration/recording_core/src
gleam test --target javascript
(cd integration/recording_core && gleam run --target javascript && gleam run --target erlang)
cd integration/recording
gleam build
npm ci --ignore-scripts --no-audit --no-fund
if [ -z "${PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH:-}" ]; then
  npx playwright install chromium
fi
npm test
