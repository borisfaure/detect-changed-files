# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.2] - 2025-07-07

### Changed
- Updated README with more examples and usage instructions
- Change release binary names not to include version number in the name

### Added
- Have version in help output
- Add `--version`,`-V` flags to display the version of the tool


## [0.0.1] - 2025-07-06

### Added
- Core file change detection functionality written in Zig
- YAML configuration support for flexible matching rules
- JSON output format
- Absolute and relative path matching support
- Unicode handling for international file names
- Basic CI workflows with GitHub Actions
- Dependabot setup
- CI workflows to run on all available workers: build, test and check
  formatting
- Release workflow with different build optimizations
