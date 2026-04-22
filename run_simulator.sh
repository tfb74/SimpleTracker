#!/bin/bash
# Startet iPhone 17 + Apple Watch Series 11 Simulator und baut das Projekt

set -e

IPHONE_UDID="B0905D18-0E12-4F01-BA29-A5E09751EDAF"
WATCH_UDID="7B960AD1-CAAA-4964-BA36-70FF1A903B78"
PROJECT="SimpleTracking.xcodeproj"
SCHEME="SimpleTracking"

echo "▶ Starte Simulatoren..."
xcrun simctl boot "$IPHONE_UDID" 2>/dev/null || true
xcrun simctl boot "$WATCH_UDID" 2>/dev/null || true
open -a Simulator

echo "▶ Baue Projekt..."
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$IPHONE_UDID" \
  -configuration Debug \
  build 2>&1 | grep -E "error:|warning:|BUILD"

echo "▶ Installiere App auf iPhone-Simulator..."
APP_PATH=$(xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$IPHONE_UDID" \
  -configuration Debug \
  -showBuildSettings 2>/dev/null | grep "BUILT_PRODUCTS_DIR" | head -1 | awk '{print $3}')

xcrun simctl install "$IPHONE_UDID" "$APP_PATH/SimpleTracking.app" 2>/dev/null || true
xcrun simctl launch "$IPHONE_UDID" "com.felix.SimpleTracking"

echo ""
echo "✅ App läuft auf iPhone 17 Simulator"
echo ""
echo "Tipp GPS-Simulation:"
echo "  Im Simulator: Features → Location → Custom Location..."
echo "  Oder GPX-Route: Xcode → Debug → Simulate Location → Add GPX File → SimulatorRoute.gpx"
