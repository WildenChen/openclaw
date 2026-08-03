#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
./scripts/generate-soulnest-icons.sh
exec xcodegen generate --spec project.yml,project.soulnest.yml "$@"
