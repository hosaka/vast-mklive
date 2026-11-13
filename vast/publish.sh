#!/bin/bash
#
# Upload files to the Forgejo generic package registry and remove everything
# else from that package version. Only the latest build is kept.
#
# Usage: vast/publish.sh <version> <file>...
#   e.g. vast/publish.sh noctalia out/vast-noctalia-*.iso*
#
# Files end up at $FORGEJO_URL/api/packages/$OWNER/generic/$PACKAGE/<version>/<file>
#
# Environment:
#   ISO_UPLOAD_TOKEN  token with write:package scope (required)
#   FORGEJO_URL       default: https://code.hosaka.cc
#   OWNER             default: hosaka
#   PACKAGE           default: vast-iso

set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=common.sh
. "$(dirname "$(readlink -f "$0")")/common.sh"

FORGEJO_URL=${FORGEJO_URL:-https://code.hosaka.cc}
OWNER=${OWNER:-hosaka}
PACKAGE=${PACKAGE:-vast-iso}

[ $# -ge 2 ] || die "usage: $0 <version> <file>..."
[ -n "${ISO_UPLOAD_TOKEN:-}" ] || die "ISO_UPLOAD_TOKEN is not set"

version=$1
shift
url="$FORGEJO_URL/api/packages/$OWNER/generic/$PACKAGE/$version"
auth="Authorization: token $ISO_UPLOAD_TOKEN"

# files currently in this version, empty if it does not exist yet
existing=$(curl --silent --header "$auth" \
  "$FORGEJO_URL/api/v1/packages/$OWNER/generic/$PACKAGE/$version/files" |
  jq -r 'if type == "array" then .[].name else empty end')

uploaded=()
for path in "$@"; do
  file=$(basename "$path")
  # the registry refuses to overwrite, e.g. a rebuild on the same day
  if grep -qxF "$file" <<<"$existing"; then
    info "replacing $file"
    curl --silent --fail --request DELETE --header "$auth" "$url/$file"
  fi
  info "uploading $file ($(du -h "$path" | cut -f1))"
  curl --fail --request PUT --header "$auth" --upload-file "$path" \
    --output /dev/null "$url/$file"
  uploaded+=("$file")
done

# keep only what was just uploaded
while read -r file; do
  [ -n "$file" ] || continue
  if ! printf '%s\n' "${uploaded[@]}" | grep -qxF "$file"; then
    info "removing old $file"
    curl --silent --fail --request DELETE --header "$auth" "$url/$file"
  fi
done <<<"$existing"

for file in "${uploaded[@]}"; do
  success "$url/$file"
done
