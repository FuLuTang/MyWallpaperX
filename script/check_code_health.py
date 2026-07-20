#!/usr/bin/env python3
"""Enforce the Swift file-size ratchet recorded in code_health_baseline.json."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path, PurePosixPath
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
BASELINE_RELATIVE_PATH = Path("script/code_health_baseline.json")
BASELINE_PATH = REPO_ROOT / BASELINE_RELATIVE_PATH


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="validate the current source tree (default)")
    mode.add_argument(
        "--ratchet-baseline",
        action="store_true",
        help="lower or remove existing legacy limits after files shrink",
    )
    parser.add_argument(
        "--base-ref",
        help="Git ref whose baseline must not be expanded (recommended in CI)",
    )
    parser.add_argument("--format", choices=("text", "github"), default="text")
    return parser.parse_args()


def read_baseline_text(text: str, source: str) -> dict[str, Any]:
    try:
        baseline = json.loads(text)
    except json.JSONDecodeError as error:
        raise ValueError(f"{source} is not valid JSON: {error}") from error

    if baseline.get("schemaVersion") != 1:
        raise ValueError(f"{source} must use schemaVersion 1")

    line_limit = baseline.get("lineLimit")
    if not isinstance(line_limit, int) or isinstance(line_limit, bool) or line_limit <= 0:
        raise ValueError(f"{source} lineLimit must be a positive integer")

    source_roots = baseline.get("sourceRoots")
    if (
        not isinstance(source_roots, list)
        or not source_roots
        or any(not isinstance(root, str) or not root for root in source_roots)
        or len(source_roots) != len(set(source_roots))
    ):
        raise ValueError(f"{source} sourceRoots must be a non-empty list of unique paths")
    for root in source_roots:
        validate_repo_relative_path(root, source, expected_suffix=None)

    legacy_files = baseline.get("legacyFiles")
    if not isinstance(legacy_files, dict):
        raise ValueError(f"{source} legacyFiles must be an object")
    for path, allowance in legacy_files.items():
        validate_repo_relative_path(path, source, expected_suffix=".swift")
        if not belongs_to_source_root(path, source_roots):
            raise ValueError(f"{source} legacy path is outside sourceRoots: {path}")
        if not isinstance(allowance, int) or isinstance(allowance, bool) or allowance <= line_limit:
            raise ValueError(f"{source} allowance for {path} must exceed lineLimit")

    return baseline


def validate_repo_relative_path(value: Any, source: str, expected_suffix: str | None) -> None:
    if not isinstance(value, str) or not value:
        raise ValueError(f"{source} contains an invalid repository path: {value!r}")
    path = PurePosixPath(value)
    if path.is_absolute() or path.as_posix() != value or ".." in path.parts or value == ".":
        raise ValueError(f"{source} path must be normalized and repository-relative: {value!r}")
    if expected_suffix is not None and not value.endswith(expected_suffix):
        raise ValueError(f"{source} path must end in {expected_suffix}: {value!r}")


def belongs_to_source_root(path: str, source_roots: list[str]) -> bool:
    path_parts = PurePosixPath(path).parts
    for root in source_roots:
        root_parts = PurePosixPath(root).parts
        if path_parts[: len(root_parts)] == root_parts:
            return True
    return False


def load_current_baseline() -> dict[str, Any]:
    try:
        text = BASELINE_PATH.read_text(encoding="utf-8")
    except OSError as error:
        raise ValueError(f"cannot read {BASELINE_RELATIVE_PATH}: {error}") from error
    return read_baseline_text(text, str(BASELINE_RELATIVE_PATH))


def swift_line_counts(baseline: dict[str, Any]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for relative_root in baseline["sourceRoots"]:
        root = REPO_ROOT / relative_root
        if not root.is_dir():
            raise ValueError(f"configured source root does not exist: {relative_root}")

    result = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "*.swift"],
        cwd=REPO_ROOT,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise ValueError(f"git ls-files failed with exit code {result.returncode}")

    try:
        relative_paths = sorted(
            raw_path.decode("utf-8")
            for raw_path in result.stdout.split(b"\0")
            if raw_path
        )
    except UnicodeDecodeError as error:
        raise ValueError(f"Swift source path is not valid UTF-8: {error}") from error

    unmanaged_paths = [
        path for path in relative_paths if not belongs_to_source_root(path, baseline["sourceRoots"])
    ]
    if unmanaged_paths:
        raise ValueError(
            "Swift files are outside configured sourceRoots: " + ", ".join(unmanaged_paths)
        )

    for relative_path in relative_paths:
        path = REPO_ROOT / relative_path
        if not path.is_file():
            continue
        try:
            counts[relative_path] = len(path.read_text(encoding="utf-8").splitlines())
        except (OSError, UnicodeDecodeError) as error:
            raise ValueError(f"cannot read {relative_path}: {error}") from error
    return dict(sorted(counts.items()))


def current_tree_problems(baseline: dict[str, Any], counts: dict[str, int]) -> list[tuple[str, str]]:
    line_limit = baseline["lineLimit"]
    legacy_files: dict[str, int] = baseline["legacyFiles"]
    problems: list[tuple[str, str]] = []

    for path, allowance in legacy_files.items():
        count = counts.get(path)
        if count is None:
            problems.append((path, "legacy entry is stale because the file no longer exists; ratchet the baseline"))
        elif count <= line_limit:
            problems.append((path, f"file is now {count} lines; remove its legacy entry with --ratchet-baseline"))
        elif count < allowance:
            problems.append(
                (path, f"file shrank from {allowance} to {count} lines; lock in the improvement with --ratchet-baseline")
            )
        elif count > allowance:
            problems.append((path, f"file grew from its locked allowance {allowance} to {count} lines"))

    for path, count in counts.items():
        if count > line_limit and path not in legacy_files:
            problems.append((path, f"new or unbaselined file has {count} lines; limit is {line_limit}"))

    return problems


def baseline_at_ref(base_ref: str) -> tuple[dict[str, Any] | None, str | None]:
    commit_check = subprocess.run(
        ["git", "rev-parse", "--verify", f"{base_ref}^{{commit}}"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if commit_check.returncode != 0:
        raise ValueError(f"base ref is not a commit: {base_ref}")

    result = subprocess.run(
        ["git", "show", f"{base_ref}:{BASELINE_RELATIVE_PATH.as_posix()}"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return None, f"{base_ref} predates the code-health baseline; historical expansion check skipped"
    return read_baseline_text(result.stdout, f"{base_ref}:{BASELINE_RELATIVE_PATH}"), None


def historical_problems(current: dict[str, Any], previous: dict[str, Any]) -> list[tuple[str, str]]:
    problems: list[tuple[str, str]] = []
    baseline_path = BASELINE_RELATIVE_PATH.as_posix()

    if current["lineLimit"] > previous["lineLimit"]:
        problems.append(
            (baseline_path, f"lineLimit increased from {previous['lineLimit']} to {current['lineLimit']}")
        )

    removed_roots = sorted(set(previous["sourceRoots"]) - set(current["sourceRoots"]))
    if removed_roots:
        problems.append((baseline_path, f"source roots cannot be removed: {', '.join(removed_roots)}"))

    previous_legacy: dict[str, int] = previous["legacyFiles"]
    for path, allowance in current["legacyFiles"].items():
        previous_allowance = previous_legacy.get(path)
        if previous_allowance is None:
            problems.append((baseline_path, f"new legacy exception is not allowed: {path}"))
        elif allowance > previous_allowance:
            problems.append(
                (baseline_path, f"legacy allowance for {path} increased from {previous_allowance} to {allowance}")
            )

    return problems


def escape_github(value: str) -> str:
    return value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def emit_problem(path: str, message: str, output_format: str) -> None:
    if output_format == "github":
        print(
            f"::error file={escape_github(path)},line=1,title=Swift file health::{escape_github(message)}"
        )
    else:
        print(f"ERROR {path}: {message}", file=sys.stderr)


def emit_notice(message: str, output_format: str) -> None:
    if output_format == "github":
        print(f"::notice title=Swift file health::{escape_github(message)}")
    else:
        print(f"NOTICE {message}")


def ratchet_baseline(baseline: dict[str, Any], counts: dict[str, int]) -> int:
    line_limit = baseline["lineLimit"]
    legacy_files: dict[str, int] = baseline["legacyFiles"]
    blockers: list[tuple[str, str]] = []

    for path, count in counts.items():
        allowance = legacy_files.get(path)
        if count > line_limit and allowance is None:
            blockers.append((path, f"cannot add a legacy exception for a {count}-line file"))
        elif allowance is not None and count > allowance:
            blockers.append((path, f"cannot ratchet a file that grew from {allowance} to {count} lines"))

    if blockers:
        for path, message in blockers:
            emit_problem(path, message, "text")
        return 1

    updated_legacy = {
        path: counts[path]
        for path in sorted(legacy_files)
        if path in counts and counts[path] > line_limit
    }
    if updated_legacy == legacy_files:
        print("Code-health baseline is already at the current minimum.")
        return 0

    baseline["legacyFiles"] = updated_legacy
    BASELINE_PATH.write_text(json.dumps(baseline, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
    print(f"Ratchet updated: {len(legacy_files)} -> {len(updated_legacy)} legacy files.")
    return 0


def main() -> int:
    arguments = parse_arguments()
    try:
        baseline = load_current_baseline()
        counts = swift_line_counts(baseline)
    except ValueError as error:
        emit_problem(BASELINE_RELATIVE_PATH.as_posix(), str(error), arguments.format)
        return 1

    if arguments.ratchet_baseline:
        if arguments.base_ref:
            emit_problem(BASELINE_RELATIVE_PATH.as_posix(), "--base-ref cannot be used while ratcheting", arguments.format)
            return 2
        return ratchet_baseline(baseline, counts)

    problems = current_tree_problems(baseline, counts)
    if arguments.base_ref:
        try:
            previous, notice = baseline_at_ref(arguments.base_ref)
            if notice:
                emit_notice(notice, arguments.format)
            if previous is not None:
                problems.extend(historical_problems(baseline, previous))
        except ValueError as error:
            problems.append((BASELINE_RELATIVE_PATH.as_posix(), str(error)))

    if problems:
        for path, message in problems:
            emit_problem(path, message, arguments.format)
        return 1

    print(
        f"Code health passed: {len(counts)} Swift files, "
        f"{len(baseline['legacyFiles'])} locked legacy files, {baseline['lineLimit']}-line limit."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
