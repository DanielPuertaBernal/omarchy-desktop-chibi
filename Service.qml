import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Desktop chibi: a sprite-animated character that roams across every screen
// and picks her own activity (walk, run, chase the cursor, dance, sit, sleep,
// jump, idle) at random. She can be picked up and dragged with the mouse.
// State lives in global desktop coordinates; each screen has a click-through
// overlay that draws her whenever she overlaps it. Sprite strips: sprites/.
//
// With bin/chibi-link configured she shares one life with her twin on another
// PC (see windows/): she walks off the edge towards it now and then, and a
// single click picks her up so she can be carried across with the mouse
// (Deskflow does not switch screens while a button is held, so press-and-drag
// stays on this PC). Only the instance where she is `present` draws her.
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
  // With the other PC linked, share of walks and runs that cross to it.
  readonly property real visitChance: 0.4

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

  // ---- Link with the twin on the other PC (bin/chibi-link) ----
  property bool present: false     // she is on this PC
  property bool started: false     // startup decided where she is
  property string peerSide: "left" // where the other PC sits, per Deskflow
  property bool primary: true      // keeps her if both instances claim her
  property bool linkOn: false      // chibi-link found a config and is running
  property real peerSeenAt: 0
  property bool peerHasHer: false
  property bool visiting: false    // walking off towards the other PC
  property bool awaitingAck: false
  property real handedAt: 0        // when she last left for the other PC

  // A function, not a binding: it has to see the clock move.
  function linkUp() {
    return peerSeenAt > 0 && Date.now() - peerSeenAt < 6000
  }

  // Nobody has her (the other PC quit or went silent): the primary takes her
  // back. Skipped right after a hand-off, while pings from before it arrive.
  function reclaimIfLost() {
    if (present || !started || awaitingAck || Date.now() - handedAt < 5000) return
    if (!linkUp() || (!peerHasHer && primary)) comeBack()
  }
  property real lift: 0
  property real breath: 0
  property real swing: 0      // pendulum angle while held, in degrees
  Behavior on swing { SpringAnimation { spring: 2.5; damping: 0.12 } }

  readonly property real speed: mode === "chase" ? chaseSpeed
                               : mode === "run" ? runSpeed : walkSpeed
  readonly property bool moving: mode === "walk" || mode === "run" || mode === "chase"
  readonly property string anim: mode === "chase" ? (caught ? "dance" : "run")
                               : mode === "held" || mode === "fall" || mode === "carried" ? "hang"
                               : mode === "away" ? "idle"
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

  // ---- Edge shared with the other PC ----
  function edgeScreen() {
    const screens = Quickshell.screens
    let best = null
    for (let i = 0; i < screens.length; i++) {
      const s = screens[i]
      if (!best || (peerSide === "left" ? s.x < best.x : s.x + s.width > best.x + best.width)) best = s
    }
    return best
  }

  function atEdge(px) {
    const s = edgeScreen()
    return s && (peerSide === "left" ? px <= s.x + 1 : px >= s.x + s.width - 2)
  }

  function send(message) {
    if (linkProc.running) linkProc.write(JSON.stringify(message) + "\n")
  }

  function handOff(kind) {
    const s = edgeScreen()
    const yr = s ? Math.max(0, Math.min(1, (gy - s.y) / s.height)) : 0.5
    send({ t: "enter", mode: kind, gait: mode, yr: yr })
    moodTimer.stop()
    jumpAnim.stop()
    fallAnim.stop()
    visiting = false
    present = false
    mode = "away"
    awaitingAck = true
    handedAt = Date.now()
    ackTimer.restart()
  }

  // She arrives from the other PC, just outside the shared edge.
  function arrive(message) {
    const s = edgeScreen()
    if (!s) return
    present = true
    started = true
    visiting = false
    lift = 0
    const yr = Number(message.yr) || 0.5
    gy = Math.max(s.y + topMargin, Math.min(s.y + s.height - h - margin, s.y + yr * s.height))
    gx = peerSide === "left" ? s.x - w : s.x + s.width
    facingRight = peerSide === "left"
    if (message.mode === "carry") {
      mode = "carried"
      moodTimer.stop()
      if (canChase && !cursorProc.running) cursorProc.running = true
    } else {
      mode = message.gait === "run" ? "run" : "walk"
      targetX = peerSide === "left" ? s.x + margin + Math.random() * 300
                                    : s.x + s.width - w - margin - Math.random() * 300
      targetY = gy
      moodTimer.interval = 30000
      moodTimer.restart()
    }
  }

  // Back on this side of the edge when the other PC never took her.
  function comeBack() {
    const s = edgeScreen()
    if (!s) return
    present = true
    gx = peerSide === "left" ? s.x + margin : s.x + s.width - w - margin
    gy = Math.max(s.y + topMargin, Math.min(s.y + s.height - h - margin, gy))
    pickNext()
  }

  function handleMessage(message) {
    if (message.t === "config") {
      peerSide = message.side === "right" ? "right" : "left"
      primary = message.primary !== false
      linkOn = true
      return
    }
    peerSeenAt = Date.now()
    if (message.t === "ping") {
      peerHasHer = message.has === true
      // Both claim her (started together): the secondary lets go.
      if (peerHasHer && present && !primary && mode !== "held" && mode !== "carried") {
        present = false
        mode = "away"
        moodTimer.stop()
      }
      reclaimIfLost()
    } else if (message.t === "enter") {
      if (present) return // no ack: the sender keeps her
      send({ t: "ack" })
      arrive(message)
    } else if (message.t === "ack") {
      awaitingAck = false
      ackTimer.stop()
    }
  }

  function pickNext() {
    if (!present) return
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
    if ((next === "walk" || next === "run") && linkUp() && Math.random() < visitChance) {
      // Head off the shared edge; the move loop hands her over there.
      const s = edgeScreen()
      visiting = true
      mode = next
      targetX = peerSide === "left" ? s.x - w - 10 : s.x + s.width + 10
      targetY = s.y + topMargin + Math.random() * Math.max(1, s.height - h - margin - topMargin)
      moodTimer.interval = 30000
      moodTimer.restart()
      return
    }
    visiting = false
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
  property real grabStartX: 0
  property real grabStartY: 0
  property real grabStartedAt: 0

  function grabStart(px, py) {
    grabStartX = px
    grabStartY = py
    grabStartedAt = Date.now()
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

  // A press released quickly without moving is a click: carry her, but only
  // with a link to cross; on her own a click just drops her as before.
  function release(px, py) {
    const still = Math.abs(px - grabStartX) < 6 && Math.abs(py - grabStartY) < 6
    if (linkOn && still && Date.now() - grabStartedAt < 300) {
      mode = "carried"
      return
    }
    drop()
  }

  function carryMove(px, py) {
    if (mode !== "carried") return
    if (linkUp() && atEdge(px)) {
      handOff("carry")
      return
    }
    grabMove(px, py)
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
    if (!present || mode === "held" || mode === "fall" || mode === "carried") return // drop() picks next
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
  // Wait until screens are known and the twin had a chance to say she is
  // over there, then start on the first screen.
  Timer {
    interval: root.linkOn ? 2500 : 500
    running: true
    onTriggered: {
      if (root.started) return
      root.started = true
      if (root.peerHasHer) { root.mode = "away"; return }
      const s = Quickshell.screens[0]
      if (s) {
        root.gx = s.x + s.width / 2
        root.gy = s.y + s.height - root.h - root.margin
      }
      root.present = true
      root.pickNext()
    }
  }

  Process {
    id: linkProc
    command: ["python3", String(Qt.resolvedUrl("bin/chibi-link")).replace("file://", "")]
    running: true
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) {
        let message = null
        try { message = JSON.parse(line) } catch (e) { return }
        root.handleMessage(message)
      }
    }
  }

  Timer {
    interval: 2000
    repeat: true
    running: linkProc.running
    onTriggered: {
      // In transit she still counts as ours, so the peer never reclaims her
      // between our hand-off and its ack.
      root.send({ t: "ping", has: root.present || root.awaitingAck })
      root.reclaimIfLost()
    }
  }

  Timer {
    id: ackTimer
    interval: 1500
    onTriggered: if (root.awaitingAck) { root.awaitingAck = false; root.comeBack() }
  }

  Timer {
    id: moodTimer
    onTriggered: root.pickNext()
  }

  // Steps once per rendered frame, sized by the frame time, so she glides
  // at the display's refresh rate. A stalled frame is capped so she never jumps.
  FrameAnimation {
    running: root.moving
    onTriggered: {
      const dx = root.targetX - root.gx
      const dy = root.targetY - root.gy
      const dist = Math.sqrt(dx * dx + dy * dy)
      const step = root.speed * Math.min(frameTime, 0.1)
      if (Math.abs(dx) > 2) root.facingRight = dx > 0
      root.caught = root.mode === "chase" && dist < 8
      if (dist <= step) {
        root.gx = root.targetX
        root.gy = root.targetY
        if (root.visiting) root.handOff("walk")
        else if (root.mode !== "chase") root.pickNext()
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
        if (parts.length !== 2 || isNaN(parts[0])) return
        if (root.mode === "carried") root.carryMove(parts[0], parts[1])
        else root.chaseTo(parts[0], parts[1])
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
      // While carried the whole overlay takes it, to follow the pointer and
      // catch the click that drops her.
      mask: Region { item: root.mode === "carried" ? stage : girl }


      Item {
        id: stage
        anchors.fill: parent

        MouseArea {
          anchors.fill: parent
          enabled: root.mode === "carried"
          hoverEnabled: true
          cursorShape: Qt.ClosedHandCursor
          onPositionChanged: function(mouse) {
            root.carryMove(mouse.x + panel.modelData.x, mouse.y + panel.modelData.y)
          }
          onClicked: root.drop()
        }

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
            enabled: root.present && root.mode !== "carried"
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
            onReleased: function(mouse) { const g = globalPos(mouse); root.release(g.x, g.y) }
          }

          AnimatedSprite {
            id: sprite
            visible: girl.onThisScreen && root.present
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
