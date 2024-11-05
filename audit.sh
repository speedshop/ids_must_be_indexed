#!/usr/bin/env bash

# Enable error handling
set -euo pipefail

# Source the check_indexes.sh file
# shellcheck disable=SC1091
source ./check_indexes.sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Read schema.rb
SCHEMA_FILE="${SCHEMA_FILE:-db/schema.rb}"

if [ ! -f "$SCHEMA_FILE" ]; then
  echo "Error: schema.rb not found at $SCHEMA_FILE"
  exit 1
fi

echo -e "${YELLOW}Analyzing schema.rb for missing indexes...${NC}"
echo

# Initialize global variables
initialize_globals

# Parse the schema
parse_schema

# Check all columns and generate report
missing_indexes=false
indexed_count=0
missing_count=0
total_count=0
declare -A missing_index_reports
declare -A missing_index_commands

# Sort the keys of SCHEMA_COLUMNS
mapfile -t sorted_keys < <(printf '%s\n' "${!SCHEMA_COLUMNS[@]}" | sort)

echo "Schema Analysis Report"
echo "====================="
echo

echo "Missing Indexes:"
echo "---------------"

for key in "${sorted_keys[@]}"; do
  IFS=':' read -r table column <<< "$key"
  type="${COLUMN_TYPES[$key]}"
  total_count=$((total_count + 1))

  if ! index_exists "$table" "$column"; then
    missing_count=$((missing_count + 1))
    if [[ "$type" == "polymorphic" ]]; then
      base_column="${column%_id}"
      missing_index_reports["$key"]="${RED}✗ Table '$table' has no index on polymorphic association '${base_column}' (columns: ${base_column}_type, ${base_column}_id)${NC}"
      missing_index_commands["$key"]="add_index :$table, [:${base_column}_type, :${base_column}_id]"
    else
      missing_index_reports["$key"]="${RED}✗ Table '$table' has no index on '$column' (type: $type)${NC}"
      missing_index_commands["$key"]="add_index :$table, :$column"
    fi
    missing_indexes=true
  else
    indexed_count=$((indexed_count + 1))
  fi
done

# Print sorted missing index reports
for key in "${sorted_keys[@]}"; do
  if [[ -v "missing_index_reports[$key]" ]]; then
    echo -e "${missing_index_reports[$key]}"
  fi
done

if [ "$missing_indexes" = true ]; then
  echo
  echo "Add missing indexes with:"
  echo

  # Print sorted missing index commands
  for key in "${sorted_keys[@]}"; do
    if [[ -v "missing_index_commands[$key]" ]]; then
      echo "${missing_index_commands[$key]}"
    fi
  done
fi

echo
echo "Summary:"
echo "--------"
echo -e "Total columns checked: ${total_count}"
echo -e "Columns with indexes: ${GREEN}${indexed_count}${NC}"
echo -e "Columns missing indexes: ${RED}${missing_count}${NC}"

if [ "$missing_indexes" = true ]; then
  echo
  echo -e "${YELLOW}Some foreign key columns are missing indexes.${NC}"
  echo "Consider adding indexes to improve query performance."
  exit 1
else
  echo
  echo -e "${GREEN}All foreign key columns have indexes. Good job!${NC}"
  exit 0
fi
