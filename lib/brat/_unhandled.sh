if [ "$1" = "" ]; then
  [ $# -gt 1 ] || usage
  shift

  if for arg; do [ -r "$arg" ]; done; then
    exec brat-plan-run "$@"
  fi
fi
