#!/bin/bash

# Enable error handling
set -euo pipefail

debug() {
  if [ "${DEBUG:-0}" = "1" ]; then
    echo "DEBUG: $@"
  fi
}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Read schema.rb
SCHEMA_FILE="db/schema.rb"

if [ ! -f "$SCHEMA_FILE" ]; then
  echo "Error: schema.rb not found at $SCHEMA_FILE"
  exit 1
fi

echo -e "${YELLOW}Analyzing schema.rb for missing indexes...${NC}"
echo

# Create temporary files to store our data
TEMP_DIR=$(mktemp -d)
COLUMNS_FILE="$TEMP_DIR/columns.txt"
INDEXES_FILE="$TEMP_DIR/indexes.txt"
touch "$COLUMNS_FILE" "$INDEXES_FILE"

# Cleanup function
cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Variables to track current table being processed in schema
current_schema_table=""
in_create_table=false

# First pass: collect all tables and their columns
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
    # Match t.bigint "column_id" or t.integer "column_id" or t.uuid "column_id"
    if echo "$line" | grep -q "t\.\(bigint\|integer\|uuid\).*\".*_id\""; then
      column=$(echo "$line" | sed -n 's/.*"\([^"]*\)".*$/\1/p')
      type=$(echo "$line" | sed -n 's/.*t\.\([^[:space:]]*\).*$/\1/p')
      echo "$current_schema_table:$column:$type" >> "$COLUMNS_FILE"
      debug "Found potential foreign key - table: $current_schema_table, column: $column, type: $type"
    fi
  fi

  # Process indexes
  if echo "$line" | grep -q "t\.index\|add_index"; then
    debug "Found index in schema: $line"
    table=$current_schema_table

    # Handle both t.index and add_index formats
    if echo "$line" | grep -q "t\.index"; then
      # Format: t.index ["column_name"], name: "index_name"
      columns=$(echo "$line" | sed -n 's/.*t\.index[[:space:]]*\[\([^]]*\)\].*$/\1/p' | tr -d '"' | tr -d ' ')
    else
      # Format: add_index "table_name", ["column_name"], name: "index_name"
      table=$(echo "$line" | sed -n 's/.*add_index[[:space:]]*"\([^"]*\)".*$/\1/p')
      columns=$(echo "$line" | sed -n 's/.*,[[:space:]]*\[\([^]]*\)\].*$/\1/p' | tr -d '"' | tr -d ' ')
    fi

    if [ ! -z "$table" ] && [ ! -z "$columns" ]; then
      debug "Recorded index - table: $table, columns: $columns"
      echo "$table:$columns" >> "$INDEXES_FILE"
    fi
  fi
done < "$SCHEMA_FILE"

# Function to check if an index exists
index_exists() {
  local table="$1"
  local column="$2"

  debug "Checking if index exists for $table:$column"
  while IFS= read -r index_line; do
    # Split the index line into table and columns
    local idx_table=${index_line%%:*}
    local idx_columns=${index_line#*:}

    # Check if table matches and column is in the index columns
    if [ "$idx_table" = "$table" ]; then
      debug "Found index for table $table: $idx_columns"
      if echo "$idx_columns" | grep -q "\b$column\b"; then
        debug "Column $column is covered by index"
        return 0
      fi
    fi
  done < "$INDEXES_FILE"

  debug "No existing index found"
  return 1
}

# Check all columns and generate report
missing_indexes=false
indexed_count=0
missing_count=0
total_count=0

echo "Schema Analysis Report"
echo "====================="
echo

echo "Missing Indexes:"
echo "---------------"

while IFS=: read -r table column type; do
  total_count=$((total_count + 1))

  if ! index_exists "$table" "$column"; then
    missing_count=$((missing_count + 1))
    echo -e "${RED}✗ Table '$table' has no index on '$column' (type: $type)${NC}"
    echo "  - Add with: add_index :$table, :$column"
    missing_indexes=true
  else
    indexed_count=$((indexed_count + 1))
  fi
done < "$COLUMNS_FILE"

# If no missing indexes, show a success message
if [ "$missing_indexes" = false ]; then
  echo -e "${GREEN}✓ All foreign key columns are properly indexed!${NC}"
fi

echo
echo "Summary:"
echo "--------"
echo "Total foreign key columns found: $total_count"
echo -e "Properly indexed: ${GREEN}$indexed_count${NC}"
echo -e "Missing indexes: ${RED}$missing_count${NC}"
echo

# Add Rails migration command if there are missing indexes
if [ "$missing_indexes" = true ]; then
  echo "To generate a migration for all missing indexes:"
  echo "-----------------------------------------"
  echo "rails generate migration AddMissingIndexes"
  echo
  echo "# In the migration file, add:"
  while IFS=: read -r table column type; do
    if ! index_exists "$table" "$column"; then
      echo "add_index :$table, :$column"
    fi
  done < "$COLUMNS_FILE"
fi

# Exit with status 1 if missing indexes were found
[ "$missing_indexes" = false ]
