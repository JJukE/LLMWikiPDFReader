#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 || ! "$1" =~ ^[0-9]+([.][0-9]+)*$ ]]; then
    echo "Usage: $0 <numeric-build-version>" >&2
    exit 2
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
project_path="$repo_root/LLMWikiPDFReader/LLMWikiPDFReader.xcodeproj"
output_dir="$repo_root/.build/sidestore"
build_version="$1"
marketing_version="1.0"
bundle_identifier="com.example.LLMWikiPDFReader"
release_tag="sidestore-latest"
release_base_url="https://github.com/JJukE/LLMWikiPDFReader/releases/download/$release_tag"
icon_url="https://raw.githubusercontent.com/JJukE/LLMWikiPDFReader/main/LLMWikiPDFReader/LLMWikiPDFReader/Assets.xcassets/AppIcon.appiconset/AppIcon-iOS.png"

mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
temp_root="$(mktemp -d "${TMPDIR:-/tmp}/llmwiki-pdfreader.XXXXXX")"
trap 'rm -rf "$temp_root"' EXIT

derived_data="$temp_root/DerivedData"
app_path="$derived_data/Build/Products/Release-iphoneos/LLMWikiPDFReader.app"
ipa_path="$output_dir/LLMWikiPDFReader.ipa"
source_path="$output_dir/source.json"

xcodebuild \
    -project "$project_path" \
    -scheme LLMWikiPDFReader \
    -configuration Release \
    -sdk iphoneos \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    CURRENT_PROJECT_VERSION="$build_version" \
    MARKETING_VERSION="$marketing_version" \
    PRODUCT_BUNDLE_IDENTIFIER="$bundle_identifier" \
    build

if [[ ! -d "$app_path" ]]; then
    echo "Expected app bundle was not produced: $app_path" >&2
    exit 1
fi

info_plist="$app_path/Info.plist"
actual_bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")"
actual_marketing_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")"
actual_build_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")"
minimum_os_version="$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$info_plist")"

[[ "$actual_bundle_identifier" == "$bundle_identifier" ]]
[[ "$actual_marketing_version" == "$marketing_version" ]]
[[ "$actual_build_version" == "$build_version" ]]
[[ "$minimum_os_version" == "26.1" ]]
[[ ! -e "$app_path/embedded.mobileprovision" ]]

mkdir -p "$temp_root/Payload"
/usr/bin/ditto "$app_path" "$temp_root/Payload/LLMWikiPDFReader.app"
rm -f "$ipa_path"
(
    cd "$temp_root"
    /usr/bin/zip -qry "$ipa_path" Payload
)
/usr/bin/unzip -tq "$ipa_path"

ipa_size="$(/usr/bin/stat -f '%z' "$ipa_path")"
release_date="$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')"
commit_sha="${GITHUB_SHA:-$(git -C "$repo_root" rev-parse HEAD)}"

SOURCE_PATH="$source_path" \
BUNDLE_IDENTIFIER="$bundle_identifier" \
MARKETING_VERSION="$marketing_version" \
BUILD_VERSION="$build_version" \
MINIMUM_OS_VERSION="$minimum_os_version" \
IPA_SIZE="$ipa_size" \
RELEASE_DATE="$release_date" \
COMMIT_SHA="$commit_sha" \
RELEASE_BASE_URL="$release_base_url" \
ICON_URL="$icon_url" \
/usr/bin/ruby -rjson -e '
source = {
  "name" => "JJukE LLM Wiki Apps",
  "subtitle" => "Unsigned builds for personal SideStore installation",
  "description" => "Automated builds from the LLMWikiPDFReader main branch.",
  "website" => "https://github.com/JJukE/LLMWikiPDFReader",
  "tintColor" => "#4D7CFE",
  "featuredApps" => [ENV.fetch("BUNDLE_IDENTIFIER")],
  "apps" => [
    {
      "name" => "LLMWikiPDFReader",
      "bundleIdentifier" => ENV.fetch("BUNDLE_IDENTIFIER"),
      "developerName" => "JJukE",
      "subtitle" => "Research PDF reader for an LLM Wiki workflow",
      "localizedDescription" => "Reads PDFs without modifying them and stores semantic highlights in sidecar JSON.",
      "iconURL" => ENV.fetch("ICON_URL"),
      "tintColor" => "#4D7CFE",
      "category" => "utilities",
      "versions" => [
        {
          "version" => ENV.fetch("MARKETING_VERSION"),
          "buildVersion" => ENV.fetch("BUILD_VERSION"),
          "date" => ENV.fetch("RELEASE_DATE"),
          "localizedDescription" => "Automated main build #{ENV.fetch("COMMIT_SHA")[0, 12]}",
          "downloadURL" => "#{ENV.fetch("RELEASE_BASE_URL")}/LLMWikiPDFReader.ipa",
          "size" => Integer(ENV.fetch("IPA_SIZE")),
          "minOSVersion" => ENV.fetch("MINIMUM_OS_VERSION")
        }
      ],
      "appPermissions" => {
        "entitlements" => [],
        "privacy" => {}
      }
    }
  ],
  "news" => []
}
File.write(ENV.fetch("SOURCE_PATH"), JSON.pretty_generate(source) + "\n")
'

(
    cd "$output_dir"
    /usr/bin/shasum -a 256 LLMWikiPDFReader.ipa source.json > SHA256SUMS
)

/usr/bin/ruby -rjson -e '
source = JSON.parse(File.read(ARGV.fetch(0)))
app = source.fetch("apps").fetch(0)
version = app.fetch("versions").fetch(0)
abort "bundle identifier mismatch" unless app.fetch("bundleIdentifier") == ARGV.fetch(1)
abort "build version mismatch" unless version.fetch("buildVersion") == ARGV.fetch(2)
abort "IPA size mismatch" unless version.fetch("size") == File.size(ARGV.fetch(3))
' "$source_path" "$bundle_identifier" "$build_version" "$ipa_path"

echo "Created SideStore artifacts in $output_dir"
