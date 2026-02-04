${BRAT_DEBUG:+set -x}

USAGE="$USAGE | <FILE> [<FILE> ...]"
VERSION="0.1.0"

TMPDIR="${TMPDIR:-/tmp}"
TMPDIR="${TMPDIR%/}"
export TMPDIR

export BRAT_LIB="$ROOT/lib/$NAME"

if [ -z "${BRAT_RUN+set}" ]; then
  export BRAT_RUN="$$"
  export BRAT_TMP="$TMPDIR/$NAME.$BRAT_RUN"

  trap 'rm -fr "$BRAT_TMP"* 2>/dev/null' EXIT
  "$SELF" "$@"
  exit
fi
