use std::io::{self, BufRead};
use crate::matching::MatchPath;

/// Represents a list of changed files from git diff
pub struct DiffFiles {
    pub files: Vec<MatchPath>,
}

impl DiffFiles {
    /// Read changed files from stdin (output of git diff --name-only)
    pub fn from_stdin() -> io::Result<Self> {
        let stdin = io::stdin();
        let reader = stdin.lock();

        let mut files = Vec::new();

        for line in reader.lines() {
            let line = line?;
            let trimmed = line.trim();

            // Skip empty lines
            if trimmed.is_empty() {
                continue;
            }

            files.push(MatchPath::from_str(trimmed));
        }

        Ok(DiffFiles { files })
    }
}
