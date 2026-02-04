#!/bin/sh

set -eu

. "$BRAT_LIB/test.sh"

TEST_DIR="$(cd "$DIR" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"

print_output() {
  if [ -s "$stdout" ]; then
    printf "stdout:\n"
    cat "$stdout"
  fi

  if [ -s "$stderr" ]; then
    printf "stderr:\n"
    cat "$stderr"
  fi
}

assert_status() {
  expected="$1"
  [ "$status" -eq "$expected" ]
}

match_output() {
  pattern="$1"
  if match "$stdout" "$pattern"; then
    return 0
  fi
  match "$stderr" "$pattern"
}

refute_output() {
  pattern="$1"
  if match_output "$pattern"; then
    return 1
  fi
  return 0
}

test_setup() {
  export TEMP_DIR
  TEMP_DIR="$(mktemp -d)"
  export GITHUB_WORKSPACE="$TEMP_DIR"
  cd "$TEMP_DIR"

  git init
  git config --local user.email "test@example.com"
  git config --local user.name "Test User"
  git config --local commit.gpgsign false
  git checkout -b main

  git checkout -b base
  mkdir -p db
  touch db/schema.rb
  git add .
  git commit -m "Initial commit"

  git checkout -b feature

  cp "$PROJECT_ROOT/check_indexes.sh" .
  chmod +x check_indexes.sh
}

test_teardown() {
  rm -rf "$TEMP_DIR"
}

test_prepare() {
  test_setup
  trap test_teardown EXIT
}

create_schema() {
  cat > db/schema.rb << EOF
ActiveRecord::Schema[7.2].define(version: 2024_01_01_000000) do
  $1
end
EOF
}

create_migration() {
  filename="$1"
  content="$2"
  mkdir -p db/migrate
  cat > "db/migrate/$filename" << EOF
$content
EOF
}
