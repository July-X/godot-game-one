# Design Decisions

This document freezes the current direction of the project. If any of these decisions change, update this file first, then update the implementation and the related reference docs.

## 1. Game Pitch

- Single-player 3D micro-story game.
- Target playtime: under 1 hour.
- Tone: compact sci-fi rescue mission with light narrative framing.
- Style reference: NES / Contra energy, but rebuilt in 3D with modern readability.

## 2. Scope Freeze

- Build a complete vertical slice before expanding content.
- No multiplayer, no online services, no backend dependencies.
- No large open world.
- No large skill tree or systemic progression layer yet.
- Focus on a short, replayable action loop with a clear beginning and ending.

## 3. Core Loop

1. Briefing and objective setup.
2. Move through a hostile corridor or compact arena.
3. Fight a small enemy set.
4. Reach a terminal, switch, or exit condition.
5. Resolve the story beat and end the run.

## 4. Camera and Controls

- Camera: side-biased 3D action camera.
- Movement: standard action movement mapped to the default Godot input actions.
- Jump: used sparingly, only if it improves traversal readability.
- Shooting: direct, readable, low-friction firing behavior.

## 5. Visual Direction

- Low-poly or simple-shape 3D assets.
- High-contrast silhouettes.
- Saturated foreground accents against restrained backgrounds.
- Readability takes priority over realism.
- Extra detail should support combat clarity, not clutter the frame.

## 6. Audio Direction

- Short, punchy weapon and hit sounds.
- Clear feedback for damage, death, pickups, and UI confirmation.
- Music should support quick action pacing and short story scenes.

## 7. Current Production Order

1. Keep the current prototype scene loadable.
2. Replace placeholder geometry with final art only after the loop is stable.
3. Add enemy behaviors and the story sequence.
4. Add animation, hit feedback, and audio.
5. Polish level flow and final menu/result presentation.

## 8. Development Plan Link

- See `docs/Development_Plan.md` for the task-by-task rollout order.
- Phase 1 is the current focus until the playable vertical slice is complete.

## 9. Update Rule

- If a feature changes the game pitch, time budget, visual language, or content scope, update:
  - `README.md`
  - `agents.md`
  - `docs/art_audio_pipeline.md`
- If a scene or script change implies a new rule for future work, write it here instead of leaving it implicit.
