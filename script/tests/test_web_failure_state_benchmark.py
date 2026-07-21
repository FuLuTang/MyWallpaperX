#!/usr/bin/env python3

import sys
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

from web_failure_state_benchmark import EXPECTED_CHECKS, validate_app_report


def passing_report() -> dict:
    return {
        "checks": {name: True for name in EXPECTED_CHECKS},
        "failureCount": 1,
        "passed": True,
        "preconditionFailure": None,
    }


class WebFailureStateBenchmarkTests(unittest.TestCase):
    def test_accepts_complete_passing_report(self) -> None:
        self.assertEqual(validate_app_report(passing_report()), [])

    def test_rejects_empty_report(self) -> None:
        self.assertTrue(validate_app_report({}))

    def test_rejects_missing_or_false_check(self) -> None:
        missing = passing_report()
        missing["checks"].pop("stopCleared")
        self.assertTrue(validate_app_report(missing))

        failed = passing_report()
        failed["checks"]["terminalCleared"] = False
        self.assertTrue(validate_app_report(failed))

    def test_rejects_precondition_and_duplicate_failure(self) -> None:
        report = passing_report()
        report["preconditionFailure"] = "fixture missing"
        report["failureCount"] = 2
        self.assertTrue(validate_app_report(report))


if __name__ == "__main__":
    unittest.main()
