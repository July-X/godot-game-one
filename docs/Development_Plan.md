# Development Plan

This plan describes the work sequence for the current game slice. It is intentionally narrow: the goal is to ship a complete short game, not to grow the scope before the loop is stable.

## Phase 1: Playable Vertical Slice

Goal: make the game start, play, fight, and finish.

Work items:

1. Keep the project loadable in Godot 4.
2. Make the player move, jump, and shoot.
3. Make enemies patrol, chase, take damage, and die.
4. Add win and fail conditions.
5. Add a simple HUD and story line.

Expected result:

- One compact level can be cleared from start to finish.
- The player understands the objective at a glance.
- Combat feedback is readable even with placeholder art.

## Phase 2: Narrative and Flow

Goal: turn the vertical slice into a short micro-story game.

Work items:

1. Add intro and outro beats.
2. Add 2 to 4 short scene segments.
3. Tighten pacing so a full run stays under 1 hour.
4. Add result screen and restart flow.

## Phase 3: Visual Production

Goal: replace placeholders with final art while preserving the current style direction.

Work items:

1. Model the player, enemies, environment props, and key set pieces.
2. Add animation clips and state transitions.
3. Improve lighting, post-process, and readability.
4. Keep the Contra-inspired 3D visual language consistent.

## Phase 4: Audio and Polish

Goal: finish the experience.

Work items:

1. Add weapon, hit, explosion, UI, and ambient sounds.
2. Add 2 to 3 short BGM loops.
3. Tune difficulty, hit timings, and transitions.
4. Fix bugs and prepare a playable build.

## Working Rule

- Do not expand into new systems before Phase 1 is complete.
- Update this document when the plan changes.
- If a milestone is added or removed, mirror the change in `README.md` and `docs/Design_Decisions.md`.

## Current Progress

- Phase 1 in progress.
- Completed in current slice: enemy touch damage, player hit invincibility, exit lock/unlock flow, restart flow, and one story trigger beat in level 01.
