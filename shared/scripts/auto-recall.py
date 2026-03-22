#!/usr/bin/env python3
"""
Auto-recall: searches all memory layers for context relevant to a message.
Usage: echo '{"message":"..."}' | python3 auto-recall.py
   OR: python3 auto-recall.py "search terms here"

Searches: ~/life/ (knowledge graph), ~/sessions/, ~/memory/ (daily notes),
          typed memories, session summaries, exemplars, and today's JSONL transcripts.

Designed to run fast (<500ms) on every message.
"""

import json
import os
import re
import sys
from pathlib import Path

HOME = Path.home()
MAX_OUTPUT_LINES = 60

STOP_WORDS = frozenset(
    "the a an is are was were be been being have has had do does did will would "
    "could should may might can shall i me my we our you your he him his she her "
    "it its they them their this that these those what which who whom when where "
    "how why if then else so but and or not no yes just also very too really "
    "about with from for on in at to of by up out off over into all any some "
    "more most other each every both few than like want need think know see look "
    "make take get go come let say tell give use find here there now still "
    "already right good great new well way thing something anything been going "
    "doing done said got much many sure yeah hey ok okay thanks thank please hi "
    "hello run check set add update create delete remove change move show list "
    "read write send try start stop keep put help work after before during "
    "between through down back again never always ever yet one two would've "
    "don't doesn't didn't can't won't shouldn't couldn't wouldn't isn't aren't "
    "wasn't weren't haven't hasn't hadn't".split()
)


def extract_terms(text: str) -> list[str]:
    """Extract meaningful search terms from text."""
    words = re.findall(r"[A-Za-z][A-Za-z0-9_.-]*[A-Za-z0-9]|[A-Za-z]", text)
    terms = []
    seen = set()
    for w in words:
        lower = w.lower()
        if lower not in STOP_WORDS and len(w) > 2 and lower not in seen:
            seen.add(lower)
            terms.append(w)
    return terms[:10]


def search_file(path: Path, pattern: re.Pattern) -> list[str]:
    """Return matching lines from a file."""
    try:
        text = path.read_text(errors="replace")
        return [
            line.strip()
            for line in text.splitlines()
            if pattern.search(line)
        ]
    except (OSError, PermissionError):
        return []


def search_knowledge_graph(pattern: re.Pattern) -> list[str]:
    """Search ~/life/ summaries and items."""
    results = []
    life_dir = HOME / "life"
    if not life_dir.exists():
        return results

    for summary in life_dir.rglob("summary.md"):
        try:
            content = summary.read_text(errors="replace")
            if pattern.search(content):
                entity = str(summary.parent.relative_to(life_dir))
                lines = content.strip().splitlines()[:15]
                results.append(f"--- ~/life/{entity} ---")
                results.extend(lines)
                results.append("")
        except (OSError, PermissionError):
            continue

    for items_file in life_dir.rglob("items.json"):
        try:
            items = json.loads(items_file.read_text())
            entity = str(items_file.parent.relative_to(life_dir))
            matching_facts = [
                f"  - {item['fact']}"
                for item in items
                if isinstance(item, dict) and pattern.search(item.get("fact", ""))
            ][:5]
            if matching_facts:
                results.append(f"--- ~/life/{entity} (facts) ---")
                results.extend(matching_facts)
                results.append("")
        except (OSError, PermissionError, json.JSONDecodeError):
            continue

    return results


def search_sessions(pattern: re.Pattern) -> list[str]:
    """Search ~/sessions/ for relevant session notes."""
    results = []
    sessions_dir = HOME / "sessions"
    if not sessions_dir.exists():
        return results

    for f in sorted(sessions_dir.glob("*.md"), reverse=True)[:20]:
        try:
            content = f.read_text(errors="replace")
            if pattern.search(content):
                lines = content.strip().splitlines()[:8]
                results.append(f"--- ~/sessions/{f.name} ---")
                results.extend(lines)
                results.append("")
        except (OSError, PermissionError):
            continue

    return results


def search_session_summaries(pattern: re.Pattern) -> list[str]:
    """Search session summaries for relevant past conversations."""
    results = []
    # Check common locations for session summaries
    for summaries_dir in [
        HOME / ".agent" / "session-summaries",
        HOME / ".maia" / "session-summaries",
    ]:
        if not summaries_dir.exists():
            continue

        for f in sorted(summaries_dir.glob("*.md"), reverse=True)[:14]:
            try:
                content = f.read_text(errors="replace")
                if not pattern.search(content):
                    continue
                lines = content.splitlines()
                matching_blocks = []
                for i, line in enumerate(lines):
                    if pattern.search(line):
                        start = i
                        for j in range(i, max(i - 10, -1), -1):
                            if lines[j].startswith("####"):
                                start = j
                                break
                        end = min(i + 3, len(lines))
                        block = lines[start:end]
                        matching_blocks.append("\n".join(block))
                        if len(matching_blocks) >= 3:
                            break
                if matching_blocks:
                    results.append(f"--- session-summaries/{f.name} ---")
                    results.extend(matching_blocks)
                    results.append("")
            except (OSError, PermissionError):
                continue

    return results


def search_daily_notes(pattern: re.Pattern) -> list[str]:
    """Search ~/memory/ daily notes."""
    results = []
    memory_dir = HOME / "memory"
    if not memory_dir.exists():
        return results

    for f in sorted(memory_dir.glob("*.md"), reverse=True)[:7]:
        matches = search_file(f, pattern)
        if matches:
            results.append(f"--- ~/memory/{f.name} ---")
            results.extend(f"  {m}" for m in matches[:5])
            results.append("")

    return results


def search_typed_memories(pattern: re.Pattern) -> list[str]:
    """Search typed memory files (Claude Code's structured memories)."""
    results = []
    # Search all project memory directories
    claude_projects = HOME / ".claude" / "projects"
    if not claude_projects.exists():
        return results

    for mem_dir in claude_projects.rglob("memory"):
        if not mem_dir.is_dir():
            continue
        for f in mem_dir.glob("*.md"):
            if f.name == "MEMORY.md":
                continue  # Already loaded every session
            try:
                content = f.read_text(errors="replace")
                if pattern.search(content):
                    lines = content.strip().splitlines()[:15]
                    results.append(f"--- memory/{f.name} ---")
                    results.extend(lines)
                    results.append("")
            except (OSError, PermissionError):
                continue

    return results


def search_exemplars(pattern: re.Pattern) -> list[str]:
    """Search exemplar patterns for relevant task trajectories."""
    results = []
    exemplars_dir = HOME / ".claude" / "skills" / "exemplars"
    if not exemplars_dir.exists():
        return results

    for f in exemplars_dir.glob("*.md"):
        if f.name == "SKILL.md":
            continue
        try:
            content = f.read_text(errors="replace")
            if pattern.search(content):
                lines = content.strip().splitlines()[:20]
                results.append(f"--- exemplar/{f.name} ---")
                results.extend(lines)
                results.append("")
        except (OSError, PermissionError):
            continue

    return results


def search_todays_jsonl(pattern: re.Pattern) -> list[str]:
    """Search today's raw JSONL transcripts for same-day context not yet summarized."""
    results = []
    from datetime import date
    today = date.today().isoformat()

    # Check common locations for JSONL transcripts
    for jsonl_dir in [
        HOME / ".claude" / "projects",
    ]:
        if not jsonl_dir.exists():
            continue

        # Check if today's summary already exists — skip raw JSONL if so
        for summaries_dir in [
            HOME / ".agent" / "session-summaries",
            HOME / ".maia" / "session-summaries",
        ]:
            summary_file = summaries_dir / f"{today}.md"
            if summary_file.exists():
                return results

        for subdir in jsonl_dir.iterdir():
            if not subdir.is_dir():
                continue
            for f in subdir.glob("*.jsonl"):
                try:
                    mtime = date.fromtimestamp(f.stat().st_mtime)
                    if mtime.isoformat() != today:
                        continue
                    matching_messages = []
                    for line in f.open(errors="replace"):
                        try:
                            entry = json.loads(line)
                        except json.JSONDecodeError:
                            continue
                        if entry.get("type") not in ("user", "assistant"):
                            continue
                        msg = entry.get("message", {})
                        content = msg.get("content", "")
                        if isinstance(content, list):
                            content = " ".join(
                                c.get("text", "") for c in content if isinstance(c, dict)
                            )
                        if isinstance(content, str) and pattern.search(content):
                            snippet = content[:200].replace("\n", " ")
                            role = entry["type"].capitalize()
                            matching_messages.append(f"  {role}: {snippet}")
                            if len(matching_messages) >= 5:
                                break
                    if matching_messages:
                        results.append(f"--- today's session ({f.stem[:8]}...) ---")
                        results.extend(matching_messages)
                        results.append("")
                except (OSError, PermissionError):
                    continue

    return results


def main():
    # Get message from stdin JSON or CLI argument
    message = ""
    if len(sys.argv) > 1:
        message = " ".join(sys.argv[1:])
    elif not sys.stdin.isatty():
        try:
            data = json.load(sys.stdin)
            message = data.get("message", data.get("prompt", data.get("content", "")))
            if isinstance(message, list):
                message = " ".join(str(m) for m in message)
        except (json.JSONDecodeError, AttributeError):
            # Try reading as plain text
            sys.stdin.seek(0)
            message = sys.stdin.read().strip()

    if not message:
        return

    terms = extract_terms(message)
    if not terms:
        return

    # Build case-insensitive pattern
    escaped = [re.escape(t) for t in terms]
    pattern = re.compile("|".join(escaped), re.IGNORECASE)

    # Search all layers
    all_results = []
    all_results.extend(search_knowledge_graph(pattern))
    all_results.extend(search_session_summaries(pattern))
    all_results.extend(search_sessions(pattern))
    all_results.extend(search_daily_notes(pattern))
    all_results.extend(search_typed_memories(pattern))
    all_results.extend(search_exemplars(pattern))
    all_results.extend(search_todays_jsonl(pattern))

    if all_results:
        output = ["=== AUTO-RECALL ===", f"Terms: {', '.join(terms)}", ""]
        output.extend(all_results[:MAX_OUTPUT_LINES])
        output.append("=== END AUTO-RECALL ===")
        print("\n".join(output))


if __name__ == "__main__":
    main()
