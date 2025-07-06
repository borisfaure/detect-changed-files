[![CI](https://github.com/borisfaure/detect-changed-files/actions/workflows/build-and-test.yml/badge.svg)](https://github.com/borisfaure/detect-changed-files/actions/workflows/build-and-test.yaml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

# detect-changed-files

A fast, lightweight tool written in Zig that analyzes changed files from git diffs and categorizes them based on configurable pattern matching rules. It's designed to be used in CI/CD pipelines to determine which parts of a codebase have been modified.

## Features

- **Fast pattern matching**: Uses efficient glob-style pattern matching with support for `*`, `?`, and `**` wildcards
- **YAML configuration**: Simple YAML-based configuration for defining file pattern groups
- **JSON output**: Produces structured JSON output for easy integration with CI/CD systems
- **Git integration**: Designed to work with `git diff --name-only` output
- **Unicode support**: Full Unicode support for file paths and pattern matching

## Installation

### Prerequisites

- [Zig](https://ziglang.org/) 0.14.1 or later

### Building from source

```bash
git clone <repository-url>
cd detect-changed-files
zig build
```

The executable will be built as `zig-out/bin/detect_changed_files`.

## Usage

### Basic Usage

The tool takes a YAML configuration file as its first argument and reads changed file paths from stdin (typically the output of `git diff --name-only`):

```bash
git diff --name-only | ./detect_changed_files config.yaml
```

### Configuration File Format

The configuration file is a YAML file where each key represents a group name,
and the value is a list of file patterns. Patterns are similar to ones used in
.gitignore files, with some limitations.

#### Pattern Syntax

The tool supports the following pattern matching features:

- `*` - Matches any sequence of characters except `/`
- `?` - Matches any single character except `/`
- `**` - Matches zero or more path components (directories)
- `/` - Directory separator


#### Example Configuration

```yaml
# Example: changed-files.yaml
github-workflows:
  - .github/workflows/

c:
  - '*.c'
  - '*.h'
  - 'meson.build'
  - /meson_options.txt

doc:
  - 'docs/**'
  - 'README.md'
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
git diff --name-only | ./detect_changed_files changed-files.yaml
```

### Example 2: Using with a specific commit range

```bash
# Check changes between two commits
git diff --name-only HEAD~1 HEAD | ./detect_changed_files changed-files.yaml
```

### Example 3: Using with staged changes

```bash
# Check staged changes
git diff --name-only --cached | ./detect_changed_files changed-files.yaml
```


## Testing

Run the test suite:

```bash
zig build test
```

## Building and Running

### Development build

```bash
zig build
git diff --name-only | ./zig-out/bin/detect_changed_files changed-files.yaml
```

### Release build

```bash
zig build -Doptimize=ReleaseFast
git diff --name-only | ./zig-out/bin/detect_changed_files changed-files.yaml
```


## Error Handling

The tool will exit with an error code if:

- No configuration file path is provided
- The configuration file cannot be read or parsed
- The YAML format is invalid
- Memory allocation fails

## Performance

The tool is designed for high performance:

- Efficient pattern matching with memoization
- Minimal memory allocations
- Fast JSON serialization

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE)
file for details.
