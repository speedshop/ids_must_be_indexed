#!/usr/bin/env bash

debug() {
  if [ "${DEBUG}" = "1" ]; then
    echo "$@"
  fi
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
    *)
      echo "$type"
      ;;
  esac
}

# Function to get changed files
get_changed_files() {
  # If we're in GitHub Actions
  if [ -n "${GITHUB_BASE_REF:-}" ]; then
    debug "Running in GitHub Actions, using GITHUB_BASE_REF"
    git diff --name-only "origin/$GITHUB_BASE_REF" HEAD | grep "db/migrate/.*\.rb$" || true
  else
    # For local testing, diff against parent branch
    debug "Running locally, using git diff against parent branch"
    git diff --name-only HEAD^..HEAD | grep "db/migrate/.*\.rb$" || true
  fi
}

# Check if we should skip
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

# Variables to track current table being processed in schema
current_schema_table=""
in_create_table=false

while IFS= read -r line; do
  # Start of create_table block
  if echo "$line" | grep -q "create_table"; then
    current_schema_table=$(echo "$line" | sed -n 's/[[:space:]]*create_table[[:space:]]*"\([^"]*\)".*$/\1/p')
    in_create_table=true
    debug "Processing schema table: $current_schema_table"
    continue
  fi

  # End of create_table block
  if [ "$in_create_table" = true ] && echo "$line" | grep -q "^[[:space:]]*end"; then
    current_schema_table=""
    in_create_table=false
    continue
  fi

  # Process columns inside create_table
  if [ "$in_create_table" = true ]; then
    # Match any of these patterns:
    # t.bigint "column_id"
    # t.integer "column_id"
    # t.references "column"
    if echo "$line" | grep -q "t\.\(bigint\|integer\).*\".*_id\"" || \
        echo "$line" | grep -q "t\.references.*\".*\"" || \
        echo "$line" | grep -q "t\.belongs_to.*\".*\""; then

      # Extract column name and type
      if echo "$line" | grep -q "t\.\(bigint\|integer\)"; then
        column=$(echo "$line" | sed -n 's/.*"\([^"]*\)".*$/\1/p')
        type=$(echo "$line" | sed -n 's/.*t\.\([^[:space:]]*\).*$/\1/p')
      else
        # For references/belongs_to, append _id
        column=$(echo "$line" | sed -n 's/.*"\([^"]*\)".*$/\1_id/p')
        type="references"
      fi

      debug "Found potential foreign key in schema - table: $current_schema_table, column: $column, type: $type"
      SCHEMA_COLUMNS["$current_schema_table:$column"]=1
      COLUMN_TYPES["$current_schema_table:$column"]="$type"
    fi
  fi

  # Process indexes
  if echo "$line" | grep -q "add_index"; then
    debug "Found index in schema: $line"
    table=$(echo "$line" | sed -n 's/.*add_index[[:space:]]*"\([^"]*\)".*$/\1/p')
    if echo "$line" | grep -q "\[\|,"; then
      columns=$(echo "$line" | sed -n 's/.*\[\([^]]*\)\].*$/\1/p')
    else
      columns=$(echo "$line" | sed -n 's/.*"[^"]*",[[:space:]]*"\([^"]*\)".*$/\1/p')
    fi
    if [ -n "$table" ] && [ -n "$columns" ]; then
      EXISTING_INDEXES["$table:$columns"]=1
      debug "Recorded existing index - table: $table, columns: $columns"
    fi
  fi
done < "$SCHEMA_FILE"

debug "Schema columns that need indexes:"
for key in "${!SCHEMA_COLUMNS[@]}"; do
  debug "  $key (type: ${COLUMN_TYPES[$key]})"
done

# Check all required indexes exist
missing_indexes=false
for key in "${!SCHEMA_COLUMNS[@]}"; do
  table=${key%:*}
  column=${key#*:}
  column_type=${COLUMN_TYPES[$key]}
  type_description=$(get_column_type_description "$column_type")

  debug "Checking index requirement from schema - table: $table, column: $column, type: $column_type"
  if ! index_exists "$table" "$column"; then
    echo "::error file=$SCHEMA_FILE::Missing index for foreign key column '$column' in table '$table'"
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
