#!/usr/bin/env bats

setup() {
  # Create temporary directory for each test
  export TEMP_DIR="$(mktemp -d)"
  export GITHUB_WORKSPACE="$TEMP_DIR"
  cd "$TEMP_DIR"

  # Set up git repo
  git init
  git config --local user.email "test@example.com"
  git config --local user.name "Test User"
  git checkout -b main

  # Create base branch
  git checkout -b base
  mkdir -p db
  touch db/schema.rb
  git add .
  git commit -m "Initial commit"

  # Create feature branch
  git checkout -b feature

  # Copy the script to test directory
  cp "$BATS_TEST_DIRNAME"/../check_indexes.sh .
  chmod +x check_indexes.sh
}

teardown() {
  rm -rf "$TEMP_DIR"
}

# Helper to create schema.rb content
create_schema() {
  cat > db/schema.rb << EOF
ActiveRecord::Schema[7.2].define(version: 2024_01_01_000000) do
  $1
end
EOF
}

# Helper to create migration file
create_migration() {
  local filename="$1"
  local content="$2"
  mkdir -p db/migrate
  cat > "db/migrate/$filename" << EOF
$content
EOF
}

@test "passes when bigint has index" {
  create_schema '
  create_table "users", force: :cascade do |t|
    t.bigint "company_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_index "users", ["company_id"], name: "index_users_on_company_id"'

  create_migration "20240101000000_create_users.rb" '
class CreateUsers < ActiveRecord::Migration[7.2]
  def change
    create_table :users do |t|
      t.bigint :company_id
      t.timestamps
    end
    add_index :users, :company_id
  end
end'

  run ./check_indexes.sh
  [ "$status" -eq 0 ]
}

@test "fails when bigint has no index" {
  create_schema '
  create_table "users", force: :cascade do |t|
    t.bigint "company_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end'

  create_migration "20240101000000_create_users.rb" '
class CreateUsers < ActiveRecord::Migration[7.2]
  def change
    create_table :users do |t|
      t.bigint :company_id
      t.timestamps
    end
  end
end'

  run ./check_indexes.sh
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Missing index for foreign key column 'company_id' in table 'users'" ]]
}

@test "passes with composite index" {
  create_schema '
  create_table "orders", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "product_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_index "orders", ["user_id", "product_id"], name: "index_orders_on_user_id_and_product_id"'

  create_migration "20240101000000_create_orders.rb" '
class CreateOrders < ActiveRecord::Migration[7.2]
  def change
    create_table :orders do |t|
      t.bigint :user_id
      t.bigint :product_id
      t.timestamps
    end
    add_index :orders, [:user_id, :product_id]
  end
end'

  run ./check_indexes.sh
  [ "$status" -eq 0 ]
}

@test "fails when column becomes foreign key" {
  create_schema '
  create_table "albums", force: :cascade do |t|
    t.bigint "comment_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end'

  create_migration "20240101000000_create_albums.rb" '
class CreateAlbums < ActiveRecord::Migration[7.2]
  def change
    create_table :albums do |t|
      t.string :comment_id
      t.timestamps
    end
  end
end'

  create_migration "20240101000001_change_comment_id_type.rb" '
class ChangeCommentIdType < ActiveRecord::Migration[7.2]
  def change
    change_column :albums, :comment_id, :bigint
  end
end'

  run ./check_indexes.sh
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Missing index for foreign key column 'comment_id' in table 'albums'" ]]
}

@test "passes with references and index" {
  create_schema '
  create_table "posts", force: :cascade do |t|
    t.bigint "author_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_index "posts", ["author_id"], name: "index_posts_on_author_id"'

  create_migration "20240101000000_create_posts.rb" '
class CreatePosts < ActiveRecord::Migration[7.2]
  def change
    create_table :posts do |t|
      t.references :author, index: true
      t.timestamps
    end
  end
end'

  run ./check_indexes.sh
  [ "$status" -eq 0 ]
}

@test "handles integer foreign keys" {
  create_schema '
  create_table "comments", force: :cascade do |t|
    t.integer "post_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end'

  create_migration "20240101000000_create_comments.rb" '
class CreateComments < ActiveRecord::Migration[7.2]
  def change
    create_table :comments do |t|
      t.integer :post_id
      t.timestamps
    end
  end
end'

  run ./check_indexes.sh
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Missing index for foreign key column 'post_id' in table 'comments'" ]]
}

@test "debug output works when enabled" {
  export DEBUG=1

  create_schema '
  create_table "users", force: :cascade do |t|
    t.bigint "company_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_index "users", ["company_id"], name: "index_users_on_company_id"'

  create_migration "20240101000000_create_users.rb" '
class CreateUsers < ActiveRecord::Migration[7.2]
  def change
    create_table :users do |t|
      t.bigint :company_id
      t.timestamps
    end
    add_index :users, :company_id
  end
end'

  run env DEBUG=1 ./check_indexes.sh
  echo "Test output:"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Schema columns that need indexes" ]]
}

@test "skips check when commit message contains [skip-index-check]" {
  # Create schema without index
  create_schema '
  create_table "users", force: :cascade do |t|
    t.bigint "company_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end'

  # Create migration with [skip-index-check] in commit message
  create_migration "20240101000000_create_users.rb" '
class CreateUsers < ActiveRecord::Migration[7.2]
  def change
    create_table :users do |t|
      t.bigint :company_id
      t.timestamps
    end
  end
end'

  # Amend the commit message to include skip tag
  git commit --amend -m "Add migration [skip-index-check]"

  run ./check_indexes.sh
  echo "output: $output"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Skipping index check" ]]
}

@test "skips check when SKIP_INDEX_CHECK environment variable is set" {
  # Create schema without index
  create_schema '
  create_table "users", force: :cascade do |t|
    t.bigint "company_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end'

  create_migration "20240101000000_create_users.rb" '
class CreateUsers < ActiveRecord::Migration[7.2]
  def change
    create_table :users do |t|
      t.bigint :company_id
      t.timestamps
    end
  end
end'

  SKIP_INDEX_CHECK=1 run ./check_indexes.sh
  echo "output: $output"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Skipping index check" ]]
}
