# -f terminal.awk

BEGIN {
  status["fail"] = 0
  status["pass"] = 0
  status["run"] = 0
  status["skip"] = 0
  status["todo"] = 0
  status["total"] = 0
}

/^1\.\./ {
  status["total"] = int(substr($0, 4))
}

/^(ok|not ok)/ {
  if (status["total"] == 0) {
    exit 1
  }

  status["run"]++
  directive = ""
}

/^(ok|not ok)(.*?)(# (SKIP|TODO))/ {
  match($0, /# (SKIP|TODO)/)
  directive = tolower(substr($0, RSTART + 2, 4))
  status[directive]++
}

/^ok / && (directive == "" || directive == "todo") {
  status["pass"]++
}

/^not ok / && directive != "todo" {
  status["fail"]++
}

function status_summary(__, bold, detail, red, reset, run, success, symbol, total) {
  bold = terminal_seq("0;1m")
  red = terminal_seq("31;1m")
  reset = terminal_seq("0m")

  run = status["run"]
  success = status["fail"] == 0
  total = status["total"]

  if (total == 1) {
    s = ""
  } else {
    s = "s"
  }

  if (success) {
    if (run == total) {
      symbol = bold "✓"
    }
  } else {
    symbol = red "✘"
    if (run != total) {
      symbol = " " symbol
    }
  }

  detail = sprintf("(%d passed, %d failed, %d skipped)", status["pass"], status["fail"], status["skip"])

  if (run == total) {
    return sprintf(" %s %s%d test%s%s %s", symbol, bold, total, s, reset, detail)
  } else {
    return sprintf("%s%s %d/%d test%s %s", symbol, reset, run, total, s, detail)
  }
}
