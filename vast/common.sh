# shellcheck shell=bash
#
# Output helpers shared by the vast/ scripts, only sourced.
#
#   # shellcheck source=common.sh
#   . "$(dirname "$(readlink -f "$0")")/common.sh"
#
# Messages are prefixed with the name of the script that sources this file
# (build, postsetup, publish).

# plain text when the terminal is not known, e.g. in CI
BOLD=$(tput bold 2>/dev/null || :)
RED=$(tput setaf 1 2>/dev/null || :)
GREEN=$(tput setaf 2 2>/dev/null || :)
YELLOW=$(tput setaf 3 2>/dev/null || :)
BLUE=$(tput setaf 4 2>/dev/null || :)
NO_COLOR=$(tput sgr0 2>/dev/null || :)

PROG=$(basename "$0" .sh)

info() {
  printf '%s\n' "${BOLD}${BLUE}>${NO_COLOR} $PROG: $*"
}

success() {
  printf '%s\n' "${BOLD}${GREEN}>${NO_COLOR} $PROG: $*"
}

warning() {
  printf '%s\n' "${YELLOW}! $PROG: $*${NO_COLOR}"
}

die() {
  printf '%s\n' "${RED}x $PROG: $*${NO_COLOR}" >&2
  exit 1
}
