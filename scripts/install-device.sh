#!/bin/bash
#
# install-device.sh — build Roost for one iPhone plugged into this Mac and install it.
# This is the cable route, for the days before TestFlight and for any Mac with Xcode.
#
#   scripts/install-device.sh                  # the one iPhone on the cable
#   scripts/install-device.sh <identifier>     # a CoreDevice identifier or a UDID from
#                                              #   `xcrun devicectl list devices`
#   scripts/install-device.sh --build-only …   # build and sign, install nothing
#
# Needs: Xcode 26, xcodegen, Roost/Config/Local.override.xcconfig with the Team ID (see
# docs/RELEASE.md), and Xcode on this Mac signed in to the team so automatic signing can
# register the phone and refresh the profile (`-allowProvisioningUpdates`).
#
# Run it from a Terminal window on this Mac, not over ssh, the first time: codesign asks
# the login keychain for the signing key and the keychain only asks you in a desktop
# session. Answer "Always Allow" and every later run, ssh included, goes through.
#
# The phone has to say yes twice, once each: "Trust This Computer" when the pairing
# prompt appears, and Developer Mode in Settings > Privacy & Security (it restarts).
set -euo pipefail

cd "$(dirname "$0")/.."

build_only=0
device=""
for arg in "$@"; do
  case "$arg" in
    --build-only) build_only=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) device="$arg" ;;
  esac
done

fail() { echo "install-device: $*" >&2; exit 2; }

[ -f Roost/Config/Local.override.xcconfig ] || fail "no Roost/Config/Local.override.xcconfig; docs/RELEASE.md, The Team ID"
command -v xcodegen >/dev/null || fail "xcodegen is missing: brew install xcodegen"
command -v xcrun >/dev/null || fail "Xcode command line tools are missing"

floor=$(sed -n 's/^ *iOS: *"\([0-9.]*\)".*/\1/p' Roost/project.yml | head -1)
[ -n "$floor" ] || fail "could not read the iOS deployment target from Roost/project.yml"

# --- which phone ------------------------------------------------------------------------
devices_json=$(mktemp)
trap 'rm -f "$devices_json"' EXIT   # widened by the signing check below
xcrun devicectl list devices --json-output "$devices_json" >/dev/null 2>&1 \
  || fail "xcrun devicectl could not list devices"

pick=$(python3 - "$devices_json" "$device" <<'PY'
import json, sys
rows = json.load(open(sys.argv[1]))["result"]["devices"]
want = sys.argv[2].strip().lower()
phones = []
for r in rows:
    hw = r.get("hardwareProperties", {}); cp = r.get("connectionProperties", {}); dp = r.get("deviceProperties", {})
    ident = r.get("identifier", ""); udid = hw.get("udid", "") or ""
    if hw.get("platform", "iOS") != "iOS":
        continue
    row = (ident, udid, cp.get("transportType", ""), dp.get("osVersionNumber", ""), dp.get("name", ""), hw.get("marketingName") or hw.get("productType", ""))
    if want:
        if ident.lower() == want or udid.lower() == want or ident.lower().startswith(want) or udid.lower().startswith(want):
            phones.append(row)
    elif row[2] == "wired":
        phones.append(row)
if len(phones) != 1:
    for p in phones or [(r.get("identifier",""), (r.get("hardwareProperties",{}).get("udid") or ""), r.get("connectionProperties",{}).get("transportType",""), r.get("deviceProperties",{}).get("osVersionNumber",""), r.get("deviceProperties",{}).get("name",""), "") for r in rows]:
        print("\t".join(p), file=sys.stderr)
    sys.exit(3)
print("\t".join(phones[0]))
PY
) || {
  if [ -n "$device" ]; then fail "no single phone matches '$device'; the list above is what devicectl sees"; fi
  fail "need exactly one iPhone on the cable, or pass an identifier; the list above is what devicectl sees"
}

IFS=$'\t' read -r ident udid transport os_version phone_name model <<<"$pick"
echo "phone:     ${phone_name:-iPhone} (${model:-?}), $transport, iOS ${os_version:-?}"
echo "device id: $ident"

# --- iOS floor ---------------------------------------------------------------------------
if [ -n "$os_version" ] && [ "$(printf '%s\n%s\n' "$floor" "$os_version" | sort -V | head -1)" != "$floor" ]; then
  fail "this phone is on iOS $os_version and the app needs iOS $floor or later; update the phone first"
fi

# --- pairing and Developer Mode ---------------------------------------------------------
details=$(xcrun devicectl device info details --device "$ident" 2>&1 || true)
if grep -qE 'must be paired|pairingState: *unpaired' <<<"$details"; then
  echo "The phone does not trust this Mac yet. Unlock it and tap Trust when it asks."
  xcrun devicectl manage pair --device "$ident"
  details=$(xcrun devicectl device info details --device "$ident" 2>&1 || true)
fi
if grep -qE 'developerModeStatus: *(disabled|notSupported|unknown)' <<<"$details"; then
  echo "Developer Mode is off on the phone. On the phone: Settings > Privacy & Security >" >&2
  echo "Developer Mode, turn it on, let it restart, unlock it, then run this again." >&2
  exit 4
fi

# --- can this session actually sign? -----------------------------------------------------
# codesign reads the private key out of the login keychain, and a session that is not the
# desktop one cannot open it unless somebody once answered "Always Allow" here. Learning
# that from a failed ten-minute device build is a bad trade, so spend a second on it now.
# Sign by certificate hash, not by name: a Mac can hold two certificates with identical
# names, and `--sign "Apple Development: …"` fails as ambiguous on those.
probe=$(mktemp -d)
trap 'rm -f "$devices_json"; rm -rf "$probe"' EXIT
cert=$(security find-identity -v -p codesigning 2>/dev/null \
  | awk '/"Apple Develop|"Apple Distrib/ { print $2; exit }')
if [ -z "$cert" ]; then
  fail "no Apple Development or Apple Distribution certificate in the login keychain"
fi
cp /usr/bin/true "$probe/probe"
if ! codesign --force --sign "$cert" "$probe/probe" >/dev/null 2>"$probe/err"; then
  if grep -q errSecInternalComponent "$probe/err"; then
    echo "codesign cannot reach the signing key from this session (launchd manager:" >&2
    echo "$(launchctl managername)). Run this once from a Terminal window on this Mac," >&2
    echo "not over ssh, and answer \"Always Allow\" to the keychain prompt. Every later" >&2
    echo "run, ssh included, goes through." >&2
    fail "cannot sign; stopped before the build rather than after it"
  fi
  cat "$probe/err" >&2
  fail "the codesign check failed; stopped before the build"
fi

# --- build -------------------------------------------------------------------------------
( cd Roost && xcodegen generate >/dev/null )
if ! git diff --quiet -- Roost/Roost.xcodeproj/project.pbxproj; then
  echo "note: Roost/Roost.xcodeproj/project.pbxproj differs from the committed one after xcodegen generate"
fi

derived="${ROOST_DERIVED_DATA:-$HOME/.roost-build/DerivedData}"
log="${ROOST_BUILD_LOG:-$HOME/.roost-build/install-device.log}"
mkdir -p "$(dirname "$log")"
echo "building for the phone (log: $log)"
# xcodebuild addresses a phone by its UDID (00008140-…); devicectl by its CoreDevice id.
if ! xcodebuild -project Roost/Roost.xcodeproj -scheme Roost -configuration Debug \
     -destination "id=${udid:-$ident}" \
     -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
     -derivedDataPath "$derived" build >"$log" 2>&1; then
  grep -E 'error:|errSecInternalComponent|No Account|No profiles|Provisioning profile' "$log" | sort -u | head -12 >&2
  if grep -q errSecInternalComponent "$log"; then
    echo "codesign could not use the signing key: run this from a Terminal window on this Mac" >&2
    echo "(not over ssh) and answer Always Allow to the keychain prompt." >&2
  fi
  fail "build failed; full log in $log"
fi
app="$derived/Build/Products/Debug-iphoneos/Roost.app"
[ -d "$app" ] || fail "built, but $app is not there"
echo "built $(git rev-parse --short HEAD) → $app"

if [ "$build_only" = 1 ]; then
  echo "--build-only: not installing"
  exit 0
fi

# --- install -----------------------------------------------------------------------------
xcrun devicectl device install app --device "$ident" "$app"
echo "installed on ${phone_name:-the phone}. Open Roost; with no token it starts at onboarding."
echo "Mint the pairing code on theoldone (docs/RELEASE.md, A new phone)."
