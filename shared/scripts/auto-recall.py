#!/usr/bin/env python3
"""
Auto-Recall — Searches all memory layers for context relevant to the user's message.
Extracts key terms, searches files, and outputs matching context.
Target: under 500ms execution time.
"""

import sys
import os
import re
import glob
from pathlib import Path

# Stop words to filter out
STOP_WORDS = {
    'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for',
    'of', 'with', 'by', 'from', 'is', 'are', 'was', 'were', 'be', 'been',
    'being', 'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would',
    'could', 'should', 'may', 'might', 'can', 'shall', 'not', 'no', 'nor',
    'so', 'if', 'then', 'than', 'too', 'very', 'just', 'about', 'up',
    'out', 'how', 'what', 'when', 'where', 'who', 'which', 'why', 'all',
    'each', 'every', 'both', 'few', 'more', 'most', 'other', 'some', 'such',
    'only', 'own', 'same', 'that', 'this', 'these', 'those', 'it', 'its',
    'i', 'me', 'my', 'we', 'us', 'our', 'you', 'your', 'he', 'him', 'his',
    'she', 'her', 'they', 'them', 'their', 'hey', 'hi', 'hello', 'thanks',
    'please', 'okay', 'ok', 'yeah', 'yes', 'no', 'sure', 'right', 'well',
    'now', 'here', 'there', 'also', 'still', 'already', 'again', 'get',
    'got', 'go', 'going', 'gone', 'come', 'came', 'make', 'made', 'take',
    'took', 'give', 'gave', 'tell', 'told', 'say', 'said', 'know', 'knew',
    'think', 'thought', 'see', 'saw', 'want', 'need', 'use', 'used',
    'try', 'let', 'keep', 'set', 'put', 'run', 'look', 'like', 'thing',
    'things', 'way', 'time', 'something', 'anything', 'everything', 'nothing',
    'really', 'actually', 'basically', 'probably', 'maybe', 'definitely'
}

MAX_TERMS = 10
MAX_OUTPUT_LINES = 60
HOME = Path.home()


def extract_terms(prompt: str) -> list[str]:
    """Extract meaningful search terms from the prompt."""
    words = re.findall(r'[a-zA-Z0-9_\-\.]+', prompt.lower())
    terms = [w for w in words if w not in STOP_WORDS and len(w) > 2]
    # Deduplicate while preserving order
    seen = set()
    unique = []
    for t in terms:
        if t not in seen:
            seen.add(t)
            unique.append(t)
    return unique[:MAX_TERMS]


def search_files(paths: list[str], pattern: re.Pattern, max_lines: int) -> list[str]:
    """Search files for matching lines."""
    results = []
    for path_pattern in paths:
        for filepath in sorted(glob.glob(path_pattern, recursive=True)):
            if not os.path.isfile(filepath):
                continue
            try:
                with open(filepath, 'r', errors='ignore') as f:
                    for line in f:
                        line = line.strip()
                        if line and pattern.search(line):
                            # Include source file for context
                            rel = os.path.relpath(filepath, HOME)
                            results.append(f"--- ~/{rel} ---")
                            # Read surrounding context (up to 5 lines before/after match)
                            results.append(line)
                            if len(results) >= max_lines:
                                return results
            except (PermissionError, OSError):
                continue
    return results


def main():
    if len(sys.argv) < 2:
        return

    prompt = ' '.join(sys.argv[1:])
    terms = extract_terms(prompt)

    if not terms:
        return

    # Build case-insensitive regex
    pattern = re.compile('|'.join(re.escape(t) for t in terms), re.IGNORECASE)

    # Define search paths (ordered by priority)
    search_paths = []

    # Layer 1: Knowledge graph summaries
    life_dir = HOME / 'life'
    if life_dir.exists():
        search_paths.append(str(life_dir / '**' / 'summary.md'))
        search_paths.append(str(life_dir / '**' / 'items.json'))

    # Layer 2: Typed memory files
    claude_memory = HOME / '.claude' / 'projects'
    if claude_memory.exists():
        search_paths.append(str(claude_memory / '**' / 'memory' / '*.md'))

    # Layer 3: Session notes (most recent 20)
    sessions_dir = HOME / 'sessions'
    if sessions_dir.exists():
        session_files = sorted(glob.glob(str(sessions_dir / '*.md')), reverse=True)[:20]
        search_paths.extend(session_files)

    # Layer 4: Daily notes (most recent 7)
    memory_dir = HOME / 'memory'
    if memory_dir.exists():
        daily_files = sorted(glob.glob(str(memory_dir / '????-??-??.md')), reverse=True)[:7]
        search_paths.extend(daily_files)

    # Layer 5: Main memory file
    memory_file = HOME / 'memory' / 'MEMORY.md'
    if memory_file.exists():
        search_paths.append(str(memory_file))

    results = search_files(search_paths, pattern, MAX_OUTPUT_LINES)

    if results:
        print("=== AUTO-RECALL ===")
        print(f"Terms: {', '.join(terms)}")
        print()
        # Deduplicate consecutive source headers
        prev_source = None
        for line in results:
            if line.startswith('--- ~/'):
                if line != prev_source:
                    print()
                    print(line)
                    prev_source = line
            else:
                print(line)
        print("=== END AUTO-RECALL ===")


if __name__ == '__main__':
    main()
