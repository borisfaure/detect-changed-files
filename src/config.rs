use std::collections::HashMap;
use std::fmt;

#[derive(Debug, Clone)]
pub struct ParseError {
    pub line: usize,
    pub message: String,
}

impl fmt::Display for ParseError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "Parse error at line {}: {}", self.line, self.message)
    }
}

impl std::error::Error for ParseError {}

/// Parses a configuration string into a HashMap of sections and their items.
pub fn parse_config(content: &str) -> Result<HashMap<String, Vec<String>>, ParseError> {
    let mut result = HashMap::new();
    let mut current_section = String::new();
    let mut vec_section: Vec<String> = Vec::new();

    for (line_num, line) in content.lines().enumerate() {
        let line_number = line_num + 1;
        let trimmed = line.trim();

        // Skip empty lines and comments
        if trimmed.is_empty() || trimmed.starts_with('#') || trimmed.starts_with(";") {
            continue;
        }

        // Parse section headers
        if trimmed.starts_with('[') && trimmed.ends_with(']') {
            // Save previous section items if any
            if !current_section.is_empty() {
                result.insert(
                    std::mem::take(&mut current_section),
                    std::mem::take(&mut vec_section),
                );
            }
            if trimmed.len() < 3 {
                return Err(ParseError {
                    line: line_number,
                    message: "Invalid section header: too short".to_string(),
                });
            }

            current_section = trimmed[1..trimmed.len() - 1].to_string();

            if result.contains_key(&current_section) {
                return Err(ParseError {
                    line: line_number,
                    message: format!("Duplicate section: '{}'", current_section),
                });
            }
        } else {
            if current_section.is_empty() {
                return Err(ParseError {
                    line: line_number,
                    message: "Item found before any section is defined".to_string(),
                });
            }

            let item = trimmed.to_string();
            if item.is_empty() {
                return Err(ParseError {
                    line: line_number,
                    message: "Item cannot be empty".to_string(),
                });
            }
            vec_section.push(item);
        }
    }
    if !current_section.is_empty() {
        result.insert(current_section, vec_section);
    }

    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_empty_config() {
        let content = "";
        let result = parse_config(content).unwrap();
        assert!(result.is_empty());
    }

    #[test]
    fn test_valid_config() {
        let content = r#"
[compile]
.github/changed-files.conf
src/**

[test]
tests/**
"#;

        let result = parse_config(content).unwrap();
        assert_eq!(result.len(), 2);
        assert!(result.contains_key("compile"));
        assert_eq!(result["compile"].len(), 2);
        assert!(result.contains_key("test"));
        assert_eq!(result["test"].len(), 1);
    }

    #[test]
    fn test_empty_section_alone() {
        let content = "[empty-section]\n";
        let result = parse_config(content).unwrap();
        assert!(result.contains_key("empty-section"));
        assert_eq!(result["empty-section"].len(), 0);
    }

    #[test]
    fn test_empty_section_before_full_section() {
        let content = r#"
[empty-section]
[section]
item1
item2
"#;
        let result = parse_config(content).unwrap();
        assert!(result.contains_key("empty-section"));
        assert_eq!(result["empty-section"].len(), 0);
        assert!(result.contains_key("section"));
        assert_eq!(result["section"].len(), 2);
    }

    #[test]
    fn test_comments() {
        let content = r#"
# This is a comment
[section]
# Another comment
item1
item2
"#;
        let result = parse_config(content).unwrap();
        assert_eq!(result["section"].len(), 2);
    }

    #[test]
    fn test_duplicate_section() {
        let content = r#"
[section]
item1
[section]
item2
"#;
        let err = parse_config(content).unwrap_err();
        assert_eq!(err.line, 4);
        assert!(err.message.contains("Duplicate section"));
    }

    #[test]
    fn test_item_before_section() {
        let content = r#"
item1
[section]
"#;
        let err = parse_config(content).unwrap_err();
        assert_eq!(err.line, 2);
        assert!(err.message.contains("before any section"));
    }

    #[test]
    fn test_whitespace_only_line() {
        // Whitespace-only lines should be skipped (treated as empty)
        let content = r#"
[section]
        
item1
"#;
        let result = parse_config(content).unwrap();
        assert_eq!(result["section"].len(), 1);
        assert_eq!(result["section"][0], "item1");
    }
}
