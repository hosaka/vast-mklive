#!/bin/bash
#
# mklive.sh -x hook, called with the rootfs path after packages are installed
# and services are enabled, before the initramfs and squashfs are generated.
# Uses the VAST_* variables exported by vast/build.sh.
#
# This hook:
# - Applies system files (system/ in chezmoi repo) to /
# - Removes unused initramfs that the kernel hook generated
# - Renders the dotfiles for $VAST_USER the same way `chezmoi init` does
# - Moves the user home directory to /etc/skel, the live user and the user
#   created by void-installer both start from it

set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=common.sh
. "$(dirname "$(readlink -f "$0")")/common.sh"

rootfs=$1
home=/home/$VAST_USER
source_dir=$home/.local/share/chezmoi

# run a command inside the rootfs with a clean environment, extra
# NAME=value arguments are added to it
in_rootfs() {
  chroot "$rootfs" env -i PATH=/usr/bin:/usr/sbin LANG=C.UTF-8 "$@"
}

info "staging the chezmoi source in $source_dir"
mkdir -p "$rootfs$home/.local/share" "$rootfs$home/.config/chezmoi"
cp -a "$VAST_DOTFILES" "$rootfs$source_dir"
cp "$VAST_CHEZMOI_SEED" "$rootfs$home/.config/chezmoi/chezmoi.toml"

# chezmoi externals, from .chezmoiexternal.toml, are created during apply and need DNS
resolv=$rootfs/etc/resolv.conf
if [ -e "$resolv" ] || [ -L "$resolv" ]; then
  mv "$resolv" "$resolv.vast"
fi
cp -L /etc/resolv.conf "$resolv"
restore_resolv() {
  rm -f "$resolv"
  if [ -e "$resolv.vast" ] || [ -L "$resolv.vast" ]; then
    mv "$resolv.vast" "$resolv"
  fi
}
trap restore_resolv EXIT

info "applying system files"
# root's chezmoi state ends up in /root/.config/chezmoi on the installed system
in_rootfs HOME=/root chezmoi apply --no-tty --source "$source_dir/system" --destination /

info "naming the GRUB menu entries Vast"
sed -i 's/^GRUB_DISTRIBUTOR=.*/GRUB_DISTRIBUTOR="Vast"/' "$rootfs/etc/default/grub"

info "removing the kernel hook's initramfs"
# nothing uses this, the live system boots the initrd that mklive.sh builds
# and void-installer runs dracut on the target after copying the rootfs
rm -f "$rootfs"/boot/initramfs-*.img

info "applying dotfiles for $VAST_USER"
in_rootfs HOME="$home" USER="$VAST_USER" CHEZMOI_NO_SECRETS=1 \
  chezmoi init --no-tty
in_rootfs HOME="$home" USER="$VAST_USER" CHEZMOI_NO_SECRETS=1 \
  chezmoi apply --no-tty --exclude scripts

git -C "$rootfs$source_dir" remote set-url origin "$VAST_DOTFILES_URL" 2>/dev/null ||
  git -C "$rootfs$source_dir" remote add origin "$VAST_DOTFILES_URL"
git -C "$rootfs$source_dir" remote set-url --push origin "$VAST_DOTFILES_PUSHURL"

info "moving $home to /etc/skel"
cp -a "$rootfs$home/." "$rootfs/etc/skel/"
rm -rf "${rootfs:?}$home"
