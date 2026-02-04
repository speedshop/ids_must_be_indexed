set -eu

brat_eval_fn() {
  _brat_eval_fn="brat_fn_$1"
  if PATH= command -v "$_brat_eval_fn" >/dev/null 2>&1; then
    "$_brat_eval_fn"
  else
    error "$FILE:$1: not a test definition line"
  fi
}

brat_eval_var() {
  eval '[ -n "${'"brat_$1"'+set}" ] && printf "%s" "${'"brat_$1"'#?}"'
}

DIR="${FILE%/*}"

. "$(brat_preprocess "$FILE")"
