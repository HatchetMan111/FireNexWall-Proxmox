#!/usr/bin/env bash
#
# api.sh - Backend-Tests in einer lokalen virtuellen Umgebung.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV="${VENV:-$ROOT/app/.venv}"

if [[ ! -x "$VENV/bin/python" ]]; then
  echo "Erzeuge venv: $VENV"
  python3 -m venv "$VENV"
fi

"$VENV/bin/pip" install --quiet --upgrade pip
"$VENV/bin/pip" install --quiet -r "$ROOT/app/requirements.txt" -r "$ROOT/app/requirements-dev.txt"

cd "$ROOT/app"
PYTHONPATH="$ROOT/app" "$VENV/bin/pytest" -v "$@"
