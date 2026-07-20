#!/usr/bin/env python3

import copy
import json
import sys
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

from web_runtime_switch_benchmark import apply_process_outcome, score_log


SAMPLE_ID = "1509243786"
DEFAULTS_SUITE = "com.songziqiang.MyWallpaperX.Debug.runtime-switch-test"
VIDEO1_PID = 101
VIDEO2_PID = 202


def action(name: str, elapsed_ms: int) -> str:
    return f"MWX DEBUG RUNTIME SWITCH: action={name} elapsedMs={elapsed_ms}"


def checkpoint(name: str, state: dict) -> str:
    payload = json.dumps(state, separators=(",", ":"), sort_keys=True)
    return f"MWX DEBUG RUNTIME SWITCH: checkpoint={name} state={payload}"


def diag(event_type: str, message: str, record: str = SAMPLE_ID) -> str:
    return (
        f"MWX WEB DIAG record={record} screen=1 severity=info "
        f"type={event_type} url=- message={message}"
    )


def web_state(
    phase: str = "idle", surfaces: int = 0, current_request: int = 0
) -> dict:
    return {
        "currentRequest": current_request,
        "loopbacks": 0,
        "monitors": 0,
        "observers": 0,
        "phase": phase,
        "pointerTimer": 0,
        "surfaces": surfaces,
        "watchTimer": 0,
        "watchers": 0,
    }


def session(pid: int, accepted=None, ready=None) -> dict:
    return {
        "accepted": accepted,
        "display": 1,
        "launched": accepted is not None,
        "pid": pid,
        "ready": ready,
        "requested": 1,
        "running": True,
    }


def state(
    *,
    kind: str = "-",
    path: str = "-",
    playing: bool = False,
    sessions: list | None = None,
    web: dict | None = None,
    video1_alive: list | None = None,
    video1_pids: list | None = None,
    video2_alive: list | None = None,
    video2_pids: list | None = None,
) -> dict:
    return {
        "elapsedMs": 0,
        "kind": kind,
        "path": path,
        "playing": playing,
        "sessions": sessions or [],
        "video1Alive": video1_alive or [],
        "video1Pids": video1_pids or [],
        "video2Alive": video2_alive or [],
        "video2Pids": video2_pids or [],
        "web": web or web_state(),
    }


def passing_lines() -> list[str]:
    video1 = state(
        kind="video",
        path="Video1.mp4",
        playing=True,
        sessions=[session(VIDEO1_PID)],
        video1_alive=[VIDEO1_PID],
        video1_pids=[VIDEO1_PID],
    )
    web = state(
        kind="web",
        path="index.html",
        playing=True,
        web=web_state("launching", surfaces=1, current_request=1),
        video1_alive=[VIDEO1_PID],
        video1_pids=[VIDEO1_PID],
    )
    requested = state(
        kind="video",
        path="Video2.mp4",
        playing=True,
        sessions=[session(VIDEO2_PID)],
        video1_pids=[VIDEO1_PID],
        video2_alive=[VIDEO2_PID],
        video2_pids=[VIDEO2_PID],
    )
    stable = copy.deepcopy(requested)
    stable["sessions"] = [session(VIDEO2_PID, accepted=1, ready=1)]
    return [
        f"MWX DEBUG DEFAULTS: suite={DEFAULTS_SUITE}",
        action("preflight", 0),
        checkpoint("preflight", state()),
        action("video1", 0),
        checkpoint("video1-requested", video1),
        action("web", 35),
        diag("runtime.profile", "profile=standard origin=customScheme dataStore=workshopPersistent"),
        checkpoint("web-requested", web),
        action("video2", 105),
        diag("lifecycle.teardown", "surfaces=0 loopbacks=0 watchers=0 monitors=0 pointerTimer=0"),
        diag("lifecycle.stop", "phase=idle surfaces=0 loopbacks=0 observers=0"),
        checkpoint("video2-requested", requested),
        diag("lifecycle.surface.released", "screen=1", record="-"),
        checkpoint("video2-stable", stable),
        action("stop", 3500),
        checkpoint(
            "stopped",
            state(video1_pids=[VIDEO1_PID], video2_pids=[VIDEO2_PID]),
        ),
        action("completed", 4900),
    ]


def score(lines: list[str]) -> dict:
    return score_log("\n".join(lines), SAMPLE_ID, DEFAULTS_SUITE)


def replace_checkpoint(lines: list[str], name: str, mutate) -> list[str]:
    updated = list(lines)
    prefix = f"MWX DEBUG RUNTIME SWITCH: checkpoint={name} state="
    index = next(i for i, line in enumerate(updated) if line.startswith(prefix))
    payload = json.loads(updated[index][len(prefix):])
    mutate(payload)
    updated[index] = checkpoint(name, payload)
    return updated


class WebRuntimeSwitchBenchmarkTests(unittest.TestCase):
    def test_passing_timeline(self) -> None:
        result = score(passing_lines())
        self.assertTrue(result["passed"], result["failures"])
        self.assertTrue(result["switch_passed"])
        self.assertTrue(result["cleanup_passed"])
        self.assertEqual(result["switch_interval_ms"], 105)
        self.assertEqual(result["video1_pids"], [VIDEO1_PID])
        self.assertEqual(result["video2_pids"], [VIDEO2_PID])

    def test_rejects_missing_defaults_suite(self) -> None:
        result = score(passing_lines()[1:])
        self.assertFalse(result["passed"])
        self.assertIsNone(result["debug_defaults_suite"])

    def test_rejects_slow_switch_that_misses_race_window(self) -> None:
        lines = [
            line.replace("action=video2 elapsedMs=105", "action=video2 elapsedMs=300")
            for line in passing_lines()
        ]
        result = score(lines)
        self.assertFalse(result["passed"])
        self.assertEqual(result["switch_interval_ms"], 300)

    def test_rejects_video2_that_leaves_web_active(self) -> None:
        lines = replace_checkpoint(
            passing_lines(),
            "video2-stable",
            lambda payload: payload.update(
                kind="web",
                path="index.html",
                sessions=[],
                web=web_state("ready", surfaces=1, current_request=1),
            ),
        )
        result = score(lines)
        self.assertFalse(result["passed"])
        self.assertTrue(any("Video2 stable state" in failure for failure in result["failures"]))

    def test_rejects_video2_without_ready_acknowledgement(self) -> None:
        lines = replace_checkpoint(
            passing_lines(),
            "video2-stable",
            lambda payload: payload["sessions"][0].update(ready=None),
        )
        result = score(lines)
        self.assertFalse(result["passed"])
        self.assertTrue(any("accept, and ready" in failure for failure in result["failures"]))

    def test_rejects_reused_or_live_video1_pid(self) -> None:
        def mutate(payload: dict) -> None:
            payload["sessions"][0]["pid"] = VIDEO1_PID
            payload["video1Alive"] = [VIDEO1_PID]
            payload["video2Alive"] = [VIDEO1_PID]
            payload["video2Pids"] = [VIDEO1_PID]

        lines = replace_checkpoint(passing_lines(), "video2-stable", mutate)
        result = score(lines)
        self.assertFalse(result["passed"])
        self.assertTrue(any("Video1 daemon PID" in failure for failure in result["failures"]))

    def test_rejects_missing_web_lifecycle_stop(self) -> None:
        lines = [line for line in passing_lines() if "type=lifecycle.stop " not in line]
        result = score(lines)
        self.assertFalse(result["passed"])
        self.assertTrue(any("did not stop Web" in failure for failure in result["failures"]))

    def test_rejects_retained_web_surface(self) -> None:
        lines = [
            line.replace("type=lifecycle.surface.released", "type=lifecycle.surface.retained")
            for line in passing_lines()
        ]
        result = score(lines)
        self.assertFalse(result["passed"])
        self.assertEqual(result["retained_surface_count"], 1)

    def test_rejects_web_ready_after_video2_intent(self) -> None:
        lines = passing_lines()
        index = lines.index(checkpoint("video2-stable", json.loads(
            next(line.split(" state=", 1)[1] for line in lines if "checkpoint=video2-stable " in line)
        )))
        lines.insert(index, diag("host.ready", "ready"))
        result = score(lines)
        self.assertFalse(result["passed"])
        self.assertTrue(any("stale Web host" in failure for failure in result["failures"]))

    def test_rejects_final_daemon_or_web_residue(self) -> None:
        def mutate(payload: dict) -> None:
            payload["sessions"] = [session(VIDEO2_PID, accepted=1, ready=1)]
            payload["video2Alive"] = [VIDEO2_PID]
            payload["web"] = web_state("idle", surfaces=1)

        result = score(replace_checkpoint(passing_lines(), "stopped", mutate))
        self.assertFalse(result["passed"])
        self.assertTrue(result["switch_passed"])
        self.assertFalse(result["cleanup_passed"])
        self.assertTrue(any("final stop" in failure for failure in result["failures"]))

    def test_rejects_empty_checkpoint_states(self) -> None:
        lines = [
            line.split(" state=", 1)[0] + " state={}"
            if "MWX DEBUG RUNTIME SWITCH: checkpoint=" in line
            else line
            for line in passing_lines()
        ]
        result = score(lines)
        self.assertFalse(result["switch_passed"])
        self.assertTrue(
            any("invalid or missing" in failure for failure in result["switch_failures"])
        )

    def test_rejects_app_exit_before_deadline(self) -> None:
        result = score(passing_lines())
        apply_process_outcome(result, launch_error=None, process_survived_duration=False)
        self.assertFalse(result["passed"])
        self.assertFalse(result["switch_passed"])
        self.assertTrue(
            any("exited before" in failure for failure in result["switch_failures"])
        )

    def test_rejects_action_order_change(self) -> None:
        lines = passing_lines()
        web_index = next(i for i, line in enumerate(lines) if "action=web " in line)
        video2_index = next(i for i, line in enumerate(lines) if "action=video2 " in line)
        lines[web_index], lines[video2_index] = lines[video2_index], lines[web_index]
        result = score(lines)
        self.assertFalse(result["passed"])
        self.assertNotEqual(result["observed_actions"], result["expected_actions"])


if __name__ == "__main__":
    unittest.main()
