# Vast Linux ISO, see vast/README.md.
set minimum-version := '1.59.0'
set shell := ["bash", "-euo", "pipefail", "-c"]

# privilege escalation prefix, nothing when already root
sudo := ```
  if [ "$(id -u)" -eq 0 ]; then :
  elif command -v sudo >/dev/null 2>&1; then echo sudo
  elif command -v doas >/dev/null 2>&1 && [ -f /etc/doas.conf ]; then echo doas
  else echo "su root -c '\"\$0\" \"\$@\"'"
  fi
```

# upstream void-mklive (the forgejo mirror of https://github.com/void-linux/void-mklive)
upstream := env("UPSTREAM", "https://code.hosaka.cc/github/void-mklive.git")

out := justfile_directory() / "out"

[doc('list recipes (default)')]
@help:
    just --list --unsorted --no-aliases --list-submodules

[doc('show a recipe usage')]
[no-exit-message]
@usage +args:
    just --usage {{ args }}

[arg('outdir', long='outdir', help='Directory for the ISO and its checksum')]
[arg('dotfiles', long='dotfiles', help='chezmoi repository to bake in, uncommitted changes included')]
[arg('fast', long='fast', value='1', help='gzip squashfs instead of xz, quicker to build but a bigger ISO')]
[arg('keep', long='keep', value='1', help='Keep the mklive build directory for manual inspection')]
[arg('dry_run', long='dry-run', value='1', help='Only print the packages, services and mklive.sh arguments, needs no root')]
[arg('flavour', pattern='all|minimal|noctalia|noctalia-nvidia', help='Flavour to build')]
[doc('build an ISO as root')]
iso flavour='noctalia' dotfiles='~/.local/share/chezmoi' outdir=out fast='' keep='' dry_run='':
    {{ if dry_run == '' { sudo } else { '' } }} env \
        DOTFILES={{ quote(join(invocation_directory(), replace_regex(dotfiles, '^~', home_directory()))) }} \
        OUTDIR={{ quote(join(invocation_directory(), outdir)) }} \
        FAST={{ fast }} KEEP={{ keep }} DRY_RUN={{ dry_run }} ./vast/build.sh {{ flavour }}

# boot images and disks in qemu (see `just usage qemu iso`)
mod qemu 'vast/qemu.just'

[doc('remove build outputs and leftover mklive build directories')]
clean:
    rm -rf {{ quote(out) }}
    {{ sudo }} rm -rf --one-file-system mklive-build.*

[doc('fast-forward master to upstream, push it to the fork and merge it into the current branch')]
sync:
    git fetch {{ upstream }} master:master
    git push "$(git config branch.vast.remote)" master
    git merge --no-edit master
