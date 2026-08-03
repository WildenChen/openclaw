#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
exec xcodegen generate --spec project.yml,project.soulnest.yml "$@"
