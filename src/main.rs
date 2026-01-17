mod config;
mod diff;
mod matching;

use std::collections::HashMap;
use std::env;
use std::fs;
use std::io::{self, Write};
use std::process;

const VERSION: &str = env!("CARGO_PKG_VERSION");

fn print_help() {
    let help_text = format!(
        "detect-changed-files v{} - Analyze changed files and categorize them based on patterns

USAGE:
    detect_changed_files [OPTIONS] <config.conf>

ARGS:
    <config.conf>    Path to the configuration file

OPTIONS:
    -h, --help       Print this help message
    -V, --version    Print version information

DESCRIPTION:
    This tool reads changed file paths from stdin (typically the output of
    'git diff --name-only') and categorizes them based on patterns defined
    in the configuration file.

    The tool outputs JSON to stdout with boolean values indicating which
    groups have matching files.

EXAMPLES:
    # Basic usage
    git diff --name-only | detect_changed_files config.conf

    # Check staged changes
    git diff --name-only --cached | detect_changed_files config.conf

    # Check changes between commits
    git diff --name-only HEAD~1 HEAD | detect_changed_files config.conf

CONFIGURATION:
    The configuration file uses section-based format where each section name
    (in square brackets) represents a group, followed by file patterns on
    separate lines. Patterns use glob-style syntax:

    - * matches any sequence of characters except /
    - ? matches any single character except /
    - ** matches zero or more path components (directories)

OUTPUT:
    JSON object with group names as keys and boolean values indicating
    whether any files matched that group's patterns.
",
        VERSION
    );
    eprintln!("{}", help_text);
}

fn print_version() {
    println!("{}", VERSION);
}

fn check_patterns(
    config: &HashMap<String, Vec<String>>,
    diff_files: &diff::DiffFiles,
) -> HashMap<String, bool> {
    let mut results = HashMap::new();

    // Initialize all groups to false
    for group_name in config.keys() {
        results.insert(group_name.clone(), false);
    }

    // Check each changed file against all patterns
    for file_path in &diff_files.files {
        for (group_name, patterns) in config.iter() {
            // Skip if already matched
            if *results.get(group_name).unwrap() {
                continue;
            }

            // Check if any pattern matches this file
            for pattern_str in patterns {
                let pattern = matching::MatchPath::from_str(pattern_str);
                if pattern.is_match(file_path) {
                    results.insert(group_name.clone(), true);
                    break;
                }
            }
        }
    }

    results
}

fn generate_json(results: &HashMap<String, bool>) -> String {
    let mut json = String::from("{\n");

    let mut entries: Vec<_> = results.iter().collect();
    entries.sort_by_key(|(k, _)| *k);

    for (i, (key, value)) in entries.iter().enumerate() {
        let value_str = if **value { "true" } else { "false" };
        json.push_str(&format!("  \"{}\": {}", key, value_str));

        if i < entries.len() - 1 {
            json.push(',');
        }
        json.push('\n');
    }

    json.push('}');
    json
}

fn main() {
    let args: Vec<String> = env::args().collect();

    // Handle help and version flags
    if args.len() == 2 {
        match args[1].as_str() {
            "-h" | "--help" => {
                print_help();
                return;
            }
            "-V" | "--version" => {
                print_version();
                return;
            }
            _ => {}
        }
    } else if args.len() < 2 {
        eprintln!("Error: No configuration file specified");
        eprintln!("Use -h or --help for usage information");
        process::exit(1);
    } else if args.len() > 2 {
        eprintln!("Error: Too many arguments");
        eprintln!("Use -h or --help for usage information");
        process::exit(1);
    }

    let config_path = &args[1];

    // Read and parse configuration file
    let config_content = match fs::read_to_string(config_path) {
        Ok(content) => content,
        Err(e) => {
            eprintln!("Error reading config file '{}': {}", config_path, e);
            process::exit(1);
        }
    };

    let config = match config::parse_config(&config_content) {
        Ok(cfg) => cfg,
        Err(e) => {
            eprintln!("Error parsing config file: {}", e);
            process::exit(1);
        }
    };

    // Read changed files from stdin
    let diff_files = match diff::DiffFiles::from_stdin() {
        Ok(files) => files,
        Err(e) => {
            eprintln!("Error reading from stdin: {}", e);
            process::exit(1);
        }
    };

    // Check patterns and generate results
    let results = check_patterns(&config, &diff_files);

    // Generate and output JSON
    let json_output = generate_json(&results);

    if let Err(e) = io::stdout().write_all(json_output.as_bytes()) {
        eprintln!("Error writing output: {}", e);
        process::exit(1);
    }
}
