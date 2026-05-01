# Godot Game One

Single-player 3D micro-story game for Godot 4.

## Reference Docs

- [Agent Guide](./agents.md)
- [Development Plan](./docs/Development_Plan.md)
- [Design Decisions](./docs/Design_Decisions.md)
- [Art and Audio Pipeline](./docs/art_audio_pipeline.md)

## Target

- Playtime: under 1 hour
- Tone: short sci-fi rescue story
- Visual direction: NES / Contra-inspired retro action, but built in 3D
- Camera: side-biased 3D action camera with pixel-like presentation
- Scope: one complete vertical slice first, then expand content
- Technical target: Godot 4.x, GDScript, small scene count, fast iteration

## Core Loop

1. Briefing
2. Run through a compact hostile corridor
3. Fight a small set of enemies
4. Reach a story terminal or objective checkpoint
5. Escape / end scene

## Controls

- Move: `ui_left`, `ui_right`, `ui_up`, `ui_down`
- Jump / cancel: `ui_cancel`
- Shoot / confirm: `ui_accept`

## Project Layout

- `scenes/` Godot scenes
- `scripts/` gameplay logic
- `docs/` story, art, and audio brief
- `assets/` placeholder folders for future art and sound

## Style Guide

- World scale: compact rooms, readable silhouettes, limited clutter
- Colors: high-contrast, saturated accents, restrained background palette
- Materials: simple shaded materials, low-frequency detail, obvious form language
- UI: arcade-style, minimal, screen-space only when needed
- Audio: punchy effects, short loops, clear weapon feedback

## Next Milestones

1. Replace primitive geometry with final level art
2. Add enemy behaviors and a dialogue sequence
3. Add music, weapon sounds, and hit feedback
4. Expand into 3 to 5 short chapters

## Current Focus

- Phase 1: playable vertical slice
- Status: player/enemy/combat/exit-state loop is being wired up

## Documentation Rule

- Any change to gameplay scope, camera, control feel, art direction, or production order must be mirrored in the design docs before implementation drifts.
- Keep the README as the entry point, and keep the detailed decisions in the design docs.
