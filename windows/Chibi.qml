import QtQuick
import QtQuick.Window

// Desktop chibi for Windows: the same behaviour as ../Service.qml, hosted in
// a small frameless, always-on-top window that follows her around instead of
// a full-screen layer-shell overlay. The window ignores the mouse except
// while the pointer is over her box, so the desktop stays clickable.
// `bridge` (chibi.py) supplies the global cursor position, the sprites
// folder and the UDP link to her twin on the Linux PC: she walks off the
// shared edge now and then, and a single click picks her up so she can be
// carried across with the mouse (Deskflow does not switch screens while a
// button is held, so press-and-drag stays on this PC). Only the instance
// where she is `present` draws her.
Window {
  id: root

  // ---- Tweakables ----
  readonly property real sizeScale: 0.8
  readonly property real walkSpeed: 70  // px per second
  readonly property real runSpeed: 240
  readonly property real chaseSpeed: 300
  readonly property int margin: 40      // keep away from screen edges
  readonly property int topMargin: 20
  readonly property int bottomMargin: 60 // stay above the taskbar
  // Relative odds for each activity.
  readonly property var weights: ({ walk: 6, run: 3, chase: 2, idle: 5, dance: 2, sit: 2, jump: 2, sleep: 1 })
  // With the other PC linked, share of walks and runs that cross to it.
  readonly property real visitChance: 0.4

  // Frame geometry from ../sprites/sprites.json, plus playback speed per strip.
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
  // Toggled from the tray menu: she naps until woken.
  property bool sleepLocked: false
  property real lift: 0
  property real breath: 0

  // ---- Link with the twin on the other PC ----
  property bool present: false   // she is on this PC
  property bool started: false   // startup decided where she is
  readonly property string peerSide: bridge.peerSide
  readonly property bool primary: bridge.primary
  property real peerSeenAt: 0
  property bool peerHasHer: false
  property bool visiting: false  // walking off towards the other PC
  property bool awaitingAck: false
  property bool carryWaiting: false // just arrived carried: waits for this PC's pointer
  property real carryFromX: NaN
  property real carryFromY: NaN
  property bool carryArmed: true  // carried her far enough from the edge to hand her back
  property real handedAt: 0      // when she last left for the other PC
  property real swing: 0      // pendulum angle while held, in degrees
  Behavior on swing { SpringAnimation { spring: 2.5; damping: 0.12 } }

  readonly property real speed: mode === "chase" ? chaseSpeed
                               : mode === "run" ? runSpeed : walkSpeed
  readonly property bool moving: mode === "walk" || mode === "run" || mode === "chase"
  readonly property string anim: mode === "chase" ? (caught ? "dance" : "run")
                               : mode === "held" || mode === "fall" || mode === "carried" ? "hang"
                               : mode === "away" ? "idle"
                               : mode

  // ---- Window: big enough for the tallest frame, her box at bottom centre ----
  readonly property int stageWidth: 200
  readonly property int stageHeight: 260
  readonly property real boxX: (stageWidth - w) / 2
  readonly property real boxY: stageHeight - h

  width: stageWidth
  height: stageHeight
  x: Math.round(gx - boxX)
  y: Math.round(gy - boxY)
  visible: true
  color: "transparent"
  title: "Desktop chibi"
  flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool | Qt.NoDropShadowWindowHint
         | (interactive ? 0 : Qt.WindowTransparentForInput)

  property bool interactive: false

  function screens() {
    const list = Qt.application.screens
    const out = []
    for (let i = 0; i < list.length; i++)
      out.push({ x: list[i].virtualX, y: list[i].virtualY, width: list[i].width, height: list[i].height })
    return out
  }

  function screenAt(x, y) {
    const list = screens()
    for (let i = 0; i < list.length; i++) {
      const s = list[i]
      if (x >= s.x && x < s.x + s.width && y >= s.y && y < s.y + s.height) return s
    }
    return list.length ? list[0] : null
  }

  function randomPoint() {
    const list = screens()
    if (!list.length) return
    const s = list[Math.floor(Math.random() * list.length)]
    const rw = Math.max(1, s.width - w - margin * 2)
    const rh = Math.max(1, s.height - h - bottomMargin - topMargin)
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
  // A function, not a binding: it has to see the clock move.
  function linkUp() {
    return peerSeenAt > 0 && Date.now() - peerSeenAt < 6000
  }

  function edgeScreen() {
    const list = screens()
    let best = null
    for (let i = 0; i < list.length; i++) {
      const s = list[i]
      if (!best || (peerSide === "left" ? s.x < best.x : s.x + s.width > best.x + best.width)) best = s
    }
    return best
  }

  // Pointer speed towards the shared edge, in px per ms, smoothed.
  property real edgeLastX: 0
  property real edgeLastAt: 0
  property real edgeSpeed: 0

  function atEdge(px) {
    const s = edgeScreen()
    if (!s) return false
    const now = Date.now()
    const dt = now - edgeLastAt
    const toward = peerSide === "left" ? edgeLastX - px : px - edgeLastX
    edgeSpeed = dt > 0 && dt < 200 ? edgeSpeed * 0.5 + toward / dt * 0.5 : 0
    edgeLastX = px
    edgeLastAt = now
    // A fast pointer reaches the edge between two samples and Deskflow takes
    // it away before the last one, so the edge widens with the speed towards
    // it: about 80 ms ahead, from 2 px when still up to 150 px.
    const zone = Math.max(2, Math.min(150, edgeSpeed * 80))
    return peerSide === "left" ? px <= s.x + zone : px >= s.x + s.width - 1 - zone
  }

  function send(message) {
    bridge.send(JSON.stringify(message))
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
    gy = Math.max(s.y + topMargin, Math.min(s.y + s.height - h - bottomMargin, s.y + yr * s.height))
    gx = peerSide === "left" ? s.x - w : s.x + s.width
    facingRight = peerSide === "left"
    if (message.mode === "carry") {
      // The pointer arrives on the edge itself: wait until it moves away
      // before the edge can send her back, or she bounces between PCs.
      carryArmed = false
      carryWaiting = true
      carryFromX = NaN
      gx = peerSide === "left" ? s.x : s.x + s.width - w
      mode = "carried"
      moodTimer.stop()
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
    gy = Math.max(s.y + topMargin, Math.min(s.y + s.height - h - bottomMargin, gy))
    pickNext()
  }

  // Nobody has her (the other PC quit or went silent): the primary takes her
  // back. Skipped right after a hand-off, while pings from before it arrive.
  function reclaimIfLost() {
    if (present || !started || awaitingAck || Date.now() - handedAt < 5000) return
    if (!linkUp() || (!peerHasHer && primary)) comeBack()
  }

  function handleMessage(message) {
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
      targetY = s.y + topMargin + Math.random() * Math.max(1, s.height - h - bottomMargin - topMargin)
      // Time enough to reach the edge from the far screen, plus slack.
      moodTimer.interval = Math.abs(targetX - gx) / speed * 1000 + 10000
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
  // with a link to cross; on her own a click just drops her.
  function release(px, py) {
    if (mode !== "held") return
    const still = Math.abs(px - grabStartX) < 6 && Math.abs(py - grabStartY) < 6
    if (bridge.linkEnabled && still && Date.now() - grabStartedAt < 300) {
      carryArmed = true
      mode = "carried"
      return
    }
    drop()
  }

  function carryMove(px, py) {
    if (mode !== "carried") return
    // Arrived from the other PC: stay put until this PC's pointer moves, as
    // it may still sit elsewhere while Deskflow switches screens.
    if (carryWaiting) {
      if (isNaN(carryFromX)) { carryFromX = px; carryFromY = py; return }
      if (Math.abs(px - carryFromX) + Math.abs(py - carryFromY) < 3) return
      carryWaiting = false
    }
    const s = edgeScreen()
    if (!carryArmed && s && (peerSide === "left" ? px > s.x + 40 : px < s.x + s.width - 40)) carryArmed = true
    if (carryArmed && linkUp() && atEdge(px)) {
      handOff("carry")
      return
    }
    grabMove(px, py)
  }

  // Dragged onto the shared edge: Deskflow keeps the pointer on this PC while
  // the button is held, so she goes ahead and waits for it on the other one.
  function dragMove(px, py) {
    if (linkUp() && atEdge(px)) {
      swing = 0
      handOff("carry")
      return
    }
    grabMove(px, py)
  }

  function drop() {
    swing = 0
    mode = "fall"
    const s = screenAt(gx + w / 2, gy + h)
    const floor = s ? s.y + s.height - h - bottomMargin : gy
    fallAnim.to = Math.max(gy, Math.min(floor, gy + 60))
    fallAnim.duration = Math.max(120, (fallAnim.to - gy) * 4)
    fallAnim.restart()
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

  Connections {
    target: bridge
    function onSleepRequested(locked) { root.setSleepLocked(locked) }
    function onMessageReceived(text) {
      let message = null
      try { message = JSON.parse(text) } catch (e) { return }
      root.handleMessage(message)
    }
  }

  Timer {
    interval: 2000
    repeat: true
    running: bridge.linkEnabled
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
  // Give the twin a chance to say she is over there before starting here.
  Timer {
    interval: bridge.linkEnabled ? 2500 : 0
    running: true
    onTriggered: {
      if (root.started) return
      root.started = true
      if (root.peerHasHer) { root.mode = "away"; return }
      const s = root.screens()[0]
      if (s) {
        root.gx = s.x + s.width / 2
        root.gy = s.y + s.height - root.h - root.bottomMargin
      }
      root.present = true
      root.pickNext()
    }
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

  // Pointer tracking: chase target, and whether the window takes the mouse.
  // Only her box is interactive; while held she keeps the mouse until release.
  // While carried the whole window takes the mouse, to catch the click that
  // drops her.
  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      const p = bridge.cursorPos()
      if (root.mode === "chase") root.chaseTo(p.x, p.y)
      const over = root.present && p.x >= root.gx && p.x < root.gx + root.w
                && p.y >= root.gy - root.lift && p.y < root.gy + root.h
      const want = over || root.mode === "held" || root.mode === "carried"
      if (want !== root.interactive) root.interactive = want
    }
  }

  // While carried she follows the pointer on every rendered frame.
  FrameAnimation {
    running: root.mode === "carried"
    onTriggered: {
      const p = bridge.cursorPos()
      root.carryMove(p.x, p.y)
    }
  }

  MouseArea {
    anchors.fill: parent
    enabled: root.mode === "carried"
    cursorShape: Qt.ClosedHandCursor
    onClicked: root.drop()
  }

  Item {
    id: girl
    x: root.boxX
    y: root.boxY
    width: root.w
    height: root.h

    MouseArea {
      anchors.fill: parent
      enabled: root.present && root.mode !== "carried"
      hoverEnabled: true
      cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
      // The window moves with her while dragging, so local coordinates are
      // useless; the global cursor drives the grab instead.
      onPressed: { const g = bridge.cursorPos(); root.grabStart(g.x, g.y) }
      onPositionChanged: if (pressed) { const g = bridge.cursorPos(); root.dragMove(g.x, g.y) }
      onReleased: { const g = bridge.cursorPos(); root.release(g.x, g.y) }
    }

    AnimatedSprite {
      id: sprite
      visible: root.present
      readonly property var a: root.anims[root.anim] || root.anims.idle
      source: bridge.spritesUrl + "/" + root.anim + ".png"
      frameWidth: a.frameWidth
      frameHeight: a.frameHeight
      frameCount: a.frameCount
      frameDuration: a.frameMs
      loops: root.anim === "jump" ? 1 : AnimatedSprite.Infinite
      running: true
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
