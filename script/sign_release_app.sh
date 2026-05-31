#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 /path/to/App.app 'Developer ID Application: ...' [/path/to/keychain]" >&2
  exit 2
fi

app_path="$1"
identity="$2"
keychain_path="${3:-}"

if [[ ! -d "$app_path" ]]; then
  echo "App bundle not found: $app_path" >&2
  exit 1
fi

codesign_args=(
  --force
  --timestamp
  --options runtime
  --sign "$identity"
)

if [[ -n "$keychain_path" ]]; then
  codesign_args+=(--keychain "$keychain_path")
fi

sign_standalone() {
  local path="$1"
  codesign "${codesign_args[@]}" "$path"
}

sign_bundle() {
  local path="$1"
  # 第三方 bundle（如 SteamCMDRuntime）可能有 unsealed contents，
  # 先清掉旧签名，再用 --deep 重新签
  rm -rf "$path/Contents/_CodeSignature" 2>/dev/null || true
  rm -rf "$path/_CodeSignature" 2>/dev/null || true
  codesign "${codesign_args[@]}" --deep "$path"
}

# Collect all nested bundle paths so we can exclude their contents
# from standalone Mach-O signing.
nested_bundle_list="$(mktemp)"
find "$app_path/Contents" \
  \( -name '*.app' -o -name '*.appex' -o -name '*.framework' -o -name '*.xpc' -o -name '*.bundle' -o -name '*.kext' -o -name '*.plugin' \) \
  -print > "$nested_bundle_list"

# Step 1: sign only truly standalone Mach-O binaries (not inside any bundle)
while IFS= read -r binary_path; do
  [[ -n "$binary_path" ]] || continue
  sign_standalone "$binary_path"
done < <(
  find "$app_path/Contents" -type f ! -path '*/_CodeSignature/*' -print \
    | while IFS= read -r candidate; do
        # Skip files inside nested bundles (they get signed with their bundle)
        inside_bundle=false
        while IFS= read -r bundle_path; do
          [[ -n "$bundle_path" ]] || continue
          if [[ "$candidate" == "$bundle_path"/* ]]; then
            inside_bundle=true
            break
          fi
        done < "$nested_bundle_list"
        [[ "$inside_bundle" == true ]] && continue

        if file -b "$candidate" | grep -q 'Mach-O'; then
          printf '%s\t%s\n' "$(awk -F/ '{print NF}' <<<"$candidate")" "$candidate"
        fi
      done \
    | sort -rn \
    | cut -f2-
)

# Step 2: sign nested bundles (deepest first, excluding main app)
while IFS= read -r nested_bundle; do
  [[ -n "$nested_bundle" ]] || continue
  [[ "$nested_bundle" == "$app_path" ]] && continue
  sign_bundle "$nested_bundle"
done < <(
  awk '{ print gsub(/\//, "&") "\t" $0 }' "$nested_bundle_list" \
    | sort -rn \
    | cut -f2-
)

rm -f "$nested_bundle_list"

# Step 3: sign the main app bundle
sign_bundle "$app_path"
codesign --verify --strict --deep --verbose=4 "$app_path"
