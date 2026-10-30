# Desktop chibi for Omarchy

<p align="center">
  <img src="docs/poses.png" alt="All eight poses: idle, walk, run, dance, jump, sit, sleep and hang">
</p>

A little chibi character that lives on your desktop. She roams across every
screen on her own and picks what to do at random: walk, run, chase your
cursor, dance, sit, jump, idle or take a nap. Grab her with the mouse and she
dangles from your cursor; let go and she drops back down.

It is built with [Quickshell](https://quickshell.org) (QML). It runs as an
[Omarchy](https://omarchy.org) plugin or standalone on any distro, and works
with any character you want: swap the sprites and you have your own.

Everything else stays click-through: only her own box takes mouse input.

## Requirements

- A **Wayland** compositor with the layer-shell protocol: Hyprland, Sway,
  KDE Plasma, niri, river, Wayfire... GNOME is **not** supported (no
  layer-shell).
- [Quickshell](https://quickshell.org/docs/master/guide/install-setup).
- Chasing the cursor only works on **Hyprland** (it uses `hyprctl cursorpos`).
  On other compositors she does everything else and simply never chases.

## Install

### Omarchy

```sh
omarchy plugin add https://github.com/DanielPuertaBernal/omarchy-desktop-chibi.git --enable
```

Optional: a `chibi` command to turn her on and off from the terminal:

```sh
ln -s ~/.config/omarchy/plugins/danso.chibi/bin/chibi ~/.local/bin/chibi

chibi          # toggle
chibi on       # turn on
chibi off      # turn off
chibi status   # prints on / off
chibi sleep    # nap until woken
chibi wake     # roam again
```

### Any distro (standalone)

1. Install Quickshell:

   | Distro         | Command                                                                 |
   |----------------|-------------------------------------------------------------------------|
   | Arch and derivatives | `sudo pacman -S quickshell`                                       |
   | Fedora         | `sudo dnf copr enable errornointernet/quickshell && sudo dnf install quickshell` |
   | Debian testing / unstable | `sudo apt install quickshell`                                 |
   | Others         | see the [Quickshell install guide](https://quickshell.org/docs/master/guide/install-setup) |

2. Get the chibi and run her:

   ```sh
   git clone https://github.com/DanielPuertaBernal/omarchy-desktop-chibi.git ~/.local/share/desktop-chibi
   quickshell -p ~/.local/share/desktop-chibi
   ```

3. Start her with your session:

   - Hyprland (`~/.config/hypr/hyprland.conf`):
     `exec-once = quickshell -p ~/.local/share/desktop-chibi`
   - Sway (`~/.config/sway/config`):
     `exec quickshell -p ~/.local/share/desktop-chibi`
   - KDE Plasma and others: add the same command in your autostart settings.

To stop her: `pkill -f desktop-chibi`.

### Windows

The `windows/` folder runs the same behaviour on Windows with Qt Quick
(PySide6): a small frameless, always-on-top window follows her around and
only takes the mouse while the pointer is over her. A tray icon puts her to
sleep, wakes her up or quits.

Build a standalone `chibi.exe` (needs [Python](https://www.python.org/downloads/windows/) 3.10+):

```powershell
cd windows
.\build.ps1
.\dist\chibi.exe
```

Or run it without building: `pip install PySide6`, then `python chibi.py`.

To start her with Windows, put a shortcut to `chibi.exe` in the Startup
folder (`Win + R`, then `shell:startup`).

### One chibi across two PCs (Deskflow)

If you share one mouse between a Linux and a Windows PC with
[Deskflow](https://github.com/deskflow/deskflow), both copies can share a
single chibi over the local network: she walks or runs off the shared edge
and on into the other PC on her own, and you can carry her across.

- **Carry her:** click her once (no drag) and she hangs from the cursor; move
  to the other PC as usual and click again to drop her. Press-and-drag still
  works, but only within one PC: Deskflow does not switch screens while a
  mouse button is held.
- Only one copy shows her at a time. If the other PC goes away, she comes
  back on her own.

Configure each side with the other PC's address and where it sits, matching
your Deskflow layout. The Linux side is the `primary` (it keeps her if both
start at once).

Linux, `~/.config/danso-chibi/link.json` (the Windows PC is on the left):

```json
{ "peer": "192.168.1.20", "port": 47800, "side": "left", "primary": true }
```

Windows, `link.json` next to `chibi.exe` (see `windows/link.example.json`):

```json
{ "peer": "192.168.1.10", "port": 47800, "side": "right", "primary": false }
```

Allow UDP port 47800 between the two PCs: on Linux with ufw,
`sudo ufw allow from <windows-ip> to any port 47800 proto udp`; on Windows,
accept the firewall prompt the first time `chibi.exe` starts (private
networks).

## Tweak her

Edit the `Tweakables` block at the top of `Service.qml`:

| Property     | What it does                                         |
|--------------|------------------------------------------------------|
| `sizeScale`  | Size multiplier (raise it to make her bigger)        |
| `walkSpeed`, `runSpeed`, `chaseSpeed` | Speeds in px per second     |
| `margin`, `topMargin` | Distance kept from screen edges / the bar   |
| `weights`    | Relative odds of each activity                       |
| `visitChance` | Share of walks and runs that cross to the linked PC |

## Make your own character

Anyone can add a character. You only need a set of sprite strips; the code
stays the same.

### 1. Make the sprites

Each animation is **one PNG file with all frames side by side in a single
row** (a horizontal strip), on a transparent background:

```
walk.png   [frame 1][frame 2][frame 3][frame 4][frame 5][frame 6]
```

- All frames in a strip have the same width and height.
- The strip width is `frameWidth × frameCount`.
- `walk.png` and `run.png` must face **right**; they are mirrored automatically
  to walk left. The others can face the viewer.
- `sleep.png` can be a single frame; she "breathes" on her own.
- `hang.png` is used while held and while falling: draw her hanging by her
  hands, with the hands at the top of the frame.

The plugin uses these eight animations, so provide all of them:

| File        | Used for                         | Frames (current) |
|-------------|----------------------------------|------------------|
| `idle.png`  | standing still                   | 6                |
| `walk.png`  | walking (faces right)            | 6                |
| `run.png`   | running and chasing (faces right)| 7                |
| `dance.png` | dancing, celebrating the cursor  | 6                |
| `jump.png`  | jumping                          | 4                |
| `sit.png`   | sitting                          | 2                |
| `sleep.png` | napping                          | 1                |
| `hang.png`  | held by the mouse / falling      | 2                |

The included sprites were generated with **Google Gemini** and then cut into
strips. Any image generator or pixel-art tool works. Tips for AI generation:
ask for a "sprite sheet, single row, N frames, same character, same size,
transparent background, side view facing right" and keep the same character
description for every animation so she looks consistent.

### 2. Describe the frames

Update the frame sizes in **both** places (they must match):

- `sprites/sprites.json`:
  ```json
  "walk": { "frameWidth": 109, "frameHeight": 138, "frameCount": 6 }
  ```
- the `anims` block in `Service.qml`, which also sets the playback speed
  (`frameMs`, milliseconds per frame) and whether the strip is mirrored
  (`sideways: true` for `walk` and `run`):
  ```qml
  walk: { frameWidth: 109, frameHeight: 138, frameCount: 6, frameMs: 140, sideways: true },
  ```

To get `frameWidth`, divide the PNG width by the number of frames
(`file sprites/walk.png` shows the size).

### 3. Give your plugin its own id

To keep your character next to this one (or share it), copy the folder and
edit `manifest.json`:

```json
{
  "id": "yourname.chibi",
  "name": "My desktop chibi",
  "author": "yourname",
  "description": "..."
}
```

The `id` must be unique; use the same name for the folder.

### 4. Try it

```sh
cp -r my-chibi ~/.config/omarchy/plugins/yourname.chibi
omarchy plugin validate ~/.config/omarchy/plugins/yourname.chibi
omarchy plugin enable yourname.chibi
```

Standalone (no Omarchy): `quickshell -p my-chibi`.

Publish your folder as a git repo and others can install your character with
`omarchy plugin add <your-repo-url> --enable`. Pull requests that add new
characters or animations here are welcome too.

## Credits

- Code: Daniel Puerta Bernal.
- Sprites: generated with Google Gemini.

## License

MIT, see [LICENSE](LICENSE).
