#!/usr/bin/env python3
"""Benchmark MyWallpaperX Web wallpaper runtime capability.

The tool launches the Debug app against installed Workshop Web samples, parses
the existing MWX WEB DIAG log stream, scores each capability dimension, and
writes JSON/Markdown reports that can be compared over time.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from dataclasses import asdict, dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_WORKSHOP_ROOT = Path.home() / "Movies/MyWallpaperX/创意工坊"
DEFAULT_DERIVED_DATA = REPO_ROOT / ".codex/DerivedData"
DEFAULT_APP_BINARY = (
    DEFAULT_DERIVED_DATA
    / "Build/Products/Debug/MyWallpaperX.app/Contents/MacOS/MyWallpaperX"
)
APP_NAME = "MyWallpaperX"

DIAG_RE = re.compile(
    r"MWX WEB DIAG record=(?P<record>\S+) screen=(?P<screen>\S+) "
    r"severity=(?P<severity>\S+) type=(?P<type>\S+) "
    r"url=(?P<url>\S+) message=(?P<message>.*)$"
)
DEBUG_LAUNCH_RE = re.compile(
    r"MWX DEBUG PLAY: launching workshop item (?P<id>\S+) type=(?P<type>\S+)"
)
PRECONDITION_RE = re.compile(
    r"MWX DEBUG PLAY: workshop item (?P<id>\S+) precondition=(?P<precondition>\S+)"
)
SNAPSHOT_RE = re.compile(
    r"webSnapshot\[(?P<reason>[^\]]+)\] size=(?P<size>\S+) "
    r"avgLuma=(?P<avg>[0-9.]+) nonBlack=(?P<nonblack>[0-9.]+)"
    r"(?: lumaStdDev=(?P<stddev>[0-9.]+) colored=(?P<colored>[0-9.]+) white=(?P<white>[0-9.]+))?"
)
TIMESTAMP_RE = re.compile(r"^(?P<stamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d+)?)")
RAW_RUNTIME_ERROR_TOKENS = (
    "request to run javascript failed",
    "run javascript failed",
    "javascript exception",
    "uncaught ",
    "syntaxerror",
    "referenceerror",
    "typeerror",
    "failed to load resource",
    "not allowed to load local resource",
    "web process terminated",
    "webcontent process terminated",
)


@dataclass
class Sample:
    id: str
    path: str | None = None
    title: str | None = None
    reason: str = "manual"


@dataclass
class DiagnosticEvent:
    type: str
    severity: str
    message: str
    url: str | None
    line: str
    seconds_from_start: float | None = None


@dataclass
class DimensionScore:
    name: str
    score: float
    weight: float
    status: str
    evidence: str
    findings: list[str] = field(default_factory=list)


@dataclass
class SampleResult:
    sample: Sample
    score: float
    grade: str
    coverage: float
    dimensions: list[DimensionScore]
    findings: list[str]
    shortfall_categories: list[str]
    log_path: str
    screenshot_path: str | None
    web_snapshot_paths: list[str]
    process_exit_code: int | None
    duration_seconds: float
    event_counts: dict[str, int]
    diagnostic_warnings: list[str]
    diagnostic_errors: list[str]
    raw_error_lines: list[str]


def run_command(command: list[str], cwd: Path, log_path: Path | None = None) -> None:
    if log_path:
        with log_path.open("w", encoding="utf-8") as handle:
            subprocess.run(command, cwd=cwd, stdout=handle, stderr=subprocess.STDOUT, check=True)
        return
    subprocess.run(command, cwd=cwd, check=True)


def build_debug_app(derived_data: Path, log_path: Path) -> None:
    command = [
        "/usr/bin/xcodebuild",
        "-project",
        str(REPO_ROOT / "MyWallpaperX.xcodeproj"),
        "-scheme",
        "MyWallpaperX",
        "-configuration",
        "Debug",
        "-derivedDataPath",
        str(derived_data),
        "CODE_SIGNING_ALLOWED=NO",
        "build",
    ]
    run_command(command, REPO_ROOT, log_path)


def load_project_json(project_path: Path) -> dict[str, Any] | None:
    try:
        return json.loads(project_path.read_text(encoding="utf-8"))
    except Exception:
        return None


def project_declares_web(project: dict[str, Any]) -> tuple[bool, str]:
    project_type = str(project.get("type", "")).lower()
    file_value = str(project.get("file", ""))
    dependency = project.get("dependency")
    if project_type == "web":
        return True, "project.type=web"
    if file_value.lower().endswith((".html", ".htm")):
        return True, "project.file=html"
    if dependency:
        return True, "dependency-backed shell"
    return False, "not web"


def discover_samples(workshop_root: Path) -> list[Sample]:
    samples: list[Sample] = []
    if not workshop_root.exists():
        return samples
    for project_path in sorted(workshop_root.rglob("project.json")):
        project = load_project_json(project_path)
        if not project:
            continue
        is_web, reason = project_declares_web(project)
        if not is_web:
            continue
        sample_id = project_path.parent.name
        if not sample_id:
            continue
        title = project.get("title")
        samples.append(
            Sample(
                id=sample_id,
                path=str(project_path.parent),
                title=str(title) if title else None,
                reason=reason,
            )
        )
    return samples


def parse_timestamp(line: str) -> datetime | None:
    match = TIMESTAMP_RE.search(line)
    if not match:
        return None
    stamp = match.group("stamp")
    for fmt in ("%Y-%m-%d %H:%M:%S.%f", "%Y-%m-%d %H:%M:%S"):
        try:
            return datetime.strptime(stamp, fmt)
        except ValueError:
            continue
    return None


def is_raw_runtime_error(line: str) -> bool:
    lowered = line.lower()
    return any(token in lowered for token in RAW_RUNTIME_ERROR_TOKENS)


def parse_log(log_path: Path) -> tuple[list[DiagnosticEvent], dict[str, Any]]:
    events: list[DiagnosticEvent] = []
    metadata: dict[str, Any] = {
        "debug_launch_type": None,
        "item_not_found": False,
        "precondition": None,
        "snapshots": [],
        "raw_error_lines": [],
    }
    first_timestamp: datetime | None = None

    if not log_path.exists():
        return events, metadata

    for line in log_path.read_text(encoding="utf-8", errors="replace").splitlines():
        timestamp = parse_timestamp(line)
        if timestamp and first_timestamp is None:
            first_timestamp = timestamp
        seconds_from_start = None
        if timestamp and first_timestamp:
            seconds_from_start = (timestamp - first_timestamp).total_seconds()

        launch_match = DEBUG_LAUNCH_RE.search(line)
        if launch_match:
            metadata["debug_launch_type"] = launch_match.group("type").strip()

        if "MWX DEBUG PLAY: workshop item" in line and "not found" in line:
            metadata["item_not_found"] = True

        precondition_match = PRECONDITION_RE.search(line)
        if precondition_match:
            metadata["precondition"] = precondition_match.group("precondition")

        snapshot_match = SNAPSHOT_RE.search(line)
        if snapshot_match:
            metadata["snapshots"].append(
                {
                    "reason": snapshot_match.group("reason"),
                    "size": snapshot_match.group("size"),
                    "avgLuma": float(snapshot_match.group("avg")),
                    "nonBlack": float(snapshot_match.group("nonblack")),
                    "lumaStdDev": (
                        float(snapshot_match.group("stddev"))
                        if snapshot_match.group("stddev") is not None
                        else None
                    ),
                    "colored": (
                        float(snapshot_match.group("colored"))
                        if snapshot_match.group("colored") is not None
                        else None
                    ),
                    "white": (
                        float(snapshot_match.group("white"))
                        if snapshot_match.group("white") is not None
                        else None
                    ),
                }
            )

        diag_match = DIAG_RE.search(line)
        if diag_match:
            url = diag_match.group("url")
            if url == "-":
                url = None
            events.append(
                DiagnosticEvent(
                    type=diag_match.group("type"),
                    severity=diag_match.group("severity"),
                    message=diag_match.group("message"),
                    url=url,
                    line=line,
                    seconds_from_start=seconds_from_start,
                )
            )
            continue

        if is_raw_runtime_error(line):
            metadata["raw_error_lines"].append(line[-500:])

    return events, metadata


def count_by_type(events: Iterable[DiagnosticEvent]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for event in events:
        counts[event.type] = counts.get(event.type, 0) + 1
    return dict(sorted(counts.items()))


def has_event(events: list[DiagnosticEvent], event_type: str) -> bool:
    return any(event.type == event_type for event in events)


def event_time(events: list[DiagnosticEvent], event_type: str) -> float | None:
    for event in events:
        if event.type == event_type:
            return event.seconds_from_start
    return None


def events_matching(events: list[DiagnosticEvent], prefixes: tuple[str, ...]) -> list[DiagnosticEvent]:
    return [event for event in events if event.type.startswith(prefixes)]


def classify_sample_resource_noise(event: DiagnosticEvent) -> bool:
    message = event.message.lower()
    url = (event.url or "").lower()
    known_optional_names = (
        "background.png",
        "placeholder.png",
        "face-5.jpg",
        "null",
        "google",
        "fonts",
        "cdn",
        "http",
    )
    return any(name in message or name in url for name in known_optional_names)


def score_sample(
    sample: Sample,
    events: list[DiagnosticEvent],
    metadata: dict[str, Any],
    log_path: Path,
    screenshot_path: Path | None,
    web_snapshot_paths: list[Path],
    exit_code: int | None,
    duration_seconds: float,
) -> SampleResult:
    counts = count_by_type(events)
    diagnostic_warnings = [
        event.line[-500:]
        for event in events
        if event.severity.lower() == "warning"
    ]
    diagnostic_errors = [
        event.line[-500:]
        for event in events
        if event.severity.lower() == "error"
    ]
    raw_error_lines = list(metadata.get("raw_error_lines") or [])[-80:]
    precondition = metadata.get("precondition")
    if precondition:
        return SampleResult(
            sample=sample,
            score=0,
            grade="N/A",
            coverage=0,
            dimensions=[],
            findings=[f"Not run: required Workshop precondition is {precondition}."],
            shortfall_categories=["precondition"],
            log_path=str(log_path),
            screenshot_path=str(screenshot_path) if screenshot_path else None,
            web_snapshot_paths=[str(path) for path in web_snapshot_paths],
            process_exit_code=exit_code,
            duration_seconds=round(duration_seconds, 2),
            event_counts=counts,
            diagnostic_warnings=diagnostic_warnings,
            diagnostic_errors=diagnostic_errors,
            raw_error_lines=raw_error_lines,
        )
    findings: list[str] = []
    categories: set[str] = set()
    dimensions: list[DimensionScore] = []

    runtime_profile = has_event(events, "runtime.profile")
    host_ready = has_event(events, "host.ready")
    navigation_finish = has_event(events, "navigation.finish")
    host_ready_time = event_time(events, "host.ready")
    navigation_time = event_time(events, "navigation.finish")

    launch_score = 0.0
    launch_findings: list[str] = []
    launch_type = metadata.get("debug_launch_type")
    if metadata.get("item_not_found"):
        launch_findings.append("App did not find this Workshop record.")
        categories.add("launch")
    if launch_type:
        if "web" in str(launch_type).lower():
            launch_score += 5
        else:
            launch_findings.append(f"Debug launch type was {launch_type}, not web.")
            categories.add("launch")
    elif not metadata.get("item_not_found"):
        launch_score += 2
        launch_findings.append("Debug launch line was not observed.")
    if runtime_profile:
        launch_score += 8
    else:
        launch_findings.append("Missing runtime.profile.")
        categories.add("launch")
    if exit_code not in (None, 0, -15, -9):
        launch_findings.append(f"Process exited unexpectedly with code {exit_code}.")
        categories.add("host_runtime")
    else:
        launch_score += 2
    dimensions.append(
        DimensionScore(
            name="launch_classification",
            score=min(15, launch_score),
            weight=15,
            status="pass" if launch_score >= 13 else "fail",
            evidence="strong" if runtime_profile else "weak",
            findings=launch_findings,
        )
    )

    ready_score = 0.0
    ready_findings: list[str] = []
    if host_ready:
        ready_score += 14
        if host_ready_time is None:
            ready_score += 3
        elif host_ready_time <= 5:
            ready_score += 6
        elif host_ready_time <= 10:
            ready_score += 4
            ready_findings.append(f"host.ready was slow: {host_ready_time:.1f}s.")
            categories.add("performance")
        else:
            ready_score += 2
            ready_findings.append(f"host.ready exceeded 10s: {host_ready_time:.1f}s.")
            categories.add("performance")
    else:
        ready_findings.append("Missing host.ready.")
        categories.add("host_runtime")
    dimensions.append(
        DimensionScore(
            name="host_ready_performance",
            score=min(20, ready_score),
            weight=20,
            status="pass" if ready_score >= 16 else "fail",
            evidence="strong" if host_ready else "weak",
            findings=ready_findings,
        )
    )

    nav_score = 0.0
    nav_findings: list[str] = []
    nav_failures = events_matching(events, ("navigation.fail", "navigation.error"))
    if navigation_finish:
        nav_score += 12
        if navigation_time is None or navigation_time <= 10:
            nav_score += 3
        else:
            nav_score += 1
            nav_findings.append(f"navigation.finish was slow: {navigation_time:.1f}s.")
            categories.add("performance")
    elif host_ready:
        nav_score += 8
        nav_findings.append("host.ready was observed, but navigation.finish was missing in the window.")
        categories.add("navigation")
    else:
        nav_findings.append("No navigation.finish evidence.")
        categories.add("navigation")
    if nav_failures:
        nav_score = max(0, nav_score - 6)
        nav_findings.append(f"{len(nav_failures)} navigation failure event(s).")
        categories.add("navigation")
    dimensions.append(
        DimensionScore(
            name="navigation_lifecycle",
            score=min(15, nav_score),
            weight=15,
            status="pass" if nav_score >= 12 else "warn" if nav_score >= 8 else "fail",
            evidence="strong" if navigation_finish else "medium" if host_ready else "weak",
            findings=nav_findings,
        )
    )

    resource_events = events_matching(
        events,
        (
            "resource.error",
            "local-resource-error",
            "local-resource-deny",
            "loopback.resource.error",
            "fetch.error",
        ),
    )
    resource_score = 15.0
    resource_findings: list[str] = []
    host_resource_events = [event for event in resource_events if not classify_sample_resource_noise(event)]
    sample_noise_events = [event for event in resource_events if classify_sample_resource_noise(event)]
    if host_resource_events:
        penalty = min(12, 4 * len(host_resource_events))
        resource_score -= penalty
        resource_findings.append(f"{len(host_resource_events)} likely host resource mapping issue(s).")
        categories.add("resource_mapping")
    if sample_noise_events:
        penalty = min(4, len(sample_noise_events))
        resource_score -= penalty
        resource_findings.append(f"{len(sample_noise_events)} sample/remote optional resource issue(s).")
        categories.add("sample_resource")
    dimensions.append(
        DimensionScore(
            name="resource_compatibility",
            score=max(0, resource_score),
            weight=15,
            status="pass" if resource_score >= 13 else "warn" if resource_score >= 8 else "fail",
            evidence="strong" if runtime_profile else "weak",
            findings=resource_findings,
        )
    )

    property_events = events_matching(events, ("properties.",))
    property_errors = [
        event
        for event in property_events
        if event.severity == "error" or event.type in {"properties.error", "properties.skipped", "properties.applied.partial"}
    ]
    property_info_recoveries = [
        event for event in property_events if event.type == "properties.resize-after-script-failure"
    ]
    property_score = 15.0
    property_findings: list[str] = []
    if property_errors:
        property_score -= min(12, 5 * len(property_errors))
        property_findings.append(f"{len(property_errors)} property bridge error event(s).")
        categories.add("properties")
    if property_info_recoveries:
        property_score -= 1
        property_findings.append("Renderer refresh after sample script failure was needed.")
    dimensions.append(
        DimensionScore(
            name="property_bridge",
            score=max(0, property_score),
            weight=15,
            status="pass" if property_score >= 13 else "warn" if property_score >= 8 else "fail",
            evidence="strong" if property_events else "medium",
            findings=property_findings,
        )
    )

    media_events = events_matching(events, ("media.", "audio."))
    media_errors = [
        event
        for event in media_events
        if event.type in {"media.error", "media.play.error", "audio.resume.error"}
        or event.severity == "error"
    ]
    media_score = 8.0
    media_findings: list[str] = []
    media_evidence = "strong" if media_events else "weak"
    if media_errors:
        media_score -= min(8, 3 * len(media_errors))
        media_findings.append(f"{len(media_errors)} media/audio error event(s).")
        categories.add("media_audio")
    elif not media_events:
        media_score = 6.0
        media_findings.append("No media/audio events observed; capability not actively covered.")
    dimensions.append(
        DimensionScore(
            name="media_audio",
            score=max(0, media_score),
            weight=8,
            status="pass" if media_score >= 7 else "warn" if media_score >= 5 else "fail",
            evidence=media_evidence,
            findings=media_findings,
        )
    )

    pointer_events = events_matching(events, ("pointer.", "wheel."))
    pointer_errors = [event for event in pointer_events if "error" in event.type or event.severity == "error"]
    interaction_smoke = has_event(events, "evidence.interaction")
    interaction_smoke_error = has_event(events, "evidence.interaction.error")
    pointer_down = has_event(events, "pointer.down")
    pointer_up = has_event(events, "pointer.up")
    interaction_score = 7.0
    interaction_findings: list[str] = []
    interaction_evidence = "weak"
    if pointer_errors or interaction_smoke_error:
        input_error_count = len(pointer_errors) + int(interaction_smoke_error)
        interaction_score -= min(7, 4 * input_error_count)
        interaction_findings.append(f"{input_error_count} input dispatch error event(s).")
        categories.add("interaction")
    elif interaction_smoke and pointer_down and pointer_up:
        interaction_evidence = "strong"
    elif interaction_smoke:
        interaction_score = 4.0
        interaction_evidence = "medium"
        interaction_findings.append("Synthetic interaction completed, but pointer down/up receipt was incomplete.")
        categories.add("interaction")
    elif pointer_events:
        interaction_score = 3.0
        interaction_evidence = "medium"
        interaction_findings.append("Passive pointer events were observed without a complete interaction smoke sequence.")
        categories.add("interaction")
    else:
        interaction_score = 1.0
        interaction_findings.append("No pointer/click/drag/wheel interaction evidence was collected.")
        categories.add("interaction")
    dimensions.append(
        DimensionScore(
            name="interaction",
            score=max(0, interaction_score),
            weight=7,
            status="pass" if interaction_score >= 6 else "warn" if interaction_score >= 4 else "fail",
            evidence=interaction_evidence,
            findings=interaction_findings,
        )
    )

    snapshots = metadata.get("snapshots") or []
    dom_evidence = has_event(events, "evidence.dom")
    dom_errors = events_matching(events, ("evidence.dom.error",))
    visual_score = 0.0
    visual_findings: list[str] = []
    visual_evidence = "weak"
    complete_snapshots = [snapshot for snapshot in snapshots if snapshot.get("lumaStdDev") is not None]
    if complete_snapshots and web_snapshot_paths and dom_evidence and not dom_errors:
        visual_evidence = "strong"
        meaningful_snapshots = [
            snapshot
            for snapshot in complete_snapshots
            if float(snapshot["nonBlack"]) >= 0.02
            and float(snapshot["white"]) < 0.98
            and (float(snapshot["lumaStdDev"]) >= 0.01 or float(snapshot["colored"]) >= 0.02)
        ]
        if meaningful_snapshots:
            visual_score = 5.0
        else:
            visual_score = 0.0
            best = max(complete_snapshots, key=lambda snapshot: float(snapshot["lumaStdDev"]))
            visual_findings.append(
                "Snapshot looked uniform/empty: "
                f"nonBlack={float(best['nonBlack']):.3f}, "
                f"lumaStdDev={float(best['lumaStdDev']):.3f}, "
                f"colored={float(best['colored']):.3f}, white={float(best['white']):.3f}."
            )
            categories.add("visual_output")
    elif snapshots and web_snapshot_paths:
        visual_score = 3.0
        visual_evidence = "medium"
        visual_findings.append("WebView snapshot exists, but DOM evidence is missing or failed.")
        categories.add("visual_output")
    elif snapshots:
        visual_score = 1.0
        visual_findings.append("Snapshot metrics were logged without a saved WebView image artifact.")
        categories.add("visual_output")
    else:
        visual_findings.append("No WebView snapshot or DOM evidence was collected; host readiness is not visual proof.")
        categories.add("visual_output")
    dimensions.append(
        DimensionScore(
            name="visual_output",
            score=visual_score,
            weight=5,
            status="pass" if visual_score >= 4 else "warn" if visual_score >= 2 else "fail",
            evidence=visual_evidence,
            findings=visual_findings,
        )
    )

    for dimension in dimensions:
        findings.extend(dimension.findings)

    weighted_score = sum(dimension.score for dimension in dimensions)
    evidence_weights = {"strong": 1.0, "medium": 0.7, "weak": 0.35}
    coverage = (
        sum(dimension.weight * evidence_weights.get(dimension.evidence, 0.35) for dimension in dimensions)
        / sum(dimension.weight for dimension in dimensions)
        * 100
    )

    if weighted_score >= 90:
        grade = "A"
    elif weighted_score >= 80:
        grade = "B"
    elif weighted_score >= 70:
        grade = "C"
    elif weighted_score >= 60:
        grade = "D"
    else:
        grade = "F"

    grade_rank = {"A": 4, "B": 3, "C": 2, "D": 1, "F": 0}
    critical_dimensions = [
        dimension for dimension in dimensions if dimension.name in {"interaction", "visual_output"}
    ]
    grade_cap = "A"
    if any(dimension.status == "fail" for dimension in critical_dimensions):
        grade_cap = "C"
    elif any(dimension.status == "warn" for dimension in critical_dimensions):
        grade_cap = "B"
    if grade_rank[grade] > grade_rank[grade_cap]:
        findings.append(f"Grade capped at {grade_cap}: critical interaction/visual evidence is incomplete.")
        grade = grade_cap

    return SampleResult(
        sample=sample,
        score=round(weighted_score, 1),
        grade=grade,
        coverage=round(coverage, 1),
        dimensions=dimensions,
        findings=findings[:20],
        shortfall_categories=sorted(categories),
        log_path=str(log_path),
        screenshot_path=str(screenshot_path) if screenshot_path else None,
        web_snapshot_paths=[str(path) for path in web_snapshot_paths],
        process_exit_code=exit_code,
        duration_seconds=round(duration_seconds, 2),
        event_counts=counts,
        diagnostic_warnings=diagnostic_warnings,
        diagnostic_errors=diagnostic_errors,
        raw_error_lines=raw_error_lines,
    )


def terminate_process(process: subprocess.Popen[Any]) -> int | None:
    if process.poll() is not None:
        return process.returncode
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return process.poll()
    except Exception:
        process.terminate()
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except Exception:
            process.kill()
        process.wait(timeout=3)
    return process.returncode


def kill_existing_app() -> None:
    subprocess.run(["/usr/bin/pkill", "-x", APP_NAME], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def capture_screenshot(path: Path) -> None:
    if shutil.which("screencapture") is None:
        return
    subprocess.run(["/usr/sbin/screencapture", "-x", str(path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def start_unified_log_capture(handle: Any) -> subprocess.Popen[Any]:
    return subprocess.Popen(
        [
            "/usr/bin/log",
            "stream",
            "--style",
            "compact",
            "--level",
            "debug",
            "--predicate",
            f'process == "{APP_NAME}"',
        ],
        stdout=handle,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )


def run_one_sample(
    app_binary: Path,
    sample: Sample,
    output_dir: Path,
    duration: float,
    capture_screen: bool,
    kill_existing: bool,
    runtime_workshop_root: Path | None,
    runtime_home: Path | None,
) -> SampleResult:
    sample_dir = output_dir / sample.id
    sample_dir.mkdir(parents=True, exist_ok=True)
    log_path = sample_dir / "app.log"
    screenshot_path = sample_dir / "screen.png" if capture_screen else None

    if kill_existing:
        kill_existing_app()

    command = [
        str(app_binary),
        "--mwx-debug-suppress-main-window",
        "--mwx-log-web-diagnostics",
        "--mwx-debug-run-web-workshop-id",
        sample.id,
        "--mwx-debug-web-evidence-dir",
        str(sample_dir),
    ]
    if runtime_workshop_root:
        command.extend(["--mwx-debug-workshop-root", str(runtime_workshop_root)])

    environment = os.environ.copy()
    if runtime_home:
        sample_home = runtime_home / sample.id
        sample_home.mkdir(parents=True, exist_ok=True)
        environment["HOME"] = str(sample_home)
        environment["CFFIXED_USER_HOME"] = str(sample_home)

    started = time.monotonic()
    with log_path.open("w", encoding="utf-8") as handle:
        log_process = start_unified_log_capture(handle)
        process: subprocess.Popen[Any] | None = None
        exit_code: int | None = None
        try:
            time.sleep(0.25)
            process = subprocess.Popen(
                command,
                cwd=REPO_ROOT,
                stdout=handle,
                stderr=subprocess.STDOUT,
                env=environment,
                start_new_session=True,
            )
            time.sleep(duration)
            if screenshot_path:
                capture_screenshot(screenshot_path)
        finally:
            if process is not None:
                exit_code = terminate_process(process)
            terminate_process(log_process)
    elapsed = time.monotonic() - started

    events, metadata = parse_log(log_path)
    web_snapshot_paths = sorted(sample_dir.glob("web-snapshot-*.png"))
    return score_sample(
        sample,
        events,
        metadata,
        log_path,
        screenshot_path,
        web_snapshot_paths,
        exit_code,
        elapsed,
    )


def compare_with_baseline(results: list[SampleResult], baseline_path: Path | None) -> dict[str, Any] | None:
    if not baseline_path:
        return None
    try:
        baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
    except Exception as error:
        return {"error": f"failed to read baseline: {error}"}

    previous = {
        item["sample"]["id"]: item
        for item in baseline.get("samples", [])
        if isinstance(item, dict) and isinstance(item.get("sample"), dict)
    }
    deltas = []
    for result in results:
        old = previous.get(result.sample.id)
        if not old:
            deltas.append({"id": result.sample.id, "status": "new", "score": result.score})
            continue
        old_score = float(old.get("score", 0))
        delta = round(result.score - old_score, 1)
        if abs(delta) >= 0.1:
            deltas.append(
                {
                    "id": result.sample.id,
                    "status": "changed",
                    "old_score": old_score,
                    "new_score": result.score,
                    "delta": delta,
                }
            )
    return {"baseline": str(baseline_path), "deltas": deltas}


def summarize(results: list[SampleResult], comparison: dict[str, Any] | None) -> dict[str, Any]:
    if not results:
        return {
            "sample_count": 0,
            "runnable_sample_count": 0,
            "precondition_count": 0,
            "average_score": 0,
            "average_coverage": 0,
            "grade_counts": {},
            "category_counts": {},
            "comparison": comparison,
        }

    grade_counts: dict[str, int] = {}
    category_counts: dict[str, int] = {}
    for result in results:
        grade_counts[result.grade] = grade_counts.get(result.grade, 0) + 1
        for category in result.shortfall_categories:
            category_counts[category] = category_counts.get(category, 0) + 1
    runnable_results = [result for result in results if result.grade != "N/A"]
    return {
        "sample_count": len(results),
        "runnable_sample_count": len(runnable_results),
        "precondition_count": len(results) - len(runnable_results),
        "average_score": round(sum(result.score for result in runnable_results) / len(runnable_results), 1) if runnable_results else 0,
        "average_coverage": round(sum(result.coverage for result in runnable_results) / len(runnable_results), 1) if runnable_results else 0,
        "grade_counts": dict(sorted(grade_counts.items())),
        "category_counts": dict(sorted(category_counts.items())),
        "comparison": comparison,
    }


def write_json_report(output_dir: Path, args: argparse.Namespace, results: list[SampleResult], summary: dict[str, Any]) -> Path:
    report = {
        "schema_version": 3,
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "repo_root": str(REPO_ROOT),
        "command": vars(args),
        "summary": summary,
        "samples": [asdict(result) for result in results],
    }
    report_path = output_dir / "report.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    return report_path


def write_markdown_report(output_dir: Path, results: list[SampleResult], summary: dict[str, Any]) -> Path:
    lines = [
        "# MyWallpaperX Web Wallpaper Benchmark",
        "",
        f"- Generated: {datetime.now().isoformat(timespec='seconds')}",
        f"- Samples: {summary['sample_count']}",
        f"- Runnable samples: {summary['runnable_sample_count']}",
        f"- Precondition skips: {summary['precondition_count']}",
        f"- Average score: {summary['average_score']}",
        f"- Average evidence coverage: {summary['average_coverage']}%",
        f"- Grades: {summary['grade_counts']}",
        f"- Shortfall categories: {summary['category_counts']}",
        "",
        "## Samples",
        "",
        "| ID | Score | Grade | Coverage | Web snapshots | Diagnostics | Raw errors | Shortfalls | Log |",
        "| --- | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |",
    ]
    for result in sorted(results, key=lambda item: item.score):
        shortfalls = ", ".join(result.shortfall_categories) if result.shortfall_categories else "-"
        log_name = Path(result.log_path).relative_to(output_dir)
        lines.append(
            f"| `{result.sample.id}` | {result.score:.1f} | {result.grade} | "
            f"{result.coverage:.1f}% | {len(result.web_snapshot_paths)} | "
            f"{len(result.diagnostic_warnings) + len(result.diagnostic_errors)} | "
            f"{len(result.raw_error_lines)} | {shortfalls} | `{log_name}` |"
        )

    lines.extend(["", "## Lowest Scoring Findings", ""])
    for result in sorted((item for item in results if item.grade != "N/A"), key=lambda item: item.score)[:10]:
        lines.append(f"### {result.sample.id} - {result.score:.1f} ({result.grade})")
        if result.findings:
            for finding in result.findings[:8]:
                lines.append(f"- {finding}")
        else:
            lines.append("- No notable findings.")
        lines.append("")

    precondition_results = [result for result in results if result.grade == "N/A"]
    if precondition_results:
        lines.extend(["## Precondition Skips", ""])
        for result in precondition_results:
            lines.append(f"- `{result.sample.id}`: {result.findings[0]}")
        lines.append("")

    comparison = summary.get("comparison")
    if comparison:
        lines.extend(["## Baseline Comparison", ""])
        if comparison.get("error"):
            lines.append(f"- {comparison['error']}")
        else:
            deltas = comparison.get("deltas", [])
            if not deltas:
                lines.append("- No score changes.")
            for delta in deltas[:50]:
                lines.append(f"- `{delta['id']}`: {delta}")
        lines.append("")

    report_path = output_dir / "report.md"
    report_path.write_text("\n".join(lines), encoding="utf-8")
    return report_path


def make_output_dir(base: Path | None) -> Path:
    if base:
        output_dir = base
    else:
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        output_dir = REPO_ROOT / f".codex/web-wallpaper-benchmark-{stamp}"
    output_dir.mkdir(parents=True, exist_ok=True)
    return output_dir


def load_samples_from_args(args: argparse.Namespace) -> list[Sample]:
    samples: list[Sample] = []
    if args.ids:
        for raw in args.ids.split(","):
            sample_id = raw.strip()
            if sample_id:
                samples.append(Sample(id=sample_id))
    if args.id_file:
        for line in Path(args.id_file).read_text(encoding="utf-8").splitlines():
            sample_id = line.strip()
            if sample_id and not sample_id.startswith("#"):
                samples.append(Sample(id=sample_id, reason="id-file"))
    if not samples:
        samples = discover_samples(Path(args.workshop_root))
    seen: set[str] = set()
    unique_samples: list[Sample] = []
    for sample in samples:
        if sample.id in seen:
            continue
        seen.add(sample.id)
        unique_samples.append(sample)
    if args.limit:
        unique_samples = unique_samples[: args.limit]
    return unique_samples


def run_benchmark(args: argparse.Namespace) -> int:
    output_dir = make_output_dir(Path(args.output_dir) if args.output_dir else None)
    build_log = output_dir / "build.log"
    app_binary = Path(args.app) if args.app else DEFAULT_APP_BINARY
    runtime_workshop_root = Path(args.runtime_workshop_root).expanduser().resolve() if args.runtime_workshop_root else None
    runtime_home = Path(args.runtime_home).expanduser().resolve() if args.runtime_home else None

    if runtime_workshop_root is None:
        print("--runtime-workshop-root is required so sample runs cannot use the real library.", file=sys.stderr)
        return 2
    if not runtime_workshop_root.is_dir():
        print(f"Runtime workshop root does not exist: {runtime_workshop_root}", file=sys.stderr)
        return 2
    if runtime_home is None:
        print("--runtime-home is required so sample runs cannot use normal user state.", file=sys.stderr)
        return 2

    if args.build:
        build_debug_app(Path(args.derived_data), build_log)

    if not app_binary.exists():
        print(f"App binary not found: {app_binary}", file=sys.stderr)
        print("Run with --build, or pass --app /path/to/MyWallpaperX.", file=sys.stderr)
        return 2

    samples = load_samples_from_args(args)
    if not samples:
        print(f"No Web samples found under {args.workshop_root}.", file=sys.stderr)
        print("Pass --ids 3700131876,2997985023 to run explicit Workshop IDs.", file=sys.stderr)
        return 2

    results: list[SampleResult] = []
    for index, sample in enumerate(samples, start=1):
        print(f"[{index}/{len(samples)}] benchmarking {sample.id}")
        results.append(
            run_one_sample(
                app_binary=app_binary,
                sample=sample,
                output_dir=output_dir,
                duration=args.duration,
                capture_screen=args.screenshot,
                kill_existing=args.kill_existing,
                runtime_workshop_root=runtime_workshop_root,
                runtime_home=runtime_home,
            )
        )

    comparison = compare_with_baseline(results, Path(args.baseline) if args.baseline else None)
    summary = summarize(results, comparison)
    json_path = write_json_report(output_dir, args, results, summary)
    md_path = write_markdown_report(output_dir, results, summary)

    print(f"Report JSON: {json_path}")
    print(f"Report Markdown: {md_path}")
    print(f"Average score: {summary['average_score']} coverage={summary['average_coverage']}%")
    return 0


def run_self_test(args: argparse.Namespace) -> int:
    output_dir = make_output_dir(Path(args.output_dir) if args.output_dir else None)
    fixture_dir = output_dir / "fixture"
    fixture_dir.mkdir(parents=True, exist_ok=True)
    log_path = fixture_dir / "app.log"
    web_snapshot_path = fixture_dir / "web-snapshot-1-ready.png"
    web_snapshot_path.write_bytes(b"fixture")
    log_path.write_text(
        "\n".join(
            [
                "2026-06-26 10:00:00.000 MyWallpaperX[1:1] MWX DEBUG PLAY: launching workshop item fixture type=web",
                "2026-06-26 10:00:01.000 MyWallpaperX[1:1] MWX WEB DIAG record=fixture screen=- severity=info type=runtime.profile url=mwx-local://wallpaper/index.html message=profile=standard origin=customScheme dataStore=persistent",
                "2026-06-26 10:00:01.500 MyWallpaperX[1:1] MWX WEB DIAG record=fixture screen=1 severity=info type=dom.ready url=- message=mwx-local://wallpaper/index.html",
                "2026-06-26 10:00:02.000 MyWallpaperX[1:1] MWX WEB DIAG record=fixture screen=1 severity=info type=host.ready url=- message=ready",
                "2026-06-26 10:00:02.100 MyWallpaperX[1:1] MWX WEB DIAG record=fixture screen=1 severity=info type=navigation.finish url=mwx-local://wallpaper/index.html message=ready",
                "2026-06-26 10:00:02.200 MyWallpaperX[1:1] MWX WEB DIAG record=fixture screen=1 severity=info type=media.initial url=- message=mwx-local://wallpaper/a.mp4 tag=video readyState=4",
                "2026-06-26 10:00:02.300 MyWallpaperX[1:1] MWX WEB DIAG record=fixture screen=1 severity=info type=pointer.down url=- message=x=10 y=10",
                "2026-06-26 10:00:02.350 MyWallpaperX[1:1] MWX WEB DIAG record=fixture screen=1 severity=info type=pointer.up url=- message=x=20 y=20",
                "2026-06-26 10:00:02.375 MyWallpaperX[1:1] MWX WEB DIAG record=fixture screen=1 severity=info type=evidence.interaction url=- message={events:[pointer,click,drag,wheel]}",
                "2026-06-26 10:00:02.390 MyWallpaperX[1:1] MWX WEB DIAG record=fixture screen=1 severity=info type=evidence.dom url=- message={visibleElementCount:4}",
                "2026-06-26 10:00:02.400 MyWallpaperX[1:1] webSnapshot[ready] size=1920x1080 avgLuma=0.230 nonBlack=0.800 lumaStdDev=0.180 colored=0.400 white=0.010",
            ]
        ),
        encoding="utf-8",
    )
    events, metadata = parse_log(log_path)
    result = score_sample(
        Sample(id="fixture"),
        events,
        metadata,
        log_path,
        screenshot_path=None,
        web_snapshot_paths=[web_snapshot_path],
        exit_code=-15,
        duration_seconds=3.0,
    )
    comparison = compare_with_baseline([result], Path(args.baseline) if args.baseline else None)
    summary = summarize([result], comparison=comparison)
    json_path = write_json_report(output_dir, args, [result], summary)
    md_path = write_markdown_report(output_dir, [result], summary)
    if result.score < 90:
        print(f"Self-test failed: score={result.score}", file=sys.stderr)
        return 1
    blank_metadata = dict(metadata)
    blank_metadata["snapshots"] = [
        {
            "reason": "ready",
            "size": "1920x1080",
            "avgLuma": 1.0,
            "nonBlack": 1.0,
            "lumaStdDev": 0.0,
            "colored": 0.0,
            "white": 1.0,
        }
    ]
    blank_result = score_sample(
        Sample(id="blank-fixture"),
        events,
        blank_metadata,
        log_path,
        screenshot_path=None,
        web_snapshot_paths=[web_snapshot_path],
        exit_code=-15,
        duration_seconds=3.0,
    )
    if blank_result.grade != "C" or "visual_output" not in blank_result.shortfall_categories:
        print(
            f"Self-test failed: blank frame grade={blank_result.grade} "
            f"shortfalls={blank_result.shortfall_categories}",
            file=sys.stderr,
        )
        return 1
    print(f"Self-test passed: score={result.score} coverage={result.coverage}%")
    print(f"Report JSON: {json_path}")
    print(f"Report Markdown: {md_path}")
    return 0


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Benchmark MyWallpaperX Web wallpaper runtime capability."
    )
    parser.add_argument("--self-test", action="store_true", help="Run parser/scorer fixture without launching the app.")
    parser.add_argument("--build", action="store_true", help="Build the Debug app before running samples.")
    parser.add_argument("--derived-data", default=str(DEFAULT_DERIVED_DATA), help="DerivedData path for --build.")
    parser.add_argument("--app", help="Path to MyWallpaperX debug binary.")
    parser.add_argument("--workshop-root", default=str(DEFAULT_WORKSHOP_ROOT), help="Workshop library root to discover samples.")
    parser.add_argument(
        "--runtime-workshop-root",
        help="Debug-only library root passed to the app while launching samples; use an isolated copy to protect the real library.",
    )
    parser.add_argument(
        "--runtime-home",
        help="Temporary HOME/CFFIXED_USER_HOME base; each launched sample receives its own child directory.",
    )
    parser.add_argument("--ids", help="Comma-separated Workshop IDs to benchmark.")
    parser.add_argument("--id-file", help="File containing one Workshop ID per line.")
    parser.add_argument("--limit", type=int, help="Limit discovered samples.")
    parser.add_argument("--duration", type=float, default=10.0, help="Seconds to run each sample.")
    parser.add_argument("--screenshot", action="store_true", help="Capture a desktop screenshot near the end of each run.")
    parser.add_argument("--kill-existing", action="store_true", help="Kill existing MyWallpaperX processes before each sample.")
    parser.add_argument("--baseline", help="Previous report.json for score comparison.")
    parser.add_argument("--output-dir", help="Directory for logs and reports.")
    return parser


def main(argv: list[str]) -> int:
    parser = make_parser()
    args = parser.parse_args(argv)
    if args.self_test:
        return run_self_test(args)
    return run_benchmark(args)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
