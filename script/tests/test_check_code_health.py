from __future__ import annotations

import importlib.util
import json
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "check_code_health.py"
SPEC = importlib.util.spec_from_file_location("check_code_health", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
GATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GATE)


class CodeHealthGateTests(unittest.TestCase):
    def test_current_tree_rejects_growth_and_new_oversized_file(self) -> None:
        baseline = {
            "lineLimit": 400,
            "legacyFiles": {"MyWallpaperX/Legacy.swift": 500},
        }

        problems = GATE.current_tree_problems(
            baseline,
            {
                "MyWallpaperX/Legacy.swift": 501,
                "MyWallpaperX/New.swift": 401,
            },
        )

        self.assertEqual(2, len(problems))
        self.assertIn("grew", problems[0][1])
        self.assertIn("unbaselined", problems[1][1])

    def test_current_tree_requires_ratchet_after_shrink_or_delete(self) -> None:
        baseline = {
            "lineLimit": 400,
            "legacyFiles": {
                "MyWallpaperX/Shrank.swift": 500,
                "MyWallpaperX/Deleted.swift": 450,
            },
        }

        problems = GATE.current_tree_problems(
            baseline,
            {"MyWallpaperX/Shrank.swift": 450},
        )

        self.assertEqual(2, len(problems))
        self.assertTrue(all("ratchet" in message for _, message in problems))

    def test_history_rejects_weaker_limits_and_new_exceptions(self) -> None:
        previous = {
            "lineLimit": 400,
            "sourceRoots": ["MyWallpaperX", "WallpaperDaemonSources"],
            "legacyFiles": {"MyWallpaperX/Legacy.swift": 500},
        }
        current = {
            "lineLimit": 401,
            "sourceRoots": ["MyWallpaperX"],
            "legacyFiles": {
                "MyWallpaperX/Legacy.swift": 501,
                "MyWallpaperX/New.swift": 450,
            },
        }

        problems = GATE.historical_problems(current, previous)

        self.assertEqual(4, len(problems))
        messages = "\n".join(message for _, message in problems)
        self.assertIn("lineLimit increased", messages)
        self.assertIn("source roots cannot be removed", messages)
        self.assertIn("increased from 500 to 501", messages)
        self.assertIn("new legacy exception", messages)

    def test_baseline_rejects_non_normalized_paths_and_unmanaged_legacy_files(self) -> None:
        baseline = {
            "schemaVersion": 1,
            "lineLimit": 400,
            "sourceRoots": ["MyWallpaperX"],
            "legacyFiles": {},
        }
        GATE.read_baseline_text(json.dumps(baseline), "fixture")

        for invalid_root in ("/tmp/source", "../source", "MyWallpaperX/../Other", "MyWallpaperX/"):
            invalid = dict(baseline, sourceRoots=[invalid_root])
            with self.subTest(root=invalid_root):
                with self.assertRaises(ValueError):
                    GATE.read_baseline_text(json.dumps(invalid), "fixture")

        unmanaged = dict(
            baseline,
            legacyFiles={"MyWallpaperXTests/Oversized.swift": 500},
        )
        with self.assertRaises(ValueError):
            GATE.read_baseline_text(json.dumps(unmanaged), "fixture")

    def test_source_root_membership_uses_path_components(self) -> None:
        roots = ["MyWallpaperX", "WallpaperDaemonSources"]

        self.assertTrue(GATE.belongs_to_source_root("MyWallpaperX/App/AppDelegate.swift", roots))
        self.assertTrue(GATE.belongs_to_source_root("WallpaperDaemonSources/main.swift", roots))
        self.assertFalse(GATE.belongs_to_source_root("MyWallpaperXTests/AppTests.swift", roots))
        self.assertFalse(GATE.belongs_to_source_root("MyWallpaperXBackup/File.swift", roots))


if __name__ == "__main__":
    unittest.main()
