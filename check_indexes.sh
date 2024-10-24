#!/usr/bin/env bash

set -euo pipefail

DEBUG=${DEBUG:-0}

debug() {
  if [ "${DEBUG}" = "1" ]; then
    echo "DEBUG: $*" >&2
  fi
}

is_foreign_key_column() {
  local column="$1"
  [[ "$column" == *_id ]]
}

extract_table_name() {
  sed -n 's/create_table[[:space:]]*:\([a-zA-Z0-9_]*\).*$/\1/p'
}

extract_column_info() {
  local line="$1"
  local type
  local column

  type=$(echo "$line" | awk '{print $1}' | cut -d. -f2)
  column=$(echo "$line" | awk '{print $2}' | tr -d '":,')

  if [ "$type" = "references" ] || [ "$type" = "belongs_to" ]; then
    column="${column}_id"
  fi
  echo "$column $type"
}

# Function to check if check should be skipped
should_skip() {
  # Check for skip in last commit message
  if git log -1 --pretty=%B | grep -q "\[skip-index-check\]"; then
    echo "Skipping index check: [skip-index-check] found in commit message"
    return 0
  fi

  # Check for skip in any commit message in the PR
  if [ -n "${GITHUB_BASE_REF:-}" ]; then
    if git log "origin/$GITHUB_BASE_REF..HEAD" --pretty=%B | grep -q "\[skip-index-check\]"; then
      echo "Skipping index check: [skip-index-check] found in PR commits"
      return 0
    fi
  fi

  # Check for SKIP_INDEX_CHECK environment variable
  if [ "${SKIP_INDEX_CHECK:-0}" = "1" ]; then
    echo "Skipping index check: SKIP_INDEX_CHECK environment variable is set"
    return 0
  fi

  return 1
}

# Function to check if an index exists in schema.rb
index_exists() {
  local table="$1"
  local column="$2"

  debug "Checking if index exists for $table:$column"
  for key in "${!EXISTING_INDEXES[@]}"; do
    if echo "$key" | grep -q "$table:.*$column"; then
      debug "Found existing index in schema: $key"
      return 0
    fi
  done
  debug "No existing index found in schema"
  return 1
}

# Function to get column type description
get_column_type_description() {
  local type="$1"
  case "$type" in
    "bigint")
      echo "64-bit integer typically used for foreign keys"
      ;;
    "integer")
      echo "32-bit integer commonly used for foreign keys"
      ;;
    "references")
      echo "Rails reference/belongs_to association"
      ;;
    "uuid")
      echo "Universally Unique Identifier"
      ;;
    *)
      echo "$type"
      ;;
  esac
}

# Function to get changed files
get_changed_files() {
  # If we're in GitHub Actions
  if [ -n "${GITHUB_BASE_REF:-}" ]; then
    git diff --name-only "origin/$GITHUB_BASE_REF" HEAD | grep "db/migrate/.*\.rb$" || true
  else
    # For local testing, diff against parent branch
    git status --porcelain -u | grep "db/migrate/.*\.rb$" || true
  fi
}

parse_migration() {
  local file="$1"
  debug "Parsing migration file: $file"

  local current_table=""
  local in_create_table=false

  while IFS= read -r line; do
    line=$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    if echo "$line" | grep -q "create_table"; then
      current_table=$(echo "$line" | extract_table_name)
      in_create_table=true
      debug "Found create_table for $current_table"
    elif [ "$in_create_table" = true ] && echo "$line" | grep -qE "^t\.(bigint|integer|references|belongs_to|uuid)"; then
      read -r column type <<< "$(extract_column_info "$line")"
      if is_foreign_key_column "$column"; then
        debug "Found column in create_table - table: $current_table, column: $column, type: $type"
        MIGRATION_COLUMNS["$current_table:$column"]="$type"
      fi
    elif [ "$in_create_table" = true ] && echo "$line" | grep -q "end"; then
      in_create_table=false
      current_table=""
    elif echo "$line" | grep -qE "add_column|change_column"; then
      local table column type
      read -r _ table column type <<< "$(echo "$line" | awk '{print $1, $2, $3, $4}' | tr -d ':,"')"
      if is_foreign_key_column "$column"; then
        debug "Found column change - table: $table, column: $column, type: $type"
        MIGRATION_COLUMNS["$table:$column"]="$type"
      fi
    fi
  done < "$file"
}
if should_skip; then
  exit 0
fi

# Get list of changed migration files
CHANGED_FILES=$(get_changed_files)

debug "Changed files: $CHANGED_FILES"

if [ -z "$CHANGED_FILES" ]; then
  debug "No migration files changed"
  exit 0
fi

# Parse changed migration files
declare -A MIGRATION_COLUMNS
for file in $CHANGED_FILES; do
  parse_migration "$file"
done

# Read current schema.rb to build table structure
SCHEMA_FILE="db/schema.rb"
declare -A EXISTING_INDEXES
declare -A SCHEMA_COLUMNS
declare -A COLUMN_TYPES

if [ ! -f "$SCHEMA_FILE" ]; then
  echo "Error: schema.rb not found at $SCHEMA_FILE"
  exit 1
fi

debug "Reading schema.rb..."

parse_schema() {
  local current_table=""
  local in_create_table=false

  while IFS= read -r line; do
    case "$line" in
      *create_table*)
        current_table=$(echo "$line" | sed -n 's/[[:space:]]*create_table[[:space:]]*"\([^"]*\)".*$/\1/p')
        in_create_table=true
        debug "Processing schema table: $current_table"
        ;;
      *t.bigint*\"*_id\"*|*t.integer*\"*_id\"*|*t.uuid*\"*_id\"*|*t.references*|*t.belongs_to*)
        if [ "$in_create_table" = true ]; then
          parse_column "$line" "$current_table"
        fi
        ;;
      *add_index*)
        parse_index "$line"
        ;;
      *end*)
        in_create_table=false
        ;;
    esac
  done < "$SCHEMA_FILE"
}

parse_column() {
  local line="$1"
  local table="$2"
  local column type

  if [[ "$line" =~ t\.(bigint|integer|uuid) ]]; then
    column=$(echo "$line" | sed -n 's/.*"\([^"]*\)".*$/\1/p')
    type=${BASH_REMATCH[1]}
  else
    column=$(echo "$line" | sed -n 's/.*"\([^"]*\)".*$/\1_id/p')
    type="references"
  fi

  debug "Found potential foreign key in schema - table: $table, column: $column, type: $type"
  SCHEMA_COLUMNS["$table:$column"]=1
  COLUMN_TYPES["$table:$column"]="$type"
}

parse_index() {
  local line="$1"
  local table columns

  table=$(echo "$line" | sed -n 's/.*add_index[[:space:]]*"\([^"]*\)".*$/\1/p')
  if [[ "$line" =~ \[|\, ]]; then
    columns=$(echo "$line" | sed -n 's/.*\[\([^]]*\)\].*$/\1/p')
  else
    columns=$(echo "$line" | sed -n 's/.*"[^"]*",[[:space:]]*"\([^"]*\)".*$/\1/p')
  fi

  if [ -n "$table" ] && [ -n "$columns" ]; then
    EXISTING_INDEXES["$table:$columns"]=1
    debug "Recorded existing index - table: $table, columns: $columns"
  fi
}

parse_schema

debug "Schema columns that need indexes:"
for key in "${!SCHEMA_COLUMNS[@]}"; do
  debug "  $key (type: ${COLUMN_TYPES[$key]})"
done

# Check only the columns changed in migrations
missing_indexes=false
for key in "${!MIGRATION_COLUMNS[@]}"; do
  IFS=':' read -r table column <<< "$key"
  column_type=${MIGRATION_COLUMNS[$key]}
  type_description=$(get_column_type_description "$column_type")

  debug "Checking index requirement from migration - table: $table, column: $column, type: $column_type"
  if ! index_exists "$table" "$column"; then
    echo "::error file=$file::Missing index for foreign key column '$column' in table '$table'"
    echo "Details:"
    echo "- Column type: $column_type ($type_description)"
    echo "- Column appears to be a foreign key (ends with _id)"
    echo "- Please add an index to improve query performance"
    echo "- You can add it using: add_index :$table, :$column"
    missing_indexes=true
  fi
done

if [ "$missing_indexes" = true ]; then
  echo "Found foreign key columns in schema.rb that need indexes"
  echo "Foreign keys should have indexes to improve JOIN performance"
  echo "Run with DEBUG=1 to see more details about the detected columns"
  exit 1
fi
