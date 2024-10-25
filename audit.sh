#!/usr/bin/env bash

# Enable error handling
set -euo pipefail

# Source the check_indexes.sh file
source ./check_indexes.sh

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

# Initialize global variables
initialize_globals

# Parse the schema
parse_schema

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

for key in "${!SCHEMA_COLUMNS[@]}"; do
  IFS=':' read -r table column <<< "$key"
  type="${COLUMN_TYPES[$key]}"
  total_count=$((total_count + 1))

  if ! index_exists "$table" "$column"; then
    missing_count=$((missing_count + 1))
    echo -e "${RED}✗ Table '$table' has no index on '$column' (type: $type)${NC}"
    echo "  - Add with: add_index :$table, :$column"
    missing_indexes=true
  else
    indexed_count=$((indexed_count + 1))
  fi
done

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
