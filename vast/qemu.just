# qemu test VM for the ISOs. The VM's disk and UEFI variables are kept in out/ next to the ISOs.
set shell := ["bash", "-euo", "pipefail", "-c"]

out := justfile_directory() / "out"
ovmf := env("OVMF_DIR", "/usr/share/edk2/x64")

[arg('args', help='Passed to qemu, after `--`')]
[arg('flavour', long='flavour', help='Boot the newest ISO of this flavour instead of the latest one')]
[doc('boot the newest ISO in out/ with an empty disk to install to (default)')]
iso flavour='' *args: (_vm 'iso' flavour args)

[arg('args', help='Passed to qemu')]
[doc('boot the disk installed from the ISO')]
disk *args: (_vm 'disk' '' args)

[doc('delete the disk and UEFI variables')]
reset:
    rm -f {{ quote(out) }}/vm-disk.qcow2 {{ quote(out) }}/vm-ovmf-vars.fd

[private]
@onpath tool:
    echo 'using {{ require(tool) }}' > /dev/null

_vm boot flavour *args: (onpath 'qemu-system-x86_64') (onpath 'qemu-img')
    #!/usr/bin/env bash
    set -euo pipefail

    if [ ! -f {{ quote(ovmf) }}/OVMF_CODE.4m.fd ]; then
      echo "no UEFI firmware in {{ ovmf }}, install edk2-ovmf or set OVMF_DIR" >&2
      exit 1
    fi
    mkdir -p {{ quote(out) }}
    [ -f {{ quote(out) }}/vm-disk.qcow2 ] || qemu-img create -q -f qcow2 {{ quote(out) }}/vm-disk.qcow2 40G
    [ -f {{ quote(out) }}/vm-ovmf-vars.fd ] || cp {{ quote(ovmf) }}/OVMF_VARS.4m.fd {{ quote(out) }}/vm-ovmf-vars.fd

    cdrom=()
    if [ {{ quote(boot) }} = iso ]; then
      flavour={{ quote(flavour) }}
      # out/vast-<flavour>-x86_64-<date>.iso, the flavour is part of the glob
      # shellcheck disable=SC2086
      iso=$(ls -t {{ quote(out) }}/vast-${flavour:-*}-x86_64-*.iso 2>/dev/null | head -n1) || true
      if [ -z "$iso" ]; then
        echo "no ${flavour:-vast} ISO in {{ out }}, run: just iso $flavour" >&2
        exit 1
      fi
      echo "booting $iso"
      cdrom=(-cdrom "$iso" -boot once=d)
    fi

    # `--` separates qemu's arguments from the options of iso, just passes it
    # on for disk which has none
    args=({{ args }})
    [ "${args[0]:-}" != -- ] || args=("${args[@]:1}")

    qemu-system-x86_64 \
      -enable-kvm -machine q35 -cpu host -smp 4 -m 8G \
      -drive if=pflash,format=raw,readonly=on,file={{ quote(ovmf) }}/OVMF_CODE.4m.fd \
      -drive if=pflash,format=raw,file={{ quote(out) }}/vm-ovmf-vars.fd \
      -drive if=virtio,format=qcow2,file={{ quote(out) }}/vm-disk.qcow2 \
      -device virtio-vga-gl -display "${QEMU_DISPLAY:-gtk,gl=on}" \
      -device qemu-xhci -device usb-tablet \
      -nic user,model=virtio-net-pci \
      "${cdrom[@]}" "${args[@]}"
