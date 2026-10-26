#!/usr/bin/env python3
"""Freeze the solo levels lab (one courier, all levels in difficulty order, res://lab/main.tscn) and build its standalone Mac app.
Local only: never uploads, no Android package.
    FRIENDS_PRIORITY=1 tools/engine_slot.sh python3 tools/build_solo_levels.py --output build/solo-levels-<new name>"""
import app_build

if __name__ == '__main__':
    app_build.build(name='FRIENDS Solo Levels', identity='com.summerengine.friends.sololevels', entry='res://lab/main.tscn',
                    executable='FRIENDSSoloLevels', tag='solo', description=__doc__)
