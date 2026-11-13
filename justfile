# Vast Linux ISO, see vast/README.md
set minimum-version := '1.40.0'
set shell := ["bash", "-euo", "pipefail", "-c"]

# privileged commands, nothing to escalate when already root (CI)
sudo := if `id -u` == "0" { "" } else { env("SUDO", "doas") }
# chezmoi repository baked into the image, uncommitted changes included
dotfiles := env("DOTFILES", home_directory() / ".local/share/chezmoi")
# upstream void-mklive (the forgejo mirror of github.com/void-linux/void-mklive)
upstream := env("UPSTREAM", "https://code.hosaka.cc/github/void-mklive.git")

out := justfile_directory() / "out"
ovmf := env("OVMF_DIR", "/usr/share/edk2/x64")

[doc('list recipes (default)')]
@help:
  just --list --unsorted

[doc('build an ISO, extra args are env vars for vast/build.sh, e.g. FAST=1 KEEP=1')]
iso profile="noctalia" *env:
  {{ sudo }} env DOTFILES={{ quote(dotfiles) }} OUT_DIR={{ quote(out) }} {{ env }} ./vast/build.sh {{ profile }}

[doc('quicker test build: gzip squashfs instead of xz')]
iso-fast profile="noctalia" *env: (iso profile "FAST=1" env)

[doc('show packages, services and mklive.sh arguments without building')]
iso-dry-run profile="noctalia":
  env DOTFILES={{ quote(dotfiles) }} OUT_DIR={{ quote(out) }} DRY_RUN=1 ./vast/build.sh {{ profile }}

[doc('boot an ISO (ISO=<path>, default: newest in out/) in qemu with UEFI and an empty disk to install to, extra args go to qemu')]
qemu *args:
  #!/usr/bin/env bash
  set -euo pipefail
  iso=${ISO:-$(ls -t {{ quote(out) }}/*.iso 2>/dev/null | head -n1)}
  [ -f "$iso" ] || { echo "no ISO found, run: just iso" >&2; exit 1; }
  just _vm -cdrom "$iso" -boot once=d {{ args }}

[doc('boot the disk installed by `just qemu`, extra args go to qemu')]
qemu-disk *args:
  just _vm {{ args }}

[doc('delete the qemu disk and UEFI variables')]
qemu-reset:
  rm -f {{ quote(out) }}/vm-disk.qcow2 {{ quote(out) }}/vm-ovmf-vars.fd

[private]
@onpath tool:
  echo 'using {{ require(tool) }}' > /dev/null

[private]
_vm *args: (onpath 'qemu-system-x86_64') (onpath 'qemu-img')
  @[ -f {{ ovmf }}/OVMF_CODE.4m.fd ] || { echo "no UEFI firmware in {{ ovmf }}, install edk2-ovmf or set OVMF_DIR" >&2; exit 1; }
  mkdir -p {{ quote(out) }}
  [ -f {{ quote(out) }}/vm-disk.qcow2 ] || qemu-img create -q -f qcow2 {{ quote(out) }}/vm-disk.qcow2 40G
  [ -f {{ quote(out) }}/vm-ovmf-vars.fd ] || cp {{ ovmf }}/OVMF_VARS.4m.fd {{ quote(out) }}/vm-ovmf-vars.fd
  qemu-system-x86_64 \
    -enable-kvm -machine q35 -cpu host -smp 4 -m 8G \
    -drive if=pflash,format=raw,readonly=on,file={{ ovmf }}/OVMF_CODE.4m.fd \
    -drive if=pflash,format=raw,file={{ quote(out) }}/vm-ovmf-vars.fd \
    -drive if=virtio,format=qcow2,file={{ quote(out) }}/vm-disk.qcow2 \
    -device virtio-vga-gl -display ${QEMU_DISPLAY:-gtk,gl=on} \
    -device qemu-xhci -device usb-tablet \
    -nic user,model=virtio-net-pci \
    {{ args }}

[doc('fast-forward master to upstream, push it to the fork and merge it into the current branch')]
sync-upstream:
  git fetch {{ upstream }} master:master
  git push "$(git config branch.vast.remote)" master
  git merge --no-edit master

[doc('remove build outputs and leftover mklive build directories')]
clean:
  rm -rf {{ quote(out) }}
  {{ sudo }} rm -rf --one-file-system mklive-build.*
