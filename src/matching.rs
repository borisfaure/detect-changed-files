// Do pattern matching on strings

use std::collections::HashMap;

// PATTERN FORMAT
//  - The slash "/" is used as the directory separator.
//  - Two consecutive asterisks ("**") in patterns match against many
//    successive path components
//  - Patterns that not start with a slash are considered relative and match
//    the same as if they started with `**/`.
//  - Patterns that end with a slash are considered directories and match any
//    file or directory within that directory or their subdirectories. It acts
//    as if it had a trailing "**".
//  - An asterisk "*" matches anything except a slash. The character "?"
//    matches any one character except "/".

#[derive(Debug, Clone)]
pub struct PathComponent {
    str: Vec<char>,
}

impl PathComponent {
    fn is_double_star(&self) -> bool {
        self.str.len() == 2 && self.str[0] == '*' && self.str[1] == '*'
    }

    fn new(chars: Vec<char>) -> Self {
        PathComponent { str: chars }
    }
}

#[derive(Debug)]
pub struct MatchPath {
    components: Vec<PathComponent>,
    is_absolute: bool,
    is_directory: bool,
}

impl MatchPath {
    pub fn new(path: &[char]) -> Self {
        if path.is_empty() {
            return MatchPath {
                components: Vec::new(),
                is_absolute: false,
                is_directory: false,
            };
        }

        let is_absolute = path[0] == '/';
        let is_directory = !path.is_empty() && path[path.len() - 1] == '/';
        let components = split_path_components(path);

        MatchPath {
            components,
            is_absolute,
            is_directory,
        }
    }

    pub fn from_str(path: &str) -> Self {
        let path_chars: Vec<char> = path.chars().collect();
        Self::new(&path_chars)
    }

    /// Check if the path matches the given text
    /// self is the pattern, text is the string to match against
    pub fn is_match(&self, text: &MatchPath) -> bool {
        // If the pattern has no components, it matches only if text is empty
        if self.components.is_empty() {
            return text.components.is_empty();
        }

        // index in self.components
        let mut pattern_idx: usize = 0;
        // index in text.components
        let mut text_idx: usize = 0;

        let mut is_double_star: bool = !self.is_absolute;

        // Iterate through both components
        while pattern_idx < self.components.len() && text_idx < text.components.len() {
            let pattern_comp = &self.components[pattern_idx];
            let text_comp = &text.components[text_idx];

            // If the pattern component is a double star, it matches anything
            if pattern_comp.is_double_star() {
                is_double_star = true;
                if pattern_idx + 1 == self.components.len() {
                    // If this is the last pattern component, it matches everything
                    return true;
                }
                pattern_idx += 1; // Move to the next pattern component
                text_idx += 1; // Move to the next text component
                continue;
            }

            if !match_pattern_component(&pattern_comp.str, &text_comp.str) {
                // If the current components do not match, check if we had a double star
                if is_double_star {
                    // If we had a double star, we can skip this text component
                    text_idx += 1;
                    continue;
                }
                // Otherwise, the match fails
                return false;
            } else {
                // There is a match!
                // Reset double star flag
                is_double_star = false;

                // Move to the next components in both
                pattern_idx += 1;
                text_idx += 1;
            }
        }

        if self.is_directory && pattern_idx == self.components.len() {
            return true;
        }

        if pattern_idx < self.components.len() || text_idx < text.components.len() {
            // If we still have pattern or text components left, it means we didn't match all components
            return false;
        }

        // If we reached here, all components matched
        true
    }
}

/// Split a string into path components
fn split_path_components(path: &[char]) -> Vec<PathComponent> {
    let mut components = Vec::new();
    let mut start: usize = 0;

    for (i, &c) in path.iter().enumerate() {
        if c == '/' {
            if i > start {
                let comp = PathComponent::new(path[start..i].to_vec());
                components.push(comp);
            }
            start = i + 1; // skip the '/'
        }
    }

    // Add last component if not empty
    if start < path.len() {
        let comp = PathComponent::new(path[start..].to_vec());
        components.push(comp);
    }

    components
}

fn match_pattern_component(pattern: &[char], text: &[char]) -> bool {
    let mut memo = HashMap::new();
    match_recursive_memo(pattern, text, 0, 0, &mut memo)
}

fn match_recursive_memo(
    pattern: &[char],
    text: &[char],
    p_idx: usize,
    t_idx: usize,
    memo: &mut HashMap<usize, bool>,
) -> bool {
    // Create unique key for this state
    let key = p_idx * 10000 + t_idx;

    // Check memoization
    if let Some(&result) = memo.get(&key) {
        return result;
    }

    // Base cases
    if p_idx == pattern.len() {
        let result = t_idx == text.len();
        memo.insert(key, result);
        return result;
    }

    if t_idx == text.len() {
        // If we're at end of text, pattern must be all * from here
        let result = pattern[p_idx..].iter().all(|&c| c == '*');
        memo.insert(key, result);
        return result;
    }

    let match_result = match pattern[p_idx] {
        '*' => {
            // Try matching 0, 1, 2, ... characters
            let mut result = false;
            for i in 0..=(text.len() - t_idx) {
                if match_recursive_memo(pattern, text, p_idx + 1, t_idx + i, memo) {
                    result = true;
                    break;
                }
            }
            result
        }
        '?' => {
            // Match exactly one character
            match_recursive_memo(pattern, text, p_idx + 1, t_idx + 1, memo)
        }
        _ => {
            // Exact character match
            if t_idx < text.len() && pattern[p_idx] == text[t_idx] {
                match_recursive_memo(pattern, text, p_idx + 1, t_idx + 1, memo)
            } else {
                false
            }
        }
    };

    memo.insert(key, match_result);
    match_result
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_match_pattern_component(pattern: &str, text: &str) -> bool {
        let pattern_chars: Vec<char> = pattern.chars().collect();
        let text_chars: Vec<char> = text.chars().collect();
        match_pattern_component(&pattern_chars, &text_chars)
    }

    #[test]
    fn component_multiple_star_wildcards() {
        assert!(test_match_pattern_component("a*b*c", "a123b456c"));
        assert!(test_match_pattern_component("a*b*c", "abc"));
        assert!(!test_match_pattern_component("a*b*c", "a123b456c789"));
        assert!(!test_match_pattern_component("a*b*c", "a123d456c")); // missing 'b'
        assert!(!test_match_pattern_component("a*b*c", "a123b")); // missing 'c'
        assert!(test_match_pattern_component("*", "anything"));
        assert!(test_match_pattern_component("a*", "a"));
        assert!(test_match_pattern_component("*a", "a"));
        assert!(test_match_pattern_component("a*b*", "ab"));
    }

    #[test]
    fn component_question_wildcard() {
        assert!(test_match_pattern_component("a?b", "a1b"));
        assert!(!test_match_pattern_component("a?b", "ab")); // '?' does not match empty
        assert!(!test_match_pattern_component("a?b", "abx")); // too long
        assert!(test_match_pattern_component("a?b", "acb"));
        assert!(test_match_pattern_component("a?b?", "a1b2"));
        assert!(!test_match_pattern_component("a?b?", "a1b"));
        assert!(!test_match_pattern_component("a?b?", "a1b2c")); // too long
    }

    #[test]
    fn component_exact_match() {
        assert!(test_match_pattern_component("abc", "abc"));
        assert!(!test_match_pattern_component("abc", "abcd")); // too long
        assert!(!test_match_pattern_component("abc", "ab")); // too short
        assert!(!test_match_pattern_component("abc", "abx")); // wrong character
        assert!(test_match_pattern_component("a?c", "abc")); // '?' matches 'b'
    }

    #[test]
    fn component_complex_patterns() {
        assert!(test_match_pattern_component("a*b?c", "a123b4c"));
        assert!(!test_match_pattern_component("a*b?c", "a123b456c"));
        assert!(test_match_pattern_component("a*b?c?d*", "a123b4c7d89"));
        assert!(!test_match_pattern_component("a*b?c", "a123b456c789"));
        assert!(!test_match_pattern_component("a*b?c", "a123d456c")); // missing 'b'
        assert!(!test_match_pattern_component("a*b?c", "a123b")); // missing 'c'
        assert!(test_match_pattern_component("a*b?c*", "a123b4c56"));
        assert!(!test_match_pattern_component("a*b?c*", "a123b456d789")); // wrong character
    }

    #[test]
    fn split_path_components_test() {
        let path: Vec<char> = "ab/cd/ef/gh/ij".chars().collect();
        let components = split_path_components(&path);
        assert_eq!(components.len(), 5);
    }

    #[test]
    fn match_path_absolute_pattern_eq_text() {
        let pattern = MatchPath::from_str("/ab/cd/ef.zig");
        let text = MatchPath::from_str("ab/cd/ef.zig");
        assert!(pattern.is_match(&text));

        let rel = MatchPath::from_str("foo/bar/ab/cd/ef.ghi");
        assert!(!pattern.is_match(&rel));
    }

    #[test]
    fn match_path_relative_pattern_eq_text() {
        let pattern = MatchPath::from_str("ab/cd/ef.zig");
        let text = MatchPath::from_str("ab/cd/ef.zig");
        assert!(pattern.is_match(&text));

        let deep = MatchPath::from_str("foo/bar/ab/cd/ef.zig");
        assert!(pattern.is_match(&deep));

        let nope = MatchPath::from_str("ab/cd/ef.ghi");
        assert!(!pattern.is_match(&nope));

        let nope2 = MatchPath::from_str("aaaaaab/cd/ef.ghi");
        assert!(!pattern.is_match(&nope2));
    }

    #[test]
    fn match_path_leading_double_star() {
        let pattern = MatchPath::from_str("**/ef.zig");

        let single = MatchPath::from_str("foo/ef.zig");
        assert!(pattern.is_match(&single));

        let multiple = MatchPath::from_str("ab/cd/ef.zig");
        assert!(pattern.is_match(&multiple));

        let nope = MatchPath::from_str("ef.zig");
        assert!(!pattern.is_match(&nope));
    }

    #[test]
    fn match_path_trailing_double_star() {
        let pattern = MatchPath::from_str("ab/cd/**");

        let single = MatchPath::from_str("ab/cd/ef.zig");
        assert!(pattern.is_match(&single));

        let multiple = MatchPath::from_str("ab/cd/ef/gh.zig");
        assert!(pattern.is_match(&multiple));

        let nope = MatchPath::from_str("ab/cd");
        assert!(!pattern.is_match(&nope));
    }

    #[test]
    fn match_path_double_star_in_middle() {
        let pattern = MatchPath::from_str("ab/**/cd/ef.zig");

        let single = MatchPath::from_str("ab/foo/cd/ef.zig");
        assert!(pattern.is_match(&single));

        let multiple = MatchPath::from_str("ab/foo/bar/cd/ef.zig");
        assert!(pattern.is_match(&multiple));

        let nope = MatchPath::from_str("ab/cd/ef.zig");
        assert!(!pattern.is_match(&nope));
    }

    #[test]
    fn match_path_complex_pattern_with_double_star_and_question() {
        let pattern = MatchPath::from_str("ab/cd/**/e?f/gh.zig");

        let single = MatchPath::from_str("ab/cd/foo/e3f/gh.zig");
        assert!(pattern.is_match(&single));

        let nope = MatchPath::from_str("ab/cd/foo/e33f/gh.zig");
        assert!(!pattern.is_match(&nope));
    }

    #[test]
    fn match_path_double_double_star() {
        let pattern = MatchPath::from_str("ab/**/cd/**/ef.zig");

        let single = MatchPath::from_str("ab/foo/cd/bar/ef.zig");
        assert!(pattern.is_match(&single));

        let multiple = MatchPath::from_str("ab/foo/cd/bar/baz/ef.zig");
        assert!(pattern.is_match(&multiple));

        let nope = MatchPath::from_str("ab/cd/ef.zig");
        assert!(!pattern.is_match(&nope));
    }

    #[test]
    fn match_path_with_utf8_strings() {
        // Test with UTF-8 strings
        let pattern = MatchPath::from_str("ab/**/e⚡f/g?h/ij.zig");
        let text = MatchPath::from_str("ab/⚡/e⚡f/g⚡h/ij.zig");
        assert!(pattern.is_match(&text));
    }
}
