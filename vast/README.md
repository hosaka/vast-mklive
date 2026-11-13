# Vast Linux

A live and installable Void Linux ISO that reproduces my desktop: packages, runit services, system files and dotfiles, ready to use after installation without running chezmoi.

This branch (`vast`) only adds files on top of upstream [void-mklive](https://github.com/void-linux/void-mklive), nothing upstream is modified, so merging upstream never conflicts. `master` is kept identical to upstream.

## Where things live

Everything about *what* is on the system lives in the [dotfiles](https://code.hosaka.cc/hosaka/.dotfiles) (chezmoi), this repository only knows *how* to turn that into an ISO.

| What | Where |
| --- | --- |
| Packages and services | dotfiles: `dotfiles/.chezmoidata/packages.toml` |
| System files (`/etc`) | dotfiles: `system/`, a separate chezmoi source applied to `/` |
| XBPS repos and ignored packages | dotfiles: `system/etc/xbps.d/` |
| User dotfiles | dotfiles: `dotfiles/` |
| Flags, kernel, live user | here: `vast/profiles/<profile>.env` |
| vast-packages signing key | here: `keys/d4:fe:01:8b:18:0e:5c:ea:25:00:50:a5:b5:77:78:2c.plist` |

## How it works

`just iso` runs [build.sh](build.sh) as root, which:

1. snapshots the chezmoi repository (`DOTFILES` from env or `~/.local/share/chezmoi` by default)
2. seeds a chezmoi config with the profile's `CHEZMOI_FLAGS` and reads `chezmoi data`
3. reads the repositories and `ignorepkg` entries from `system/etc/xbps.d/`
4. runs `mklive.sh` with specified repos, the kernel, `void-installer`, makes the kernel cmdline and [postsetup.sh](postsetup.sh) as the `-x` hook

`postsetup.sh` runs inside the new rootfs before it is compressed:

1. applies `system/` to `/` with chezmoi as root
2. runs a few modifications to the installed system
3. runs `chezmoi init` and `chezmoi apply --exclude scripts` as the user would on a fresh machine
4. moves the resulting user `$HOME`, including the chezmoi source and state, to `/etc/skel`

`/etc/skel` is what both the live user and the user created by `void-installer` are made from.

## Building

```bash
just                # list recipes
just iso-dry-run    # packages, services and the mklive.sh command line, no root needed
just iso            # build out/vast-noctalia-x86_64-<date>.iso (runs as root)
just iso-fast       # gzip squashfs, quicker for testing
just iso noctalia KEEP=1   # keep the mklive build directory for inspection
just clean          # remove out/ and leftover build directories
```

Packages are cached in `xbps-cachedir-x86_64/` between builds.

## Testing in qemu

Needs `qemu` and `edk2-ovmf` packages on Void.

```bash
just qemu           # boot the newest ISO with UEFI and an empty 40G disk
ISO=out/<file>.iso just qemu   # boot a specific ISO
just qemu-disk      # boot the installed disk
just qemu-reset     # throw away the disk and UEFI variables
```

The live user is `alex`, password `voidlinux`.

Extra arguments go to qemu can be passed with:

```bash
just qemu-disk -device usb-host,hostbus=1,hostport=3
```

To capture the keyboard in a QEMU window use `Ctrl+Alt+G`, press again to restore it.

## Installing

Run `void-installer` from the live system as root: `doas void-installer`:

- **Source**: `Local`. It copies the live system, with all packages, services, `/etc` and keys. `Network` would install a bare `base-system` instead.
- **User account**: login `alex`. The installer's default groups lack some that I use, also tick `input`, `plugdev`, `socklog`, `storage` and `bluetooth`.
- **Filesystems**: ext4 or btrfs (note that the installer's btrfs has no subvolumes, so there is no snapper setup yet).
- **Services**: everything from `packages.toml` is already ticked.
- **Mirror**: leave this as is.

After the first boot, only the things that need secrets or hardware keys are left:

```bash
chezmoi apply   # reads the secrets and runs the run_once/run_onchange scripts
```

## CI

[build-iso.yml](../.forgejo/workflows/build-iso.yml) builds on pushes to `vast` that touch `vast/`, `justfile` or the workflow, and on manual dispatch. The ISO and its checksum are uploaded to the generic package registry, replacing the previous build:

```
https://code.hosaka.cc/api/packages/hosaka/generic/vast-iso/<profile>/vast-<profile>-x86_64-<date>.iso
```

Requirements:

- repository secret `ISO_UPLOAD_TOKEN`: a token with `write:package` scope
- the runner must allow privileged containers and mounting `/dev` (`container.privileged` and `container.valid_volumes` in the runner config), mklive needs loop devices
- set `vast` as the default branch, so the workflow shows up for manual dispatch

## Syncing with upstream

```bash
just sync-upstream   # fast-forward master from the mirror, push it, merge into this branch
```

Upstream changes (`mklive.sh`, `installer.sh`, ...) are outside the CI path filter, so a sync does not trigger a build. Dispatch one by hand when upstream changed something that matters for the ISO.
