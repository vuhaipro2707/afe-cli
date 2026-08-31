#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo ".")"
VERSION_FILE="$SCRIPT_DIR/version"

if [ ! -f "$VERSION_FILE" ]; then
  echo "1.1.0" > "$VERSION_FILE"
fi

CURRENT_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
CURRENT_VERSION="${CURRENT_VERSION:-1.0.0}"

# Parse SemVer
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
MAJOR="${MAJOR:-0}"
MINOR="${MINOR:-0}"
PATCH="${PATCH:-0}"

BUMP_TYPE="${1:-patch}"

case "$BUMP_TYPE" in
  major)
    NEW_MAJOR=$((MAJOR + 1))
    NEW_MINOR=0
    NEW_PATCH=0
    NEW_VERSION="${NEW_MAJOR}.${NEW_MINOR}.${NEW_PATCH}"
    ;;
  minor)
    NEW_MAJOR=$MAJOR
    NEW_MINOR=$((MINOR + 1))
    NEW_PATCH=0
    NEW_VERSION="${NEW_MAJOR}.${NEW_MINOR}.${NEW_PATCH}"
    ;;
  patch)
    NEW_MAJOR=$MAJOR
    NEW_MINOR=$MINOR
    NEW_PATCH=$((PATCH + 1))
    NEW_VERSION="${NEW_MAJOR}.${NEW_MINOR}.${NEW_PATCH}"
    ;;
  [0-9]*.[0-9]*.[0-9]*)
    NEW_VERSION="$BUMP_TYPE"
    ;;
  *)
    echo "❌ Invalid bump type: '$BUMP_TYPE'"
    echo "Usage: $0 [patch | minor | major | <custom_version>]"
    echo "Examples:"
    echo "  $0 patch       # $CURRENT_VERSION -> $MAJOR.$MINOR.$((PATCH + 1))"
    echo "  $0 minor       # $CURRENT_VERSION -> $MAJOR.$((MINOR + 1)).0"
    echo "  $0 major       # $CURRENT_VERSION -> $((MAJOR + 1)).0.0"
    echo "  $0 2.0.0       # Set explicitly to 2.0.0"
    exit 1
    ;;
esac

echo "=================================================="
echo "           🚀 AFE CLI Version Bumper              "
echo "=================================================="
echo "  Current Version : v$CURRENT_VERSION"
echo "  New Version     : v$NEW_VERSION ($BUMP_TYPE)"
echo "--------------------------------------------------"

# 1. Update version file
echo "$NEW_VERSION" > "$VERSION_FILE"
echo "✅ Updated $VERSION_FILE"

# 2. Update default fallback versions in macos.sh & linux.sh
if [ -f "$SCRIPT_DIR/macos.sh" ]; then
  sed -i '' "s/AFE_VERSION=\".*\"/AFE_VERSION=\"$NEW_VERSION\"/g" "$SCRIPT_DIR/macos.sh" 2>/dev/null || \
  sed -i "s/AFE_VERSION=\".*\"/AFE_VERSION=\"$NEW_VERSION\"/g" "$SCRIPT_DIR/macos.sh" 2>/dev/null || true
  echo "✅ Updated macos.sh"
fi

if [ -f "$SCRIPT_DIR/linux.sh" ]; then
  sed -i "s/AFE_VERSION=\".*\"/AFE_VERSION=\"$NEW_VERSION\"/g" "$SCRIPT_DIR/linux.sh" 2>/dev/null || true
  echo "✅ Updated linux.sh"
fi

echo ""
echo "🎉 Successfully bumped AFE CLI to v$NEW_VERSION!"
