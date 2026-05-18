#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build"
APP_PATH="$BUILD_DIR/Build/Products/Debug/RepTrack.app"
LOG="$BUILD_DIR/build.log"

G='\033[0;32m'   # green
R='\033[0;31m'   # red
D='\033[0;90m'   # gray
B='\033[1m'      # bold
N='\033[0m'      # reset
HR="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

ok()   { printf "  ${G}✓${N}  $1\n"; }
fail() { printf "  ${R}✗${N}  $1\n"; }
step() { printf "  ⟳  $1"; }
done_in() { printf "\r  ${G}✓${N}  $1  ${G}done (${2}s)${N}\n"; }

mkdir -p "$BUILD_DIR"

echo ""
printf "  ${B}${HR}${N}\n"
printf "  ${B}  RepTrack Builder${N}\n"
printf "  ${B}${HR}${N}\n"
echo ""

# ── Kill old instance ──────────────────────────────
OLD_PID=$(pgrep -x "RepTrack" 2>/dev/null)
if [ -n "$OLD_PID" ]; then
    pkill -x "RepTrack" 2>/dev/null
    sleep 0.6
    ok "Killed old instance (PID $OLD_PID)"
fi

# ── Build ──────────────────────────────────────────
step "Building..."
T0=$(date +%s)

xcodebuild \
  -project "$SCRIPT_DIR/RepTrack.xcodeproj" \
  -scheme RepTrack \
  -configuration Debug \
  -derivedDataPath "$BUILD_DIR" \
  build > "$LOG" 2>&1

STATUS=$?
T1=$(date +%s)
ELAPSED=$((T1 - T0))

if [ "$STATUS" -ne 0 ]; then
    printf "\r"
    fail "Build failed  ${D}(${ELAPSED}s)${N}"
    echo ""
    grep "error:" "$LOG" | grep -v "^//" | sed 's/^/    /'
    echo ""
    printf "  ${D}Full log: $LOG${N}\n"
    echo ""
    exit 1
fi

done_in "Building..." "$ELAPSED"

# ── Launch ─────────────────────────────────────────
step "Launching..."
open "$APP_PATH"
sleep 0.5
ok "Launched"

# ── Summary ────────────────────────────────────────
echo ""
printf "  ${HR}\n"
printf "  ${G}${B}✅  RepTrack.app${N}  ${D}(Debug · local only)${N}\n"
printf "  ${HR}\n"
echo ""
