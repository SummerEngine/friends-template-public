#!/usr/bin/env python3
"""Freeze the level game (title -> lobby with two circles -> TIME ATTACK / ENDLESS runs -> results, two players on one machine,
res://main.tscn) and build its standalone Mac app. Local only: never uploads, no Android package.
    FRIENDS_PRIORITY=1 tools/engine_slot.sh python3 tools/build_levels_game.py --output build/levels-game-<new name>"""
import app_build

if __name__ == '__main__':
    app_build.build(name='FRIENDS Levels', identity='com.summerengine.friends.levels', entry='res://main.tscn',
                    executable='FRIENDSLevels', tag='levels', description=__doc__)
