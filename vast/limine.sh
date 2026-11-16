#!/bin/bash
#
# Install limine on a system that void-installer just installed. UEFI only.
#
# Usage: vast-limine <root partition>
#
# void-installer only knows grub, so in its BootLoader menu choose "Manage
# bootloader otherwise" create and mount the EFI system partition at /boot. Since
# limine only reads vfat partitions, don't forget to format it to FAT32.
#
# Copies limine to EFI/limine on the ESP, writes a limine.conf with the kernel
# command line, lets the installed /etc/kernel.d/post-install/60-limine hook
# add the kernel to it and adds a UEFI boot entry.

set -euo pipefail

die() {
  echo "vast-limine: $*" >&2
  exit 1
}

[ $# -eq 1 ] || die "usage: vast-limine <root partition>, e.g. /dev/sda2"
root=$1
[ "$(id -u)" -eq 0 ] || die "must run as root"
[ -b "$root" ] || die "$root is not a block device"
[ -d /sys/firmware/efi ] || die "the live system did not boot with UEFI, limine is only set up for UEFI"

target=$(mktemp -d /mnt/vast-limine.XXXXXX)
cleanup() {
  umount -R "$target" 2>/dev/null || :
  rmdir "$target"
}
trap cleanup EXIT

mount "$root" "$target"
hook=/etc/kernel.d/post-install/60-limine
grep -qE '^\S+\s+/boot\s+vfat\s' "$target/etc/fstab" ||
  die "$root has no vfat /boot in /etc/fstab, mount the EFI system partition at /boot in void-installer"
[ -f "$target/usr/share/limine/BOOTX64.EFI" ] || die "limine is not installed on $root"
[ -x "$target$hook" ] || die "$hook is not installed on $root"

# the hook runs in the installed system, with its fstab and /boot
for dir in dev proc sys; do
  mount --rbind "/$dir" "$target/$dir"
  mount --make-rslave "$target/$dir"
done
chroot "$target" mount /boot

efidir=$target/boot/EFI/limine
mkdir -p "$efidir"
cp "$target/usr/share/limine/BOOTX64.EFI" "$efidir/"
if [ ! -f "$efidir/limine.conf" ]; then
  cat >"$efidir/limine.conf" <<EOF
timeout: 3

\${VOID_CMDLINE}=root=UUID=$(blkid -o value -s UUID "$root") ro loglevel=4

# BEGIN 60-limine
# END 60-limine
EOF
fi
chroot "$target" "$hook"

# last, so that running it again after an error does not add a second entry
esp=$(findmnt -no SOURCE "$target/boot")
efibootmgr --quiet --create --label "Vast Linux" --loader '\EFI\limine\BOOTX64.EFI' \
  --disk "/dev/$(lsblk -no PKNAME "$esp")" --part "$(cat "/sys/class/block/${esp##*/}/partition")"

echo "vast-limine: done, $esp boots limine with $root as the root filesystem"
