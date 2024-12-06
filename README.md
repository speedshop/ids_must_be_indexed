<p align="center">
  <img src="https://imgur.com/G6Tgzou.png" />
</p>

# "_ID Must Be Indexed": A Rails Foreign Key Index Check

A GitHub Action to ensure all Rails application foreign key columns (any column ending in `_id` and an `integer`, `bigint` or `uuid`) have corresponding database indexes.

```
Error: Missing index for foreign key column 'comment_id' in table 'albums'
Details:
- Column type: bigint (64-bit integer typically used for foreign keys)
- Column appears to be a foreign key (ends with _id)
- Please add an index to improve query performance
- You can add it using: add_index :albums, :comment_id
```

## Problem

If you forget to use `references` when adding a foreign key column, you'll usually also forget to add the index.

Missing indexes on foreign keys is a massive tax on the performance of your application, as things like JOINs and `preload` calls will be much slower.

99% of the time when a column ends in _id, you're eventually going to JOIN or query based on that column. Rather than leave it up to the developer to _hopefully_ remember to always do this, this action is a [poka-yoke](https://en.wikipedia.org/wiki/Poka-yoke) which creates a strong default.

## Features

- **Fails your pull request** if you are missing indexes on foreign key columns
- **Install in 10 seconds**, without any dependencies or configuration. Since it only runs on columns changed in each PR, you can add this to any project without spending a half hour adding ignored columns.
- Catches foreign keys created or **modified across multiple migrations**
- Supports various column types (**bigint, integer,** uuid or references), polymorphic associations and composite indexes

## Requirements

- Must be using **schema.rb**, structure.sql is not supported.

## Usage

Add this to a GitHub workflow (e.g. `.github/workflows/check-indexes.yml`):

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

## Auditing Existing Schema

You may also want to **audit your existing schema.rb** for missing foreign key indexes.

Look at `audit.sh` in this repository. Copy `audit.sh` and `check_indexes.sh` to your repo, `chmod +x audit.sh` and then run it. You'll get a list of columns which look like foreign keys and are unindexed.

## Configuration

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| debug | Enable debug output | No | '0' |

## Common Scenarios

### ✅ Will Pass

```ruby
# Single migration with index
class AddCompanyToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :company_id, :bigint
    add_index :users, :company_id
  end
end

# References with index
class CreateOrders < ActiveRecord::Migration[7.0]
  def change
    create_table :orders do |t|
      t.references :user, index: true
      t.timestamps
    end
  end
end

# Multi-column index
# We pass if the column appears in the index anywhere, because this is highly
# dependent on your query pattern. In this example, if you ever join users to
# departments only, you should add an additional index.
class AddDepartmentToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :department_id, :bigint
    add_index :users, [:company_id, :department_id]
  end
end
```

### ❌ Will Fail

```ruby
# Missing index
class AddCompanyToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :company_id, :bigint
    # Missing index!
  end
end
```

```ruby
# Foreign key created across migrations
class CreateAlbums < ActiveRecord::Migration[7.0]
  def change
    create_table :albums do |t|
      t.string :comment_id  # Starts as string
    end
  end
end

class ChangeCommentIdType < ActiveRecord::Migration[7.0]
  def change
    change_column :albums, :comment_id, :bigint  # Changed to foreign key
    # Needs an index!
  end
end
```

## Skipping

There are times when you might want to skip the index check, such as:
- Temporary migrations
- Special cases where indexes would be inappropriate, like when disk space is limited
- Development or testing scenarios

You can skip the check in three ways:

1. Add `[skip-index-check]` to your commit message:
```bash
git commit -m "Add user migration [skip-index-check]"
```
2. Add `[skip-index-check]` to your pull request title:
```yaml
- name: Check Migration Indexes
  uses: your-username/ids_must_be_indexed@v1.2.1
  env:
    GITHUB_PR_TITLE: ${{ github.event.pull_request.title }}
```

3. Set environment variable in your workflow:
```yaml
- name: Check Migration Indexes
  uses: your-username/ids_must_be_indexed@v1.2.1
  env:
    SKIP_INDEX_CHECK: "1"
```

4. Set environment variable locally:
```bash
SKIP_INDEX_CHECK=1 ./check_indexes.sh
```

⚠️ **Note**: Use skip options sparingly. Missing indexes can cause significant performance issues in production. Always document why you're skipping the check in your commit message or pull request description.

## Development

### Running Tests

```bash
# Install BATS
brew install bats-core  # or apt-get install bats

# Run tests
bats test/migration-index-test.bats
```

## Contributing

Contributions are welcome! Please check out our [Contributing Guide](CONTRIBUTING.md).

## Acknowledgments

This action was inspired by a [Danger](https://github.com/danger/danger) check at [Gusto](https://github.com/gusto), written by the incredible [Toni Rib](https://github.com/tonirib).

The original development of this action was sponsored by [Easol](https://github.com/easolhq).

The original development of this action was heavily assisted by Claude 3.5 Sonnet. I'm a Ruby guy, not a bash guy.
