#!/usr/bin/env bash
#
# build.sh — build and tag all custom-built images for the stack.
#
# Usage: ./scripts/build.sh <version-tag>
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

VERSION="${1:-}"

if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 <version-tag>"
  exit 1
fi

SERVICES=(
  "grade-tracker-backend:${ROOT_DIR}/backend"
  "grade-tracker-frontend:${ROOT_DIR}/frontend"
)

echo "Building images with version tag: ${VERSION}"
echo "-----------------------------------------------"

FAILED=0

for entry in "${SERVICES[@]}"; do
  name="${entry%%:*}"
  context="${entry#*:}"
  image="${name}:${VERSION}"

  echo ""
  echo ">> Building ${image} from ${context} ..."

  if docker build -t "${image}" "${context}"; then
    echo "SUCCESS: built ${image}"
  else
    echo "FAILURE: failed to build ${image}"
    FAILED=1
  fi
done

echo ""
echo "-----------------------------------------------"

if [[ "$FAILED" -ne 0 ]]; then
  echo "One or more builds failed. See output above."
  exit 1
fi

echo "All images built successfully with tag ${VERSION}."
exit 0
