import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Desktop chibi: a sprite-animated character that roams across every screen
// and picks her own activity (walk, run, chase the cursor, dance, sit, sleep,
// jump, idle) at random. She can be picked up and dragged with the mouse.
// State lives in global desktop coordinates; each screen has a click-through
// overlay that draws her whenever she overlaps it. Sprite strips: sprites/.
Scope {
  id: root

  // ---- Tweakables ----
  // Sprites are pre-scaled to physical pixels; 1 / monitor scale (1.25) draws
  // them 1:1 with no runtime resampling. Raise it to make her bigger.
  readonly property real sizeScale: 0.8
  readonly property real walkSpeed: 70  // px per second
  readonly property real runSpeed: 240
  readonly property real chaseSpeed: 300
  readonly property int margin: 40      // keep away from screen edges
  readonly property int topMargin: 60   // stay below the bar
  // Relative odds for each activity.
  readonly property var weights: ({ walk: 6, run: 3, chase: 2, idle: 5, dance: 2, sit: 2, jump: 2, sleep: 1 })

  // Frame geometry from sprites/sprites.json, plus playback speed per strip.
  // `sideways` strips are drawn facing right and get mirrored to go left.
  readonly property var anims: ({
    idle:  { frameWidth: 83,  frameHeight: 132, frameCount: 6, frameMs: 240, sideways: false },
    walk:  { frameWidth: 109, frameHeight: 138, frameCount: 6, frameMs: 140, sideways: true },
    dance: { frameWidth: 89,  frameHeight: 135, frameCount: 6, frameMs: 170, sideways: false },
    run:   { frameWidth: 159, frameHeight: 117, frameCount: 7, frameMs: 80,  sideways: true },
    jump:  { frameWidth: 110, frameHeight: 222, frameCount: 4, frameMs: 260, sideways: false },
    sit:   { frameWidth: 103, frameHeight: 109, frameCount: 2, frameMs: 900, sideways: false },
    sleep: { frameWidth: 105, frameHeight: 96,  frameCount: 1, frameMs: 1000, sideways: false },
    hang:  { frameWidth: 110, frameHeight: 222, frameCount: 2, frameMs: 280, sideways: false }
  })

  // ---- State (global desktop coordinates of her anchor box) ----
  readonly property real w: 90 * sizeScale
  readonly property real h: 135 * sizeScale
  property real gx: 0
  property real gy: 0
  property string mode: "idle"
  property real targetX: 0
  property real targetY: 0
  property bool facingRight: true
  property bool caught: false // reached the cursor while chasing
  // Set by `chibi sleep` / `chibi wake` through stateFile: she naps until woken.
  property bool sleepLocked: false
  // Chasing needs `hyprctl cursorpos`; other compositors don't expose the pointer.
  property bool canChase: false
  property real lift: 0
  property real breath: 0
  property real swing: 0      // pendulum angle while held, in degrees
  Behavior on swing { SpringAnimation { spring: 2.5; damping: 0.12 } }

  readonly property real speed: mode === "chase" ? chaseSpeed
                               : mode === "run" ? runSpeed : walkSpeed
  readonly property bool moving: mode === "walk" || mode === "run" || mode === "chase"
  readonly property string anim: mode === "chase" ? (caught ? "dance" : "run")
                               : mode === "held" || mode === "fall" ? "hang"
                               : mode

  function screenAt(x, y) {
    const screens = Quickshell.screens
    for (let i = 0; i < screens.length; i++) {
      const s = screens[i]
      if (x >= s.x && x < s.x + s.width && y >= s.y && y < s.y + s.height) return s
    }
    return screens.length ? screens[0] : null
  }

  function randomPoint() {
    const screens = Quickshell.screens
    if (!screens.length) return
    const s = screens[Math.floor(Math.random() * screens.length)]
    const rw = Math.max(1, s.width - w - margin * 2)
    const rh = Math.max(1, s.height - h - margin - topMargin)
    targetX = s.x + margin + Math.random() * rw
    targetY = s.y + topMargin + Math.random() * rh
  }

  function chaseTo(px, py) {
    if (mode !== "chase") return
    // Stand just below and beside the pointer instead of under it.
    const s = screenAt(px, py)
    targetX = Math.max(s.x, Math.min(s.x + s.width - w, px - w / 2))
    targetY = Math.max(s.y, Math.min(s.y + s.height - h, py + 10))
  }

  function pickNext() {
    if (sleepLocked) {
      caught = false
      mode = "sleep"
      moodTimer.stop()
      return
    }
    const odds = Object.assign({}, weights)
    if (!canChase) delete odds.chase
    let total = 0
    for (const k in odds) total += odds[k]
    let r = Math.random() * total
    let next = "walk"
    for (const k in odds) {
      r -= odds[k]
      if (r <= 0) { next = k; break }
    }
    caught = false
    mode = next
    if (moving && mode !== "chase") randomPoint()
    if (mode === "jump") jumpAnim.restart()
    moodTimer.interval = mode === "sleep" ? 15000 + Math.random() * 25000
                       : mode === "chase" ? 7000 + Math.random() * 6000
                       : mode === "dance" ? 4000 + Math.random() * 5000
                       : mode === "sit" ? 5000 + Math.random() * 8000
                       : mode === "idle" ? 3000 + Math.random() * 5000
                       : mode === "jump" ? 1100
                       : 30000 // walk/run end when the target is reached
    moodTimer.restart()
  }

  // ---- Grabbing (global pointer coordinates) ----
  property real lastGrabX: 0

  function grabStart(px, py) {
    moodTimer.stop()
    jumpAnim.stop()
    fallAnim.stop()
    lift = 0
    mode = "held"
    lastGrabX = px
    grabMove(px, py)
  }

  function grabMove(px, py) {
    swing = Math.max(-40, Math.min(40, (lastGrabX - px) * 3))
    lastGrabX = px
    gx = px - w / 2
    // Hands sit at the top of the hang frame.
    gy = py - (h - anims.hang.frameHeight * sizeScale) + 4
    swingReset.restart()
  }

  function drop() {
    swing = 0
    mode = "fall"
    const s = screenAt(gx + w / 2, gy + h)
    const floor = s ? s.y + s.height - h - margin : gy
    fallAnim.to = Math.max(gy, Math.min(floor, gy + 60))
    fallAnim.duration = Math.max(120, (fallAnim.to - gy) * 4)
    fallAnim.restart()
  }

  // `bin/chibi` writes "sleep" or "awake" here. A file instead of IPC because
  // third-party services are created without a parent, so an IpcHandler in
  // them never registers with the shell.
  FileView {
    id: stateFile
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/danso-chibi/state"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.setSleepLocked(text().trim() === "sleep")
  }

  function setSleepLocked(locked) {
    if (locked === sleepLocked) return
    sleepLocked = locked
    if (mode === "held" || mode === "fall") return // drop() picks next
    if (locked) {
      jumpAnim.stop()
      lift = 0
      pickNext()
    } else if (mode === "sleep") {
      pickNext()
    }
  }

  Timer {
    id: swingReset
    interval: 80
    onTriggered: root.swing = 0
  }

  NumberAnimation {
    id: fallAnim
    target: root
    property: "gy"
    easing.type: Easing.InQuad
    onFinished: if (root.mode === "fall") {
      root.mode = "idle"
      moodTimer.interval = 1500
      moodTimer.restart()
    }
  }

  // ---- Behaviour clock ----
  // Wait until screens are known, then start on the first one.
  Timer {
    interval: 500
    running: true
    onTriggered: {
      const s = Quickshell.screens[0]
      if (s) {
        root.gx = s.x + s.width / 2
        root.gy = s.y + s.height - root.h - root.margin
      }
      root.pickNext()
    }
  }

  Timer {
    id: moodTimer
    onTriggered: root.pickNext()
  }

  Timer {
    interval: 33
    repeat: true
    running: root.moving
    onTriggered: {
      const dx = root.targetX - root.gx
      const dy = root.targetY - root.gy
      const dist = Math.sqrt(dx * dx + dy * dy)
      const step = root.speed * interval / 1000
      if (Math.abs(dx) > 2) root.facingRight = dx > 0
      root.caught = root.mode === "chase" && dist < 8
      if (dist <= step) {
        root.gx = root.targetX
        root.gy = root.targetY
        if (root.mode !== "chase") root.pickNext()
        return
      }
      root.gx += dx / dist * step
      root.gy += dy / dist * step
    }
  }

  SequentialAnimation {
    id: jumpAnim
    NumberAnimation { target: root; property: "lift"; to: 45; duration: 380; easing.type: Easing.OutQuad }
    NumberAnimation { target: root; property: "lift"; to: 0; duration: 380; easing.type: Easing.InQuad }
  }

  // Slow breathing while asleep (the sleep strip is a single frame).
  NumberAnimation on breath {
    from: 0; to: Math.PI * 2; duration: 3000
    loops: Animation.Infinite
    running: root.mode === "sleep"
  }

  Process {
    command: ["sh", "-c", "command -v hyprctl"]
    running: true
    onExited: function(exitCode) {
      root.canChase = exitCode === 0
      if (!root.canChase) console.info("chibi: hyprctl not found, cursor chasing disabled")
    }
  }

  // Cursor position for chasing (global coordinates).
  Process {
    id: cursorProc
    command: ["hyprctl", "cursorpos"]
    stdout: SplitParser {
      onRead: function(line) {
        const parts = line.split(",").map(v => Number(v.trim()))
        if (parts.length === 2 && !isNaN(parts[0])) root.chaseTo(parts[0], parts[1])
      }
    }
  }

  Timer {
    interval: 150
    repeat: true
    running: root.mode === "chase"
    onTriggered: if (!cursorProc.running) cursorProc.running = true
  }

  // ---- One overlay per screen ----
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      screen: modelData
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      WlrLayershell.namespace: "danso-chibi"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      // Only her own box takes pointer input; everything else clicks through.
      mask: Region { item: girl }


      Item {
        id: stage
        anchors.fill: parent

        Item {
          id: girl
          x: root.gx - panel.modelData.x
          y: root.gy - panel.modelData.y
          width: root.w
          height: root.h
          readonly property bool onThisScreen: x + width > -200 && x < stage.width + 200
                                            && y + height > -200 && y < stage.height + 200

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            // The pointer stays grabbed by this surface while pressed, even
            // past its edges, so dragging carries her onto other screens.
            function globalPos(mouse) {
              const p = mapToItem(stage, mouse.x, mouse.y)
              return { x: p.x + panel.modelData.x, y: p.y + panel.modelData.y }
            }
            onPressed: function(mouse) { const g = globalPos(mouse); root.grabStart(g.x, g.y) }
            onPositionChanged: function(mouse) { if (pressed) { const g = globalPos(mouse); root.grabMove(g.x, g.y) } }
            onReleased: root.drop()
          }

          AnimatedSprite {
            id: sprite
            visible: girl.onThisScreen
            readonly property var a: root.anims[root.anim] || root.anims.idle
            source: Qt.resolvedUrl("sprites/" + root.anim + ".png")
            frameWidth: a.frameWidth
            frameHeight: a.frameHeight
            frameCount: a.frameCount
            frameDuration: a.frameMs
            loops: root.anim === "jump" ? 1 : AnimatedSprite.Infinite
            running: visible
            interpolate: false
            smooth: true
            width: a.frameWidth * root.sizeScale
            height: a.frameHeight * root.sizeScale
            x: (root.w - width) / 2
            y: root.h - height - root.lift
            onSourceChanged: restart()
            transform: [
              Scale {
                origin.x: sprite.width / 2
                origin.y: sprite.height
                xScale: sprite.a.sideways && !root.facingRight ? -1 : 1
                yScale: root.mode === "sleep" ? 1 + 0.015 * Math.sin(root.breath) : 1
              },
              // Swings from her hands while held.
              Rotation { origin.x: sprite.width / 2; origin.y: 0; angle: root.swing }
            ]
          }
        }
      }
    }
  }
}
