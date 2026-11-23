# Gemini prompts for the sprite strips

One prompt per animation for Gemini image generation, all for **one original
character**. Paste the **character sheet** block first in every chat (or keep
one chat and generate the animations one after another) so she looks the same
in every strip. Edit the bracketed values to make her yours.

Output target (see [sprites.md](sprites.md)): frames of **180 × 400 px**,
generated at **2x = 360 × 800 px per frame**, in a single horizontal row.

## 1. Character sheet (paste before every prompt)

```text
CHARACTER (keep identical in every image):
Original character named [Kumo], a young adult woman, full-body anime illustration.
Proportions: realistic anime, head is 1/4.5 of her total height, slim average adult build,
long legs, natural posture. NOT chibi, NOT super-deformed.
Hair: [long straight hair, deep indigo #3b4261 with soft periwinkle #7aa2f7 highlights,
side-swept bangs, a small star-shaped hair clip on the left].
Eyes: [large lavender #bb9af7 eyes].
Outfit: [oversized soft-blue #7aa2f7 cardigan over a plain pale lavender-white #c0caf5 top
(no text, no logos), dark slate #414868 pleated knee-length skirt, dark tights,
lilac #bb9af7 sneakers].
Style: clean smooth cel-shaded anime illustration, crisp dark outlines (#16161e),
soft two-tone shading, flat colors, no gradients in the background, no text,
no watermark, no shadows on the ground. Tokyo Night palette.

SPRITE SHEET RULES:
- One single horizontal row of {N} frames, all frames the same size.
- Each frame is exactly 360 px wide and 800 px tall; total image {N×360} × 800 px.
- Full body visible in every frame, feet touching the bottom edge, about 40 px of
  empty space above the head, character centered in each frame.
- Same scale, same proportions and same position of the feet in every frame.
- Background: solid pure chroma green #00FF00 (or transparent if supported).
  No green anywhere on the character.
- No frame borders, no numbers, no grid lines.
```

## 2. Animation prompts

Replace `{N}` in the sheet with the frame count below.

| Animation | File | N |
|---|---|---|
| Idle | `idle.png` | 6 |
| Walk | `walk.png` | 6 |
| Run | `run.png` | 6 |
| Sit | `sit.png` | 2 |
| Sleep | `sleep.png` | 1 |
| Held / dragged | `hang.png` | 2 |
| Fall | `fall.png` | 4 |
| Climb | `climb.png` | 4 |
| Thinking | `think.png` | 4 |
| Working / typing | `work.png` | 4 |
| Needs you (wave) | `wave.png` | 4 |
| Done / celebrate | `celebrate.png` | 4 |
| Thank-you bow | `bow.png` | 4 |
| Oops / stumble | `oops.png` | 4 |
| Talking | `talk.png` | 4 |
| Dance (optional) | `dance.png` | 6 |
| Jump (optional) | `jump.png` | 4 |

### Idle — `idle.png`, 6 frames
```text
[character sheet with N=6]
Animation: idle loop. Front three-quarter view facing the viewer. She stands relaxed,
breathing softly: frames 1-6 show a subtle up-and-down of the shoulders, one slow blink
on frame 4, hair moving slightly. Frame 6 must loop back smoothly to frame 1.
```

### Walk — `walk.png`, 6 frames
```text
[character sheet with N=6]
Animation: walk cycle, strict side view facing RIGHT. Classic 6-frame walk:
contact, down, passing, up, contact (other leg), passing. Arms swing opposite to legs,
hair and cardigan sway a little. Feet on the same baseline in all frames. Loops.
```

### Run — `run.png`, 6 frames
```text
[character sheet with N=6]
Animation: run cycle, strict side view facing RIGHT, body leaning forward ~10 degrees,
long strides with one frame where both feet are off the ground, arms bent and pumping,
hair flowing back. Loops.
```

### Sit — `sit.png`, 2 frames
```text
[character sheet with N=2]
Animation: sitting on the floor facing the viewer, knees bent to one side, hands resting
on her lap. Frame 2: same pose with eyes closed for a blink. Feet still at the bottom edge.
```

### Sleep — `sleep.png`, 1 frame
```text
[character sheet with N=1]
Single frame: she sits on the floor hugging her knees, head tilted and resting on her
knees, eyes closed, peaceful smile, a small "z" floating near her head is NOT drawn
(the app adds effects). Fits inside the 360x800 frame, feet at the bottom.
```

### Held / dragged — `hang.png`, 2 frames
```text
[character sheet with N=2]
Animation: she is being lifted by her hands. Both arms straight up, HANDS TOUCHING THE
TOP EDGE of the frame, body hanging below, legs dangling, surprised face. Frame 2:
legs swung slightly to the other side. There is no visible hand or object holding her.
```

### Fall — `fall.png`, 4 frames
```text
[character sheet with N=4]
Animation: falling through the air, front view. Arms flailing above her head, legs bent,
skirt and hair blown upward, shocked expression with swirly eyes on frames 2-3. Loops.
```

### Climb — `climb.png`, 4 frames
```text
[character sheet with N=4]
Animation: climbing up a vertical wall that is just off the RIGHT edge of the frame
(do not draw the wall). Side view facing RIGHT, hands reaching up alternately,
knees bent, determined face. Loops.
```

### Thinking — `think.png`, 4 frames
```text
[character sheet with N=4]
Animation: thinking. Front three-quarter view, one hand on her chin, the other arm
crossed under it, eyes looking up and to the side, head tilting a little more in each
frame, small pout. Loops. Do not draw thought bubbles or text.
```

### Working / typing — `work.png`, 4 frames
```text
[character sheet with N=4]
Animation: sitting on the floor facing the viewer with a small open laptop on her lap,
typing quickly; hands alternate up and down on the keyboard across frames, focused face,
tongue slightly out on frame 3. Laptop is plain dark grey #24283b with no logo. Loops.
```

### Needs you (wave) — `wave.png`, 4 frames
```text
[character sheet with N=4]
Animation: waving to get attention. Front view, right arm raised high waving left and
right across the frames, other hand cupped by her mouth as if calling, eager open-mouth
smile, slight bounce on her toes. Loops.
```

### Done / celebrate — `celebrate.png`, 4 frames
```text
[character sheet with N=4]
Animation: celebrating a success. Front view, small jump with both fists in the air,
huge happy smile with closed eyes, hair bouncing. Frame 1 crouch, frame 2 up, frame 3
peak, frame 4 landing. Keep the whole body inside the frame. No confetti (the app adds it).
```

### Thank-you bow — `bow.png`, 4 frames
```text
[character sheet with N=4]
Animation: a polite thank-you bow, front three-quarter view, hands together in front of
her skirt. Frames: standing smiling, bowing 30 degrees, bowing 45 degrees with eyes
closed, coming back up smiling.
```

### Oops / stumble — `oops.png`, 4 frames
```text
[character sheet with N=4]
Animation: tripping and recovering. Front three-quarter view; frame 1 foot catches,
frame 2 leaning forward with arms out for balance and a worried face, frame 3 wobbling
back, frame 4 upright scratching the back of her head with an embarrassed smile and a
small sweat drop.
```

### Talking — `talk.png`, 4 frames
```text
[character sheet with N=4]
Animation: chatting with the viewer, front three-quarter view, one hand gesturing
softly; mouth shapes change across frames (open, half-open, closed smile, "o"),
friendly expression, small head tilts. Loops.
```

### Dance (optional) — `dance.png`, 6 frames
```text
[character sheet with N=6]
Animation: cute simple dance, front view, swaying hips left and right, arms alternating
up, happy closed-eye smile. Loops.
```

### Jump (optional) — `jump.png`, 4 frames
```text
[character sheet with N=4]
Animation: a small jump in place, front view: crouch, take-off with arms up, peak,
landing with knees bent. Feet return to the bottom edge on frames 1 and 4.
```

## 3. Slice and convert into strips (ImageMagick 7)

Gemini rarely returns the exact size, so normalize every image. For a
strip with `N` frames saved as `raw/walk.png`:

```sh
N=6; NAME=walk
mkdir -p out tmp

# 1. Chroma green -> transparent (skip if the background is already transparent).
magick raw/$NAME.png -fuzz 12% -transparent '#00FF00' tmp/$NAME-alpha.png

# 2. Cut into N equal frames (left to right).
magick tmp/$NAME-alpha.png -crop ${N}x1@ +repage tmp/$NAME-%02d.png

# 3. Each frame: trim, fit into 180x400 with feet on the bottom, centered.
for f in tmp/$NAME-[0-9][0-9].png; do
  magick "$f" -trim +repage -resize 172x392 \
    -background none -gravity south -extent 180x400 "$f"
done

# 4. Join them back into one strip.
magick tmp/$NAME-[0-9][0-9].png +append -strip out/$NAME.png
file out/$NAME.png   # -> 1080 x 400 for 6 frames
```

Notes:

- `-trim` per frame keeps the feet on the bottom edge but can make frames of
  one strip different heights; if she "jumps" between frames, skip `-trim`
  and use `-resize 180x400` on the cut frames instead.
- For `hang.png` use `-gravity north` so the hands stay at the top.
- Leftover green fringe: raise `-fuzz` to 18–20%, or add
  `-channel A -morphology Erode Disk:1 +channel` after step 1.
- Copy the strips into `characters/<name>/` and set the frame counts in its
  `sprites.json` (see [sprites.md](sprites.md)).
