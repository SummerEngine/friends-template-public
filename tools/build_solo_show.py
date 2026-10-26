#!/usr/bin/env python3
"""Freeze THE SHOW for one player wearing the TIDEWHEAT sample cast (res://show_solo.tscn: no title, straight into the lobby yard, a points
show for one player on the keyboard and/or a gamepad) and build its standalone Mac app. Local only: never uploads, no Android package.
It opens fullscreen when exported (client/settings.gd: the exported desktop app only, never headless or offscreen runs).
    FRIENDS_PRIORITY=1 tools/engine_slot.sh python3 tools/build_solo_show.py --output build/solo-show-<new name>
`--cast <dir>` wears another cast (samples/acme, ...). demo/cast/ is never changed."""
from pathlib import Path

import app_build

if __name__ == '__main__':
    app_build.build(name='FRIENDS Show', identity='com.summerengine.friends.show', entry='res://show_solo.tscn',
                    executable='FRIENDSShow', tag='show', description=__doc__, cast=Path(__file__).resolve().parents[1] / 'samples/tidewheat')
