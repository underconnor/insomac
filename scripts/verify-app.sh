#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$project_dir/Tools/VerifyApp.py" "$@"
