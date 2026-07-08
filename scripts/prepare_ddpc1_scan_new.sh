#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"


SCAN_NAME="${SCAN_NAME:-scan_btv_dtv_test}"
NUCLEUS="${NUCLEUS:-Yb160}"
K_LABEL="${K_LABEL:-K0}"
CALC_TYPE="${CALC_TYPE=-strength}"
SCAN_ROOT="${SCAN_ROOT=$ROOT/runs/$SCAN_NAME/$K_LABEL/$CALC_TYPE}"

