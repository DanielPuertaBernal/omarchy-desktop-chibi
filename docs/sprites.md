# Sprites: animation set and strip format

A character is a folder with one PNG strip per animation plus a
`sprites.json` that describes them. `personality.json` picks the folder:

```json
{ "character": "characters/kumo" }   // default: new full-body character (placeholder art)
{ "character": "sprites" }           // the original chibi
{ "character": "ellen" }             // ~/.config/danso-chibi/characters/ellen
```

### Your own characters (kept outside the repo)

Put personal characters, and any art you may not publish, in
`~/.config/danso-chibi/characters/<name>/` and set `"character": "<name>"`.
A bare name is looked up there first, then in the repo; an absolute path
(or `~/...`) also works. An unknown name falls back to `characters/kumo`.

```
~/.config/danso-chibi/characters/<name>/
  sprites.json          required (format below)
  idle.png, walk.png... the strips
  personality.json      optional: her own name, tone, lines (overrides personality.json)
```

The repo's `.gitignore` ignores every folder in `characters/` except
`kumo`, so a character copied into the repo by mistake is not committed.

To switch characters, change `character` in
`~/.config/danso-chibi/personality.json` and restart the plugin.

## Strip format

- **One PNG per animation**, all frames side by side in **one row** (a
  horizontal strip), **transparent background** (RGBA).
- All frames in a strip have the same size; strip width = `frameWidth × frameCount`.
- `walk`, `run` and `climb` face **right**; they are mirrored to go left.
  The rest face the viewer (front or three-quarter view).
- Feet sit on the bottom edge of the frame (she stands on the bottom of her
  box). For `hang`, the hands touch the top edge.

### Default size (characters/kumo)

| | |
|---|---|
| Frame | **180 × 400 px** (aspect ≈ 1 : 2.27) |
| Proportions | full-body anime, head ≈ 1/4.5 of her height |
| Generate at | 2x, **360 × 800 px** per frame, then downscale (see below) |
| On screen | 180 × 400 logical px at `scale: 1`; set `scale` in `personality.json` (0.75, 1, 1.25...) |

The original chibi in `sprites/` keeps its own sizes (83–159 px wide) and
works unchanged.

## Animation set

| File | Used for | Frames (placeholder) | frameMs |
|------|----------|----------------------|---------|
| `idle.png` | standing still | 6 | 240 |
| `walk.png` | walking (faces right) | 6 | 140 |
| `run.png` | running, chasing the cursor (faces right) | 6 | 80 |
| `sit.png` | sitting | 2 | 900 |
| `sleep.png` | napping (can be 1 frame; she "breathes") | 1 | 1000 |
| `hang.png` | held / dragged by the mouse, hands at the top | 2 | 280 |
| `fall.png` | thrown or falling | 4 | 120 |
| `climb.png` | climbing a screen edge (faces right, wall on the right) | 4 | 200 |
| `think.png` | agent is thinking (prompt landed) | 4 | 450 |
| `work.png` | agent is working (typing on a laptop) | 4 | 110 |
| `wave.png` | agent needs you (waving) | 4 | 160 |
| `celebrate.png` | agent finished (confetti is added by the code) | 4 | 130 |
| `bow.png` | thank you (you accepted a permission) | 4 | 300 |
| `oops.png` | a tool failed (stumble) | 4 | 130 |
| `talk.png` | talking while a chat reply streams | 4 | 160 |
| `dance.png` | dancing (random activity) | 6 | 170 |
| `jump.png` | jumping (random activity) | 4 | 260 |

Only `idle` is strictly required. A missing strip falls back to a close one
(`fall → hang`, `wave → dance`, `think → idle`, `work → sit`...), so a
character with just the original eight strips still plays every state.

## sprites.json

```json
{
  "_meta": { "box": [180, 400], "scale": 1 },
  "walk": { "frameWidth": 180, "frameHeight": 400, "frameCount": 6, "frameMs": 140, "sideways": true }
}
```

- `_meta.box`: her hit box / anchor in px (defaults to the idle frame size).
- `_meta.scale`: default on-screen scale for this character.
- `frameMs` (ms per frame) and `sideways` (mirrored to go left) are optional;
  defaults exist for the classic names.
- `motion` (optional) adds procedural movement to strips with few frames:
  `breathe` (slow bob and breathing), `bounce` (small hops, e.g. celebrate),
  `sway` (rocks from the feet, e.g. wave). It ticks every 50 ms only while
  such a strip is showing.
- To make a 2-frame blink look natural, repeat the open-eyes frame in the
  strip (e.g. 7 open + 1 closed at 400 ms) instead of slowing the clock.
- Keys starting with `_` are ignored.

## Placeholders

`characters/kumo/*.png` are **placeholders**, drawn by
`tools/make-placeholders.py` (flat shapes, labelled "placeholder"). Replace
them with real art made with [gemini-sprite-prompts.md](gemini-sprite-prompts.md)
and update `sprites.json` if the frame counts change.
