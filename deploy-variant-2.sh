#!/bin/bash
set -euo pipefail

FLOORP_DIR="/usr/lib/floorp"
SRC_DIR="$(cd "$(dirname "$0")/variant-2-system" && pwd)"

echo "Deploying horizontal tabs to ${FLOORP_DIR}/"
echo "Source: ${SRC_DIR}/"
echo ""

cp "${SRC_DIR}/autoconfig.js"       "${FLOORP_DIR}/defaults/pref/autoconfig.js"
cp "${SRC_DIR}/autoconfig.cfg"      "${FLOORP_DIR}/autoconfig.cfg"
cp "${SRC_DIR}/horizontal_tabs.css" "${FLOORP_DIR}/horizontal_tabs.css"

chmod 644 "${FLOORP_DIR}/defaults/pref/autoconfig.js"
chmod 644 "${FLOORP_DIR}/autoconfig.cfg"
chmod 644 "${FLOORP_DIR}/horizontal_tabs.css"

echo "Done. Restart Floorp to apply."
