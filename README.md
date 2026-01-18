[![CI](https://github.com/borisfaure/detect-changed-files/actions/workflows/build-and-test.yaml/badge.svg)](https://github.com/borisfaure/detect-changed-files/actions/workflows/build-and-test.yaml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

# detect-changed-files

A fast, lightweight tool written in Rust that analyzes changed files from git diffs and categorizes them based on configurable pattern matching rules. It's designed to be used in CI/CD pipelines to determine which parts of a codebase have been modified.

## Features

- **Fast pattern matching**: Uses efficient glob-style pattern matching with support for `*`, `?`, and `**` wildcards
- **simple configuration**: Simple configuration for defining file pattern groups
- **JSON output**: Produces structured JSON output for easy integration with CI/CD systems
- **Git integration**: Designed to work with `git diff --name-only` output
- **Unicode support**: Full Unicode support for file paths and pattern matching

## Installation

### Prerequisites

- [Rust](https://www.rust-lang.org/) 1.70 or later

### Building from source

```bash
git clone https://github.com/borisfaure/detect-changed-files
cd detect-changed-files
cargo build --release
```

The executable will be built as `target/release/detect_changed_files`.

## Usage

### Basic Usage

The tool takes a configuration file as its first argument and reads changed file paths from stdin (typically the output of `git diff --name-only`):

```bash
git diff --name-only | ./detect_changed_files config.conf
```

### Configuration File Format

The configuration file uses a simple INI-like format with section headers and pattern lists. Each section name represents a group name, and patterns are listed one per line under each section. Patterns are similar to ones used in .gitignore files.

#### Pattern Syntax

The tool supports the following pattern matching features:

- `*` - Matches any sequence of characters except `/`
- `?` - Matches any single character except `/`
- `**` - Matches zero or more path components (directories)
- `/` - Directory separator


#### Configuration Format Rules

- Section headers are defined using square brackets: `[section-name]`
- Patterns are listed one per line under each section
- Empty lines are ignored
- Comments start with `#` or `;`
- Section names must be unique

#### Example Configuration

```ini
# Example: changed-files.conf

[github-workflows]
.github/workflows/**

[c]
*.c
*.h
meson.build
/meson_options.txt

[doc]
docs/**
README.md
```

### Output Format

The tool outputs JSON to stdout with boolean values indicating which groups have matching files:

```json
{
  "c": true,
  "github-workflows": false,
  "doc": true
}
```

## Examples

### Example 1: Basic Usage

```bash
# Check which groups are affected by changes
git diff --name-only | ./detect_changed_files changed-files.conf
```

### Example 2: Using with a specific commit range

```bash
# Check changes between two commits
git diff --name-only HEAD~1 HEAD | ./detect_changed_files changed-files.conf
```

### Example 3: Using with staged changes

```bash
# Check staged changes
git diff --name-only --cached | ./detect_changed_files changed-files.conf
```

### Example 4: In a github Actions workflow

In a GitHub Actions workflow, you can use this tool to conditionally run jobs
based on changed files. Here's an example of how to set it up:

The groups.conf file might look like this to define a linter group for all
Python files:
```ini
[linter]
*.py
```

The GitHub Actions workflow file (`.github/workflows/detect-changes.yml`)
could look like this:
```yaml
jobs:
  detect-changes:
    outputs:
      run: ${{ steps.changed-groups.outputs.run }}
    steps:
    - name: Checkout code
      uses: actions/checkout@v4
      with:
        fetch-depth: 1
    - name: fetch branch
      id: changed-groups
      run: |
        git fetch --depth=1 origin ${{ github.base_ref }}
        gh -R borisfaure/detect-changed-files release download -p detect_changed_files-ubuntu-latest -O detect_changed_files
        chmod +x detect_changed_files
        RUN=$(git diff --name-only ${BASE_SHA} | ./detect_changed_files .groups.conf)
        printf "run=%s" "$RUN" >> $GITHUB_OUTPUT

  linter:
    needs: detect-changes
    if: fromJson(needs.detect-changes.outputs.run).linter
    ...
```



## Testing

Run the test suite:

```bash
cargo test
```

## Building and Running

### Development build

```bash
cargo build
git diff --name-only | ./target/debug/detect_changed_files changed-files.conf
```

### Release build

```bash
cargo build --release
git diff --name-only | ./target/release/detect_changed_files changed-files.conf
```

### Static build

For a fully static binary that can run on any Linux system without dependencies:

```bash
# Install the musl target (one-time setup)
rustup target add x86_64-unknown-linux-musl

# Build a static binary
cargo build --release --target x86_64-unknown-linux-musl
```

The static binary will be at `target/x86_64-unknown-linux-musl/release/detect_changed_files`.

The release build is already optimized for size with:
- Symbol stripping
- Link-time optimization (LTO)
- Size optimization (`opt-level = "z"`)
- Single codegen unit for maximum optimization

### Container build

Build a minimal container image with Docker or Podman:

```bash
podman build . -t detect-changed-files:latest
```

Run the container by mounting your config file and piping the changed files to stdin:

```bash
cat tests/diff_small | podman run --rm -i --network none \
  -v ./changed-files.conf:/config.conf:ro \
  detect-changed-files:latest /detect-changed-files /config.conf
```

Or with git diff:

```bash
git diff --name-only | podman run --rm -i --network none \
  -v ./changed-files.conf:/config.conf:ro \
  detect-changed-files:latest /detect-changed-files /config.conf
```

The Dockerfile creates a statically-linked binary and packages it in a minimal scratch container for the smallest possible image size.

## Error Handling

The tool will exit with an error code if:

- No configuration file path is provided
- The configuration file cannot be read or parsed
- The configuration format is invalid (e.g., duplicate sections, items before sections)
- Memory allocation fails

## Performance

The tool is designed for high performance:

- Efficient pattern matching with memoization
- Minimal memory allocations
- Fast JSON serialization

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE)
file for details.
