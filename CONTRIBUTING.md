# Contributing

We welcome contributions! Here's what you need to know:

1. Create a new branch for your work.
2. Initialize submodules: `git submodule update --init --recursive`.
3. Ensure all tests pass: `PATH="$PWD:$PATH" ./vendor/brat/bin/brat test/*.brat`.
4. Run `shellcheck` on all shell scripts.
5. Update documentation if necessary.

## Prerequisites

```
brew install shellcheck
```

## Guidelines

- Keep pull requests below about 100 lines of code.

## Reporting Issues

Use the GitHub issue tracker. Provide as much detail as possible, hopefully with `DEBUG=1` output.

Thank you for contributing!
