<p align="center">
  <img src="https://imgur.com/G6Tgzou.png" />
</p>

# IDs Must Be Indexed

**A GitHub Action that checks your Rails migrations for missing database indexes.**

When you add a column like `user_id` to a table, you almost always need an index on it. Without an index, your database queries will be slow. This action stops pull requests that forget to add indexes.

```
Error: Missing index for foreign key column 'comment_id' in table 'albums'
Details:
- Column type: bigint (64-bit integer typically used for foreign keys)
- Column appears to be a foreign key (ends with _id)
- Please add an index to improve query performance
- You can add it using: add_index :albums, :comment_id
```

## Why Use This?

When you add a foreign key column in Rails, you should also add an index. But it's easy to forget. If you use `add_column` instead of `references`, Rails won't add the index for you.

Missing indexes hurt your app's speed. JOINs and `preload` calls become much slower. Most columns that end in `_id` will be used in queries. This action checks every pull request and fails if an index is missing.

This pattern is called a [poka-yoke](https://en.wikipedia.org/wiki/Poka-yoke)—a check that prevents mistakes before they happen.

## Features

- **Blocks pull requests** that are missing indexes on foreign key columns
- **Quick setup**—no config needed. Only checks columns changed in each PR, so you can add it to any project right away.
- **Catches changes across migrations**—if you create a column in one migration and change its type in another, both are checked
- **Works with all column types**: bigint, integer, uuid, references, polymorphic, and composite indexes

## Requirements

- Your app must use **schema.rb**. This action does not support structure.sql.

## Installation

Add this file to your repo at `.github/workflows/check-indexes.yml`:

```yaml
name: Check Indexes
on:
  pull_request:
    paths:
      - 'db/migrate/**.rb'

jobs:
  check-indexes:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Check Migration Indexes
        uses: speedshop/ids_must_be_indexed@v1.2.1
```

That's it. The action runs on every pull request that changes migration files.

## Audit Your Existing Schema

Want to find missing indexes in your current schema? Run these commands:

```bash
wget https://raw.githubusercontent.com/speedshop/ids_must_be_indexed/refs/heads/main/audit.sh
wget https://raw.githubusercontent.com/speedshop/ids_must_be_indexed/refs/heads/main/check_indexes.sh
chmod +x audit.sh
./audit.sh
```

This prints a list of columns that look like foreign keys but don't have indexes.

## Configuration

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| debug | Show debug output | No | '0' |

## Examples

### Will Pass

```ruby
# Column with index
class AddCompanyToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :company_id, :bigint
    add_index :users, :company_id
  end
end
```

```ruby
# Using references (adds index by default)
class CreateOrders < ActiveRecord::Migration[7.0]
  def change
    create_table :orders do |t|
      t.references :user, index: true
      t.timestamps
    end
  end
end
```

```ruby
# Composite index—passes if the column appears anywhere in an index
class AddDepartmentToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :department_id, :bigint
    add_index :users, [:company_id, :department_id]
  end
end
```

> [!NOTE]
> If you use a composite index like `[:company_id, :department_id]`, queries on `department_id` alone may still be slow. Add a separate index if you query by `department_id` without `company_id`.

### Will Fail

```ruby
# Missing index
class AddCompanyToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :company_id, :bigint
    # No index!
  end
end
```

```ruby
# Column type changed to a foreign key type without adding an index
class CreateAlbums < ActiveRecord::Migration[7.0]
  def change
    create_table :albums do |t|
      t.string :comment_id  # Starts as string
    end
  end
end

class ChangeCommentIdType < ActiveRecord::Migration[7.0]
  def change
    change_column :albums, :comment_id, :bigint  # Now a foreign key
    # Needs an index!
  end
end
```

## Skipping the Check

Sometimes you need to skip the index check. For example:

- The column won't be used in queries
- You have disk space limits
- You're testing something

There are four ways to skip:

**1. Add `[skip-index-check]` to your commit message:**

```bash
git commit -m "Add user migration [skip-index-check]"
```

**2. Add `[skip-index-check]` to your pull request title:**

```yaml
- name: Check Migration Indexes
  uses: speedshop/ids_must_be_indexed@v1.2.1
  env:
    GITHUB_PR_TITLE: ${{ github.event.pull_request.title }}
```

**3. Set an environment variable in your workflow:**

```yaml
- name: Check Migration Indexes
  uses: speedshop/ids_must_be_indexed@v1.2.1
  env:
    SKIP_INDEX_CHECK: "1"
```

**4. Set an environment variable locally:**

```bash
SKIP_INDEX_CHECK=1 ./check_indexes.sh
```

> [!WARNING]
> Use skip options only when you have a good reason. Missing indexes cause slow queries in production. Always explain why you skipped the check in your commit message or PR description.

## Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

### Running Tests

```bash
# Install BATS
brew install bats-core  # or: apt-get install bats

# Run tests
bats test/migration-index-test.bats
```

## Project Structure

| File | Purpose |
|------|---------|
| `action.yml` | GitHub Action definition |
| `check_indexes.sh` | Main script that checks migrations |
| `audit.sh` | Script to check your existing schema |
| `test/` | BATS test files |

## Acknowledgments

This action was inspired by a [Danger](https://github.com/danger/danger) check at [Gusto](https://github.com/gusto), written by [Toni Rib](https://github.com/tonirib).

Development was sponsored by [Easol](https://github.com/easolhq).

The original code was written with help from Claude 3.5 Sonnet.
