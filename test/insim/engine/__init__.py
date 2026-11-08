"""The in-sim engine. Its driver core is dcs-hotload's own client, `bin/hotload.py` in the vendored release."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "dcs-hotload" / "bin"))
