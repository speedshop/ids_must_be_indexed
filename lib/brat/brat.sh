set -eu
${BRAT_DEBUG:+set -x}
TAB="$(printf '\t')"

alias brat='"$SELF"'
alias error='brat --- error'
alias usage='brat --- usage "$0" "${USAGE:-}"'

brat_cache_fetch() {
  _brat_cache_fetch_path="$(IFS=" "; brat_cache_path "$*")"
  if ! [ -r "$_brat_cache_fetch_path" ]; then
    brat-"$@" >"$_brat_cache_fetch_path.$$"
    mv "$_brat_cache_fetch_path.$$" "$_brat_cache_fetch_path"
  fi
  printf "%s\n" "$_brat_cache_fetch_path"
}

brat_cache_path() {
  _brat_cache_path_result="$(printf "%s" "$1" | cksum)"
  printf "%s\n" "$BRAT_TMP.cache.${_brat_cache_path_result% *}"
}

brat_preprocess() {
  brat_cache_fetch test--preprocess "$1"
}
