# Art and Audio Pipeline

This project is intentionally scoped as a small complete game, so the content pipeline stays simple.

## Locked Production Assumptions

- Game type: single-player 3D micro-story
- Target length: under 1 hour
- Visual family: Contra-like readability with 3D execution
- Scope rule: complete the vertical slice before adding more chapters

## Visual Direction

- Base reference: Contra / Metal Slug era arcade readability
- 3D implementation: low-poly silhouettes, hard edges, strong lighting contrast
- Post-process: subtle pixelation or downscaled viewport if needed
- Animation: exaggerated run, hit, recoil, and death states

## Asset List

### Characters

- Player
- 2 to 4 enemy types
- Boss or mid-boss for the ending

### Environments

- Intro corridor
- Industrial compound
- Interior terminal room
- Escape or final reveal room

### UI

- Health display
- Objective banner
- Dialogue box
- Result screen

### Audio

- Footsteps
- Blaster shot
- Enemy hit
- Player hit
- Explosion
- UI confirm / cancel
- 2 to 3 music loops

## Production Order

1. Block out the full game in primitive 3D
2. Replace the player and first enemy with final models
3. Add animation clips and hit reactions
4. Add sound effects and music
5. Polish camera, UI, and transitions

## Documentation Cross-References

- See `README.md` for the public-facing summary.
- See `agents.md` for the working rules that future agent turns should obey.
- See `docs/Design_Decisions.md` for the frozen scope and production assumptions.
