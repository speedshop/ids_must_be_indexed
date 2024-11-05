#!/usr/bin/env bash

set -euo pipefail

# shellcheck disable=SC2034
if ! declare -g TEST_VAR 2>/dev/null; then
  echo "Error: This script requires Bash version 4.2 or later."
  echo "Your current Bash version is: ${BASH_VERSION}"
  echo "Please upgrade your Bash version to run this script."
  exit 1
fi

DEBUG=${DEBUG:-0}
SCHEMA_FILE="${SCHEMA_FILE:-db/schema.rb}"

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
# New function to initialize global variables
initialize_globals() {
  declare -g -A MIGRATION_COLUMNS
  declare -g -A SCHEMA_COLUMNS
  declare -g -A COLUMN_TYPES
  declare -g -A TABLE_INDEXES
}

# New function to check changed migration files
check_changed_migrations() {
  # Get list of changed migration files
  CHANGED_FILES=$(get_changed_files)

  debug "Changed files: $CHANGED_FILES"

  if [ -z "$CHANGED_FILES" ]; then
    debug "No migration files changed"
    return 1
  fi

  # Parse changed migration files
  for file in $CHANGED_FILES; do
    parse_migration "$file"
  done

  return 0
}

# New function to check all columns in schema
check_all_schema_columns() {
  local schema_file="$1"
  parse_schema "$schema_file"
}

parse_schema() {
  local current_table=""
  local in_create_table=false
  #
  declare -A current_table_columns

  while IFS= read -r line; do
    case "$line" in
      *create_table*)
        current_table=$(echo "$line" | sed -n 's/[[:space:]]*create_table[[:space:]]*"\([^"]*\)".*$/\1/p')
        in_create_table=true
        debug "Processing schema table: $current_table"
        unset current_table_columns
        # shellcheck disable=SC2034
        declare -A current_table_columns
        ;;
      *t.index*)
        if [ "$in_create_table" = true ]; then
          parse_index "$line"
        fi
        ;;
      *add_index*)
        parse_index "$line"
        ;;
      *t.*)
        if [ "$in_create_table" = true ]; then
          parse_column "$line" "$current_table" current_table_columns
        fi
        ;;
      *end*)
        if [ "$in_create_table" = true ]; then
          check_polymorphic_associations "$current_table" current_table_columns
        fi
        in_create_table=false
        ;;
    esac
  done < "$SCHEMA_FILE"
}

parse_column() {
  local line="$1"
  local table="$2"
  local -n table_columns="$3"
  local column type

  if [[ "$line" =~ t\.(bigint|integer|uuid|references|belongs_to|string) ]]; then
    type=${BASH_REMATCH[1]}
    column=$(echo "$line" | sed -n 's/.*t\.[^[:space:]]*[[:space:]]*"\([^"]*\)".*$/\1/p')
    table_columns["$column"]="$type"

    if [ "$type" = "references" ] || [ "$type" = "belongs_to" ]; then
      column="${column}_id"
      type=$(echo "$line" | awk '{print $1}' | cut -d. -f2)
    elif [ "$type" = "string" ] && [[ "$column" == *_id ]]; then
      # Skip string columns ending with _id
      return
    elif [[ "$column" != *_id ]]; then
      return
    fi

    debug "Found potential foreign key in schema - table: $table, column: $column, type: $type"
    SCHEMA_COLUMNS["$table:$column"]="$type"
    COLUMN_TYPES["$table:$column"]="$type"
  fi
}

check_polymorphic_associations() {
  # shellcheck disable=SC2178
  local table="$1"
  # shellcheck disable=SC2178
  local -n table_columns="$2"

  for column in "${!table_columns[@]}"; do
    if [[ "$column" == *_id ]]; then
      local base_name="${column%_id}"
      local type_column="${base_name}_type"

      if [[ -v "table_columns[$type_column]" ]]; then
        debug "Found polymorphic association - table: $table, columns: $column, $type_column"
        COLUMN_TYPES["$table:$column"]="polymorphic"
        COLUMN_TYPES["$table:$type_column"]="polymorphic"
      fi
    fi
  done
}

parse_index() {
  local line="$1"
  local table columns

  if [[ $line =~ add_index ]]; then
    table=$(echo "$line" | sed -n 's/.*add_index[[:space:]]*"\([^"]*\)".*$/\1/p')
  else
    table="$current_table"
  fi

  if echo "$line" | grep -q '\['; then
    columns=$(echo "$line" | sed -n 's/.*\[\([^]]*\)\].*$/\1/p' | tr -d '":')
  else
    columns=$(echo "$line" | sed -n 's/.*[[:space:]]"\([^"]*\)".*$/\1/p')
  fi

  columns=$(echo "$columns" | tr -d ' ' | tr ',' ' ')

  if [ -n "$table" ] && [ -n "$columns" ]; then
    # Store each column separately for faster lookup
    for column in $columns; do
      TABLE_INDEXES["$table:$column"]=1
    done
    debug "Recorded existing index - table: $table, columns: $columns"
  else
    debug "Failed to parse index from line: $line"
  fi
}

# New optimized index_exists function
index_exists() {
  local table="$1"
  local column="$2"

  if [[ -v "TABLE_INDEXES[$table:$column]" ]]; then
    debug "Found existing index for $table:$column"
    return 0
  fi

  # Check for composite indexes
  for index in "${!TABLE_INDEXES[@]}"; do
    IFS=':' read -r index_table index_columns <<< "$index"
    if [[ "$index_table" == "$table" && "$index_columns" == *"$column"* ]]; then
      debug "Found existing composite index for $table:$column"
      return 0
    fi
  done

  debug "No existing index found for $table:$column"
  return 1
}

# New main function for checking indexes
main_check_indexes() {
  initialize_globals

  if should_skip; then
    exit 0
  fi

  if ! check_changed_migrations; then
    exit 0
  fi


  if [ ! -f "$SCHEMA_FILE" ]; then
    echo "Error: schema.rb not found at $SCHEMA_FILE"
    exit 1
  fi

  debug "Reading schema.rb..."

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
      if [[ "${COLUMN_TYPES[$table:$column]}" == "polymorphic" ]]; then
        local base_column="${column%_id}"
        echo "::error file=$file::Missing index for polymorphic association '${base_column}' in table '$table'"
        echo "Details:"
        echo "- Association type: Polymorphic"
        echo "- Columns: ${base_column}_type, ${base_column}_id"
        echo "- Please add a composite index to improve query performance"
        echo "- You can add it using: add_index :$table, [:${base_column}_type, :${base_column}_id]"
      else
        echo "::error file=$file::Missing index for foreign key column '$column' in table '$table'"
        echo "Details:"
        echo "- Column type: $column_type ($type_description)"
        echo "- Column appears to be a foreign key (ends with _id)"
        echo "- Please add an index to improve query performance"
        echo "- You can add it using: add_index :$table, :$column"
      fi
      missing_indexes=true
    fi
  done

  if [ "$missing_indexes" = true ]; then
    echo "Found foreign key columns in schema.rb that need indexes"
    echo "Foreign keys should have indexes to improve JOIN performance"
    echo "Run with DEBUG=1 to see more details about the detected columns"
    exit 1
  fi
}

# Only run main_check_indexes if this script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main_check_indexes
fi
