#!/bin/bash
#
# Build a Vast Linux ISO: Void Linux with my packages, services, system files
# and dotfiles, all taken from my chezmoi repository. See vast/README.md.
#
# Usage: DOTFILES=<dir> vast/build.sh <profile|all>
#
# Normally invoked through `just iso <profile>`. `all` builds every profile in
# vast/profiles/, one after the other. Runs as root, except with DRY_RUN=1
# which only prints what would be built.
#
# Environment:
#   DOTFILES   chezmoi repository (the directory with .chezmoiroot), baked in
#   OUT_DIR    output directory for the ISO and its checksum (default: out)
#   FAST=1     gzip squashfs instead of xz, quicker to build but a bigger ISO
#   KEEP=1     keep the mklive build directory
#   DRY_RUN=1  print the package list, services and mklive.sh arguments

set -euo pipefail
export LC_ALL=C

# shellcheck source-path=SCRIPTDIR source=common.sh
. "$(dirname "$(readlink -f "$0")")/common.sh"

# mklive.sh expects to run from the repository root
cd "$(dirname "$(readlink -f "$0")")/.."

# installer.sh dependencies, mkiso.sh adds the same for the official ISOs
INSTALLER_PACKAGES="dialog cryptsetup lvm2 mdadm grub-i386-efi grub-x86_64-efi"

[ $# -eq 1 ] || die "usage: $0 <profile|all>"
profile=$1

if [ "$profile" = all ]; then
  for env in vast/profiles/*.env; do
    "$PWD/vast/build.sh" "$(basename "$env" .env)"
  done
  exit 0
fi

[ -f "vast/profiles/$profile.env" ] || die "no such profile: vast/profiles/$profile.env"
[ -f "${DOTFILES:-}/.chezmoiroot" ] || die "DOTFILES must point to the chezmoi repository, got '${DOTFILES:-}'"
[ -d "$DOTFILES/system" ] || die "$DOTFILES has no system/ directory"
[ -n "${DRY_RUN:-}" ] || [ "$(id -u)" -eq 0 ] || die "must run as root, use: just iso $profile"
for tool in chezmoi git jq; do
  command -v "$tool" >/dev/null || die "$tool is required"
done

# shellcheck source-path=SCRIPTDIR source=profiles/noctalia.env
. "vast/profiles/$profile.env"

OUT_DIR=$(readlink -m "${OUT_DIR:-out}")
iso="$OUT_DIR/vast-$profile-x86_64-$(date -u +%Y%m%d).iso"

work=$(mktemp -d "${TMPDIR:-/tmp}/vast-build.XXXXXX")
trap 'rm -rf "$work"' EXIT

# Snapshot the dotfiles. The same copy is used to read the package lists here
# and to populate the image in postsetup.sh.
cp -a "$DOTFILES" "$work/dotfiles"
[ -n "${DRY_RUN:-}" ] || chown -R root:root "$work/dotfiles"
if [ -n "$(git -C "$work/dotfiles" status --porcelain 2>/dev/null)" ]; then
  warning "the dotfiles have uncommitted changes, they will be baked in"
fi

# Answers for the promptBoolOnce calls in .chezmoi.toml.tmpl. `chezmoi init`
# keeps values that already exist in the config, so seeding them avoids prompts.
{
  echo "[data]"
  for flag in $CHEZMOI_FLAGS; do
    echo "  ${flag%%=*} = ${flag#*=}"
  done
} >"$work/seed.toml"

# Render the real config on the host as well. Fails early if a flag is missing
# and lets `chezmoi data` see the same data as the image will.
cp "$work/seed.toml" "$work/chezmoi.toml"
chezmoi_args=(
  --no-tty
  --source "$work/dotfiles"
  --config "$work/chezmoi.toml"
  --persistent-state "$work/chezmoistate.boltdb"
  --cache "$work/cache"
)
HOME="$work" chezmoi init "${chezmoi_args[@]}" </dev/null ||
  die "chezmoi init failed, are all prompted flags set in CHEZMOI_FLAGS?"
chezmoi_data=$(HOME="$work" chezmoi data --format json "${chezmoi_args[@]}")

# Packages or services of every enabled group in .chezmoidata/packages.toml
group_items() {
  jq -r --arg kind "$1" '
		. as $data | .packages.xbps | to_entries[]
		| select(.key != "remove")
		| select(.key == "common" or $data[.key] == true)
		| .value[$kind][]?' <<<"$chezmoi_data"
}
mapfile -t packages < <(group_items packages)
mapfile -t services < <(group_items services)
[ ${#packages[@]} -gt 0 ] || die "no packages found in the chezmoi data"

# Build from the same repositories that the installed system is configured
# with, xbps.d files are processed in alphabetical order (the glob is sorted)
xbpsd="$work/dotfiles/system/etc/xbps.d"
mapfile -t repos < <(cat "$xbpsd"/*.conf | sed -n 's/^repository=//p')
mapfile -t ignored < <(cat "$xbpsd"/*.conf | sed -n 's/^ignorepkg=//p')
[ ${#repos[@]} -gt 0 ] || die "no repository= entries in $xbpsd"

# void-installer, the same way mkiso.sh includes it, with the profile's
# USERGROUPS added to the groups that its user account menu ticks by default
mkdir -p "$work/include/usr/bin"
installer="$work/include/usr/bin/void-installer"
usergroups=${USERGROUPS// /,}

# shellcheck source=/dev/null
mklive_version=$(. ./lib.sh && PROGNAME='' version)
sed -e "s/@@MKLIVE_VERSION@@/$mklive_version/" \
  -e "s/^\(\s*_groups=\"[^\"]*\)/\1,$usergroups/" \
  installer.sh >"$installer"
grep -q "_groups=\".*,$usergroups\"" "$installer" ||
  die "could not set the default groups in void-installer, has installer.sh changed?"
chmod 755 "$installer"

args=(
  -a x86_64
  -v "$KERNEL"
  -T "$TITLE"
  -k "$KEYMAP"
  -l "$LOCALE"
  -p "${packages[*]} $INSTALLER_PACKAGES $EXTRA_PACKAGES"
  -S "${services[*]}"
  -g "${ignored[*]}"
  -I "$work/include"
  -x "$PWD/vast/postsetup.sh"
  -C "live.user=$USERNAME live.shell=$USERSHELL"
  -o "$iso"
)

# mklive.sh prepends every -r to the list and the first repository that has a
# package wins, pass them in reverse to keep the xbps.d order
for ((i = ${#repos[@]} - 1; i >= 0; i--)); do
  args+=(-r "${repos[i]}")
done
[ -z "${FAST:-}" ] || args+=(-s gzip)
[ -z "${KEEP:-}" ] || args+=(-K)

info "profile $profile, ${#packages[@]} packages from chezmoi, kernel $KERNEL"
info "services: ${services[*]}"
info "repositories: ${repos[*]}"

if [ -n "${DRY_RUN:-}" ]; then
  printf '%s\n' "${packages[@]}" | column -c "${COLUMNS:-100}"
  printf './mklive.sh'
  printf ' %q' "${args[@]}"
  printf '\n'
  exit 0
fi

# read by postsetup.sh, which mklive.sh runs with the rootfs as its argument
export VAST_DOTFILES="$work/dotfiles"
export VAST_CHEZMOI_SEED="$work/seed.toml"
export VAST_USER="$USERNAME"
export VAST_DOTFILES_URL="$DOTFILES_URL"
export VAST_DOTFILES_PUSHURL="$DOTFILES_PUSHURL"

mkdir -p "$OUT_DIR"
[ -e "$OUT_DIR/.gitignore" ] || echo '*' >"$OUT_DIR/.gitignore"

./mklive.sh "${args[@]}"

(cd "$OUT_DIR" && sha256sum "$(basename "$iso")" >"$(basename "$iso").sha256")

# chown results back to whoever ran the build
owner=${DOAS_USER:-${SUDO_USER:-}}
[ -z "$owner" ] || chown -R "$owner:" "$OUT_DIR"

success "done: $iso"
