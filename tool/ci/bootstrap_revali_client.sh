#!/usr/bin/env bash
# Creates a minimal generated client package so workspace pub get succeeds before revali codegen.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLIENT_DIR="${ROOT}/apps/server/.revali/revali_client"

mkdir -p "${CLIENT_DIR}/lib"
cat > "${CLIENT_DIR}/pubspec.yaml" <<'EOF'
name: client
publish_to: none

environment:
  sdk: ">=3.12.0 <4.0.0"

dependencies:
  revali_client: ^2.0.4
EOF

cat > "${CLIENT_DIR}/lib/client.dart" <<'EOF'
// Bootstrap stub — replaced by `revali dev --generate-only`.
library;
EOF

echo "Bootstrapped ${CLIENT_DIR}"
