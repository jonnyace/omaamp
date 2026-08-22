#!/usr/bin/env python3
"""State handoff regressions for the standalone player."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SKINNER = ROOT / "bin" / "skinner"


class PlayerSizeState(unittest.TestCase):
    def test_size_command_persists_mode_without_losing_player_state(self):
        with tempfile.TemporaryDirectory() as tmp:
            current = Path(tmp) / "omaamp" / "current.json"
            current.parent.mkdir(parents=True)
            current.write_text(json.dumps({"mode": "tui", "name": "test"}))
            env = {**os.environ, "XDG_STATE_HOME": tmp}

            for mode in ("original", "large"):
                result = subprocess.run(
                    [sys.executable, str(SKINNER), "size", mode],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    check=True,
                )
                payload = json.loads(result.stdout)
                state = json.loads(current.read_text())
                self.assertEqual(payload["resized"], mode)
                self.assertEqual(state["size"], mode)
                self.assertEqual(state["name"], "test")


if __name__ == "__main__":
    unittest.main()
