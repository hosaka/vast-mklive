# Vast Linux

A live and installable Void Linux ISO that reproduces my desktop: packages, runit services, system files and dotfiles, ready to use after installation without running chezmoi.

This branch (`vast`) only adds files on top of upstream [void-mklive](https://github.com/void-linux/void-mklive), nothing upstream is modified, so merging upstream never conflicts. `master` is kept identical to upstream.

## Where things live

Everything about *what* is on the system lives in the [dotfiles](https://code.hosaka.cc/hosaka/.dotfiles) (chezmoi), this repository only knows *how* to turn that into an ISO.

| What | Where |
| --- | --- |
| Flavour configuration | here: `vast/flavours/<flavour>.env` |
| User dotfiles | dotfiles: `dotfiles/` |
| Packages and services | dotfiles: `dotfiles/.chezmoidata/packages.toml` |
| System files (`/etc`) | dotfiles: `system/`, a separate chezmoi source applied to `/` |
| XBPS repos | dotfiles: `system/etc/xbps.d/` |

## How it works

`just iso` runs [build.sh](build.sh) as root, which:

1. snapshots the chezmoi repository (`--dotfiles`, `~/.local/share/chezmoi` by default)
2. seeds a chezmoi config with the flavour's `CHEZMOI_FLAGS` and reads `chezmoi data`
3. reads the repositories and `ignorepkg` entries from `system/etc/xbps.d/`
4. runs `mklive.sh` with specified repos, the kernel, `void-installer`, makes the kernel cmdline and [postsetup.sh](postsetup.sh) as the `-x` hook

`postsetup.sh` runs inside the new rootfs before it is compressed:

1. applies dotfiles `system/` to `/` with chezmoi as root
2. runs a few modifications to the installed system
3. runs `chezmoi init` and `chezmoi apply --exclude scripts` as the user would on a fresh machine
4. moves the resulting user `$HOME`, including the chezmoi source and state, to `/etc/skel`

`/etc/skel` is what both the live user and the user created by `void-installer` are made from.

## Flavours and profiles

A **profile** is a chezmoi flag (e.g. `desktop`, `development`), each profile has a package group with its services in `packages.toml` and some dotfiles that are only applied when it is on. A **flavour** is an ISO with the profiles baked into it. Flavours only bake in what the live system needs to run on the hardware, profiles can turned on after installing (see [Installing](#installing)).

| Flavour | ISO | Profiles | GPUs |
| --- | --- | --- | --- |
| `minimal` | `vast-minimal-x86_64-<date>.iso` | none, console only | any, no graphics stack |
| `noctalia` | `vast-noctalia-x86_64-<date>.iso` | `desktop` | anything with open drivers: AMD, Intel, kernel drivers and Mesa |
| `noctalia-nvidia` | `vast-noctalia-nvidia-x86_64-<date>.iso` | `desktop`, `nvidia` | NVIDIA Turing and newer, adds the proprietary driver |

- `minimal` boots to a console login, `void-installer` works there the same way.
- Vulkan drivers and hardware video decoding (`mesa-vulkan-radeon`, `mesa-vulkan-intel`, `mesa-vaapi`, `intel-media-driver`) are not included, install what your hardware needs.

## Building

```bash
just                # list recipes
just usage iso      # arguments and options of a recipe
just iso --dry-run  # packages, services and the mklive.sh command line, no root needed
just iso            # build out/vast-noctalia-x86_64-<date>.iso (runs as root)
just iso noctalia-nvidia   # build a different flavour
just iso all        # every flavour in vast/flavours/, one after the other
just iso --fast     # gzip squashfs, quicker for testing
just iso --keep     # keep the mklive build directory for inspection
just iso --dotfiles ~/Code/dotfiles   # bake in another chezmoi repository, uncommitted changes included
just iso --outdir /tmp/isos           # write the ISO somewhere else than out/
just clean          # remove out/ and leftover build directories
```

The options can be combined and go anywhere after `iso`, e.g. `just iso all --fast`.

Packages are cached in `xbps-cachedir-x86_64/` between builds.

## Testing in qemu

Needs `qemu` and `edk2-ovmf` packages on Void.

```bash
just qemu           # boot the newest ISO in out/ with UEFI and an empty 40G disk
just usage qemu iso # arguments and options of a qemu recipe
just qemu iso --flavour noctalia-nvidia   # the newest ISO of a flavour (after `just iso all` the newest is the last flavour)
just qemu disk      # boot the installed disk
just qemu reset     # throw away the disk and UEFI variables
```

The recipes are in [qemu.just](qemu.just), the `qemu` module of the justfile. The live user is `vast`, password `voidlinux`.

Extra arguments go to qemu:

```bash
just qemu iso -- -device usb-host,hostbus=1,hostport=3
just qemu disk -device usb-host,hostbus=1,hostport=3
```

To capture the keyboard in a QEMU window use `Ctrl+Alt+G`, press again to restore it.

## Installing

Run `void-installer` from the live system as root: `doas void-installer`:

- **Source**: `Local`. Copies from the live system, (with all packages, services, `/etc`) instead of downloading a bare `base-system` with `Network`.
- **User account**: Any username. The groups in the flavour's `USERGROUPS` are already ticked, on top of the installer's defaults.
- **BootLoader**: `Manage bootloader otherwise` for limine (`BOOTLOADER=limine`, the default), or the disk for GRUB.
- **Filesystems**: ext4 or btrfs (note that the installer's btrfs has no subvolumes, so there is no snapper setup yet). The EFI system partition (FAT32) is mounted at `/boot` for limine, which only reads FAT, so the kernel has to live there. Allocate 1G or more for the EFI partition, it holds every kernel and initramfs until `vkpurge` removes the old ones.
- **Services**: Everything the flavour enables is already ticked.
- **Mirror**: Leave this as is.

For limine, don't reboot when the installer is done. Install it with the root partition you picked in the installer:

```bash
doas vast-limine /dev/sda2
```

[limine.sh](limine.sh) copies limine to `EFI/limine/` on the ESP, writes `limine.conf` with the kernel command line and adds a `Vast Linux` UEFI boot entry. The `60-limine` kernel hook from the dotfiles manages available boot entries after every kernel update. Only UEFI is supported.

After the first boot, you can turn on the individual profiles. This installs profile packages, runs `chezmoi apply` for user and system config, and links the necessary services:

```bash
just profile on development
just profile status            # list profiles on/off status
just profile off development   # unlink its services, remove the packages nothing else needs
```

## CI

[build-iso.yml](../.forgejo/workflows/build-iso.yml) builds on pushes to `vast` that touch `vast/`, `justfile` or the workflow, and on manual dispatch. Pushes build `all` flavours, a dispatch picks one or `all` (the choices are listed in the workflow, add new flavours there). Each ISO and its checksum are uploaded to the generic package registry, one package version per flavour, replacing the previous build:

```
https://code.hosaka.cc/api/packages/hosaka/generic/vast-iso/<flavour>/vast-<flavour>-x86_64-<date>.iso
```

Requirements:

- repository secret `ISO_UPLOAD_TOKEN`: a token with `write:package` scope
- the runner must allow privileged containers and mounting `/dev` (`container.privileged` and `container.valid_volumes` in the runner config), mklive needs loop devices
- set `vast` as the default branch, so the workflow shows up for manual dispatch

## Syncing with upstream

```bash
just sync-upstream   # fast-forward master from the mirror, push it, merge into this branch
```

Upstream changes (`mklive.sh`, `installer.sh`, etc.) are outside the CI path filter, so a sync does not trigger a build. Dispatch one by hand when upstream changed something that matters for the ISO.
