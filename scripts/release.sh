#!/bin/bash
#
# release.sh — archive Roost, upload it to App Store Connect, and let TestFlight hand it
# to Anne's and Wes's phones. macOS only; needs Xcode 26 and xcodegen.
#
#   scripts/release.sh --dry-run        # check everything, change nothing
#   scripts/release.sh                  # build number = git commit count
#   scripts/release.sh --build 57       # build number you pick
#
# ---------------------------------------------------------------------------------------
# Why this uploads with `xcodebuild -exportArchive` and not `xcrun altool --upload-app`
# ---------------------------------------------------------------------------------------
# Checked 2026-09-13 against Apple's current documentation, and against the installed
# toolchain (Xcode 26.3, build 17C529) rather than from memory:
#
#   * `xcodebuild -help` documents the ExportOptions key `destination` as "Determines
#     whether the app is exported locally or uploaded to Apple. Options are export or
#     upload." So -exportArchive uploads on its own. It also documents `method` values,
#     where `app-store-connect` is current and `app-store` is "deprecated: use
#     app-store-connect". scripts/ExportOptions.plist uses both of those.
#
#   * altool is NOT dead for app submission. TN3147 "Migrating to the latest notarization
#     tool" deprecates altool for *notarization* only, and says so explicitly: "altool is
#     still a good way to perform other tasks, like submitting an app to the App Store."
#     https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool
#     App Store Connect Help > Upload builds still lists altool, Transporter, Xcode and the
#     App Store Connect API as upload methods, with `xcrun altool --upload-app -f file -t
#     platform`, and `xcrun altool --upload-app` is present in the shipped altool 26.10.1.
#     https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/
#     (The same page's only 2026 requirement is "Starting in 2026, you'll be required to
#     use Xcode 14 or later to upload your app to App Store Connect" — moot here. The
#     `-assetFile`-instead-of-`-f` change doing the rounds is about Apple-hosted asset
#     packs, not .ipa uploads.)
#
#   * So both work, and -exportArchive is chosen because it is one step instead of two, it
#     is the code path Xcode's own Distribute App > Upload uses, it takes the App Store
#     Connect API key with the same three flags the archive step already needs, and it
#     wants no Apple ID, no app-specific password, and no Transporter from the Mac App
#     Store. If Apple ever does retire this route, the fallback is the altool line above.
#     https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases
#
# ---------------------------------------------------------------------------------------
# Credentials — none of this is in the repo
# ---------------------------------------------------------------------------------------
# Team ID:  Roost/Config/Local.override.xcconfig (gitignored). See Local.override.xcconfig.example.
# ASC key:  ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH in the environment, or in a file at
#           $ROOST_RELEASE_ENV, default ~/.config/roost/release.env — outside the repo.
#
# It has to be a *team* key, not an individual one: -allowProvisioningUpdates uses the
# Provisioning endpoints, and "Individual keys aren't able to use Provisioning endpoints".
# https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api
#
# Full runbook, including the first-time App Store Connect and portal setup: docs/RELEASE.md

set -euo pipefail

SCHEME="Roost"
APP_NAME="Roost"
DEFAULT_ENV_FILE="$HOME/.config/roost/release.env"

die() { printf 'release.sh: %s\n' "$1" >&2; exit 1; }
note() { printf '  %s\n' "$1"; }
step() { printf '\n== %s\n' "$1"; }

usage() {
	cat <<'EOF'
Usage: scripts/release.sh [--build N] [--dry-run]

  --build N   Build number (CURRENT_PROJECT_VERSION). Default: git commit count.
  --dry-run   Validate the Team ID, the build number, the export options and the
              credentials, print the plan, and stop before changing any file.
  -h, --help  This.

Needs a Team ID in Roost/Config/Local.override.xcconfig and an App Store Connect team API key.
See docs/RELEASE.md.
EOF
}

# ---- arguments ------------------------------------------------------------------------

build_number=""
dry_run=no

while [ $# -gt 0 ]; do
	case "$1" in
		--build)
			[ $# -ge 2 ] || die "--build needs a number"
			build_number="$2"
			shift 2
			;;
		--build=*)
			build_number="${1#--build=}"
			shift
			;;
		--dry-run)
			dry_run=yes
			shift
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			usage >&2
			die "unknown argument: $1"
			;;
	esac
done

if [ -n "$build_number" ]; then
	case "$build_number" in
		''|*[!0-9]*) die "--build must be a positive integer, got: $build_number" ;;
	esac
	[ "$build_number" -gt 0 ] 2>/dev/null || die "--build must be a positive integer, got: $build_number"
fi

# ---- where we are --------------------------------------------------------------------

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" \
	|| die "not in a git checkout; run this from the Roost repo"
cd "$repo_root"

project_yml="Roost/project.yml"
xcodeproj="Roost/$APP_NAME.xcodeproj"
override_xcconfig="Roost/Config/Local.override.xcconfig"
export_options="scripts/ExportOptions.plist"

[ -f "$project_yml" ] || die "no $project_yml — is this the Roost repo?"
[ -f "$export_options" ] || die "no $export_options"

command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild not found; install Xcode 26"
command -v xcodegen >/dev/null 2>&1 || die "xcodegen not found; brew install xcodegen"

# ---- the Team ID ---------------------------------------------------------------------

step "Team ID"

[ -f "$override_xcconfig" ] || die "no $override_xcconfig.
  A release has to be signed, and the Team ID is the one build setting this repo will
  never hold. Create it:
      cp Roost/Config/Local.override.xcconfig.example $override_xcconfig
      \$EDITOR $override_xcconfig
  The Team ID is on developer.apple.com/account under Membership details."

# Last DEVELOPMENT_TEAM assignment in the file, minus any // comment, quotes and spaces.
team_id="$(
	sed -n 's|^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*\(.*\)$|\1|p' "$override_xcconfig" \
		| sed 's|//.*$||' \
		| tr -d '"'"'"' \t\r' \
		| grep -v '^$' \
		| tail -1
)" || true

[ -n "${team_id:-}" ] || die "DEVELOPMENT_TEAM is empty in $override_xcconfig.
  Put the Team ID after the '=' — ten letters and digits, from
  developer.apple.com/account under Membership details. Without it xcodebuild would
  archive something unsigned that App Store Connect will not take."

note "$override_xcconfig sets a Team ID (${#team_id} characters)"

# ---- the build number ----------------------------------------------------------------

step "Version"

if [ -z "$build_number" ]; then
	build_number="$(git rev-list --count HEAD)"
	note "build $build_number (git commit count)"
else
	note "build $build_number (passed in)"
fi

marketing_version="$(
	sed -n 's|^[[:space:]]*MARKETING_VERSION:[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}[[:space:]]*$|\1|p' "$project_yml" | tail -1
)"
[ -n "$marketing_version" ] || die "could not read MARKETING_VERSION from $project_yml"

current_build="$(
	sed -n 's|^[[:space:]]*CURRENT_PROJECT_VERSION:[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}[[:space:]]*$|\1|p' "$project_yml" | tail -1
)"
[ -n "$current_build" ] || die "could not read CURRENT_PROJECT_VERSION from $project_yml"

note "version $marketing_version, project.yml currently says build $current_build"

head_sha="$(git rev-parse --short HEAD)"
note "commit $head_sha on $(git rev-parse --abbrev-ref HEAD)"

if [ -n "$(git status --porcelain)" ]; then
	note ""
	note "WARNING: the working tree is dirty. The build in TestFlight will not match"
	note "         $head_sha, and nothing will say so. Commit first if you care."
fi

# ---- the export options --------------------------------------------------------------

step "Export options"

plutil -lint "$export_options" >/dev/null || die "$export_options is not a valid plist"

export_method="$(plutil -extract method raw -o - "$export_options" 2>/dev/null)" || export_method=""
export_destination="$(plutil -extract destination raw -o - "$export_options" 2>/dev/null)" || export_destination=""

[ "$export_method" = "app-store-connect" ] \
	|| die "$export_options has method '$export_method'; expected app-store-connect"
[ "$export_destination" = "upload" ] \
	|| die "$export_options has destination '$export_destination'; expected upload"

note "$export_options: method $export_method, destination $export_destination"

# ---- App Store Connect API key -------------------------------------------------------

step "App Store Connect API key"

env_file="${ROOST_RELEASE_ENV:-$DEFAULT_ENV_FILE}"
creds_source=""

if [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ] && [ -n "${ASC_KEY_PATH:-}" ]; then
	creds_source="the environment"
elif [ -f "$env_file" ]; then
	# shellcheck disable=SC1090
	. "$env_file"
	creds_source="$env_file"
fi

creds_ok=no
if [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ] && [ -n "${ASC_KEY_PATH:-}" ]; then
	if [ -f "${ASC_KEY_PATH}" ]; then
		creds_ok=yes
	else
		creds_ok=nokey
	fi
fi

creds_help="Set ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH in the environment, or write them
  to $env_file (outside the repo, so it cannot be committed):

      ASC_KEY_ID=ABCDE12345
      ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000
      ASC_KEY_PATH=\$HOME/.appstoreconnect/private_keys/AuthKey_ABCDE12345.p8

  It must be a team key with the App Manager role, generated in App Store Connect under
  Users and Access > Integrations > App Store Connect API > Team Keys. Individual keys
  cannot use the Provisioning endpoints that -allowProvisioningUpdates needs.
  See docs/RELEASE.md."

case "$creds_ok" in
	yes)    note "loaded from $creds_source; key file present" ;;
	nokey)  die "ASC_KEY_PATH points at a file that is not there: $ASC_KEY_PATH" ;;
	no)
		if [ "$dry_run" = yes ]; then
			note "NOT SET — a real run would stop here."
			note ""
			printf '  %s\n' "$creds_help"
		else
			die "no App Store Connect API key.
  $creds_help"
		fi
		;;
esac

# ---- dry run stops here --------------------------------------------------------------

archive_dir="build/release"
archive_path="$archive_dir/$APP_NAME-$build_number.xcarchive"
export_path="$archive_dir/$APP_NAME-$build_number-export"

if [ "$dry_run" = yes ]; then
	step "Dry run — stopping before the archive"
	note "Would set CURRENT_PROJECT_VERSION to $build_number in $project_yml"
	note "Would run: xcodegen generate (in Roost/)"
	note "Would archive $SCHEME for generic/platform=iOS to $archive_path"
	note "Would export and upload with $export_options"
	note ""
	note "Nothing was written. git status is unchanged."
	exit 0
fi

# ---- bump and regenerate -------------------------------------------------------------

step "Bump to build $build_number and regenerate"

/usr/bin/sed -i '' -E \
	"s|^([[:space:]]*CURRENT_PROJECT_VERSION:[[:space:]]*).*\$|\1\"$build_number\"|" \
	"$project_yml"

written_build="$(
	sed -n 's|^[[:space:]]*CURRENT_PROJECT_VERSION:[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}[[:space:]]*$|\1|p' "$project_yml" | tail -1
)"
[ "$written_build" = "$build_number" ] \
	|| die "failed to set CURRENT_PROJECT_VERSION in $project_yml (it reads '$written_build')"
note "$project_yml: CURRENT_PROJECT_VERSION = $build_number"

( cd Roost && xcodegen generate )
note "regenerated $xcodeproj"

# ---- archive -------------------------------------------------------------------------

step "Archive"

mkdir -p "$archive_dir"
rm -rf "$archive_path"

note "this takes a few minutes"
xcodebuild \
	-project "$xcodeproj" \
	-scheme "$SCHEME" \
	-configuration Release \
	-destination 'generic/platform=iOS' \
	-archivePath "$archive_path" \
	-skipPackagePluginValidation \
	-allowProvisioningUpdates \
	-authenticationKeyPath "$ASC_KEY_PATH" \
	-authenticationKeyID "$ASC_KEY_ID" \
	-authenticationKeyIssuerID "$ASC_ISSUER_ID" \
	clean archive

[ -d "$archive_path" ] || die "no archive at $archive_path"
note "archived to $archive_path"

# ---- export and upload ---------------------------------------------------------------

step "Export and upload to App Store Connect"

rm -rf "$export_path"

# Apple's rsync, not Homebrew's. Xcode's IPA packaging step shells out to plain `rsync`, and
# with Homebrew's rsync 3.4.4 first on PATH it dies with "syntax or usage error (code 1) at
# main.c(1806)" and xcodebuild reports only `error: exportArchive Copy failed` — which names
# neither rsync nor PATH. macOS ships openrsync at /usr/bin/rsync and that is what Xcode
# expects. Verified 2026-09-16: identical archive, export failed with Homebrew's rsync first
# and succeeded with this line, changing nothing else.
#
# /usr/bin goes first rather than dropping /opt/homebrew, because xcodegen lives in Homebrew
# and the archive step above needs it.
PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH" \
xcodebuild -exportArchive \
	-archivePath "$archive_path" \
	-exportPath "$export_path" \
	-exportOptionsPlist "$export_options" \
	-allowProvisioningUpdates \
	-authenticationKeyPath "$ASC_KEY_PATH" \
	-authenticationKeyID "$ASC_KEY_ID" \
	-authenticationKeyIssuerID "$ASC_ISSUER_ID"

# ---- where it went -------------------------------------------------------------------

cat <<EOF

== Uploaded

  $APP_NAME $marketing_version (build $build_number) from commit $head_sha

  App Store Connect > Apps > $APP_NAME > TestFlight > iOS builds
  https://appstoreconnect.apple.com

  It shows as "Processing" for a few minutes to half an hour. When that clears, the
  internal TestFlight group gets it automatically and both phones are notified. If it
  never clears, or it comes back "Invalid Binary", App Store Connect emails the reason.

  Archive kept at $archive_path — that is where the dSYMs for this build live, so leave
  it be if you want symbolicated crash reports for it later.

  project.yml now says build $build_number — commit that on a branch and open a pull
  request, since main takes pull requests only.
EOF
