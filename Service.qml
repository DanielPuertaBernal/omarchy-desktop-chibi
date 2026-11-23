import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Desktop chibi: a sprite-animated character that roams across every screen
// and picks her own activity (walk, run, chase the cursor, dance, sit, sleep,
// jump, climb a screen edge, peek from the bottom, idle) at random. She can be
// dragged and thrown with the mouse. State lives in global desktop
// coordinates; each screen has a click-through overlay that draws her
// whenever she overlaps it.
//
// The character (sprite strips + sprites.json) is chosen in personality.json
// (`character`): characters/kumo is the default, sprites/ is the original
// chibi. See docs/sprites.md.
//
// bin/chibi-brain gives her a voice: click her to chat (Ollama or Gemini),
// she says idle lines now and then, and she reacts to AI coding agents
// (Claude Code hooks post to a local bridge, see docs/agent-hooks.md).
//
// With bin/chibi-link configured she shares one life with her twin on another
// PC (see windows/): she walks off the edge towards it now and then, and a
// right click picks her up so she can be carried across with the mouse
// (Deskflow does not switch screens while a button is held, so press-and-drag
// stays on this PC). Only the instance where she is `present` draws her.
Scope {
  id: root

  // ---- Tweakables ----
  readonly property real walkSpeed: 70  // px per second
  readonly property real runSpeed: 240
  readonly property real chaseSpeed: 300
  readonly property real climbSpeed: 45
  readonly property real gravity: 2200  // px per second², for throws and falls
  readonly property int margin: 40      // keep away from screen edges
  readonly property int topMargin: 60   // stay below the bar
  readonly property int sleepAfterIdleSec: 300 // nap when the cursor sits still this long (Hyprland)
  // Relative odds for each activity.
  readonly property var weights: ({ walk: 6, run: 3, chase: 2, idle: 5, dance: 2, sit: 2, jump: 2, sleep: 1, climb: 1, peek: 1 })

  // ---- Character (loaded from <character>/sprites.json) ----
  // Repo-relative ("characters/kumo") or absolute (a user character in
  // ~/.config/danso-chibi/characters/<name>, resolved by chibi-brain).
  property string charDir: "characters/kumo"
  function charUrl(file) {
    const p = charDir + "/" + file
    return p[0] === "/" ? "file://" + p : Qt.resolvedUrl(p)
  }
  property var anims: ({})
  property bool animsReady: false
  property real sizeScale: 1
  property real boxW: 180
  property real boxH: 400
  // A missing strip falls back to the nearest existing one, so a character
  // with only the original eight strips still plays every state.
  readonly property var animFallback: ({
    fall: "hang", climb: "hang", think: "idle", work: "sit", wave: "dance",
    celebrate: "dance", bow: "idle", oops: "hang", talk: "idle",
    dance: "celebrate", jump: "idle", run: "walk", hang: "idle", sit: "idle", sleep: "sit"
  })
  readonly property var defaultFrameMs: ({ walk: 140, run: 80, sit: 900, sleep: 1000, jump: 260, hang: 280, idle: 240 })

  function animFor(name) {
    let n = name
    for (let i = 0; i < 4 && n; i++) {
      if (anims[n]) return n
      n = animFallback[n]
    }
    return anims.idle ? "idle" : Object.keys(anims)[0] || "idle"
  }

  function loadCharacter(text) {
    let data = null
    try { data = JSON.parse(text) } catch (e) { console.warn("chibi: bad sprites.json in " + charDir); return }
    const meta = data._meta || {}
    const result = {}
    for (const k in data) {
      if (k[0] === "_") continue
      const a = data[k]
      result[k] = {
        frameWidth: a.frameWidth, frameHeight: a.frameHeight, frameCount: a.frameCount,
        frameMs: a.frameMs || defaultFrameMs[k] || 160,
        sideways: a.sideways !== undefined ? a.sideways : (k === "walk" || k === "run" || k === "climb"),
        // Procedural motion for strips with few frames: breathe | bounce | sway
        motion: a.motion || ""
      }
    }
    anims = result
    if (userScale <= 0) sizeScale = meta.scale || 1
    const box = meta.box || [result.idle ? result.idle.frameWidth : 90, result.idle ? result.idle.frameHeight : 135]
    boxW = box[0]
    boxH = box[1]
    animsReady = true
  }

  FileView {
    id: charFile
    path: root.charUrl("sprites.json")
    printErrors: true
    onLoaded: root.loadCharacter(text())
  }

  // ---- Personality and brain (bin/chibi-brain) ----
  property string petName: ""
  property var idleLines: []
  property bool idleChatter: true
  property int idleChatterMinSec: 180
  property real userScale: 0 // personality.json `scale`; 0 = the character's own
  // personality.json `home`: a screen corner she stays in (bottom-right,
  // bottom-left, top-right, top-left) or "roam" to wander every screen.
  property string home: "bottom-right"
  readonly property bool homebody: home !== "roam" && home !== ""

  // ---- State (global desktop coordinates of her anchor box) ----
  readonly property real w: boxW * sizeScale
  readonly property real h: boxH * sizeScale
  property real gx: 0
  property real gy: 0
  property string mode: "idle"
  property real targetX: 0
  property real targetY: 0
  property bool facingRight: true
  property bool caught: false // reached the cursor while chasing
  property string afterArrive: "" // "climb" or "peek" once a walk ends
  // Set by `chibi sleep` / `chibi wake` through stateFile: she naps until woken.
  property bool sleepLocked: false
  property bool autoSleep: false // asleep because the user went idle
  // Chasing needs `hyprctl cursorpos`; other compositors don't expose the pointer.
  property bool canChase: false
  // Throw / fall physics
  property real vx: 0
  property real vy: 0
  property real floorY: 0

  // ---- Chat ----
  property bool chatOpen: false
  property string chatScreen: ""
  property int chatId: 0
  property bool chatBusy: false
  ListModel { id: chatLog }

  // ---- Speech bubble ----
  property string bubbleText: ""
  function say(text, ms) {
    bubbleText = text
    bubbleTimer.interval = ms || 5000
    bubbleTimer.restart()
  }

  // ---- AI agent reactions (from the brain's bridge) ----
  property string agentState: "idle" // idle|thinking|working|needs|oops|done|thanks
  property string agentDetail: ""
  property real agentSeenAt: 0
  property string pendingAgent: ""   // persistent state to show after a transient one
  property string pendingDetail: ""
  readonly property var reactAnim: ({ thinking: "think", working: "work", needs: "wave", done: "celebrate", thanks: "bow", oops: "oops" })
  readonly property bool agentBusy: agentState === "thinking" || agentState === "working" || agentState === "needs"

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
  // Current strip's procedural motion (sprites.json `motion`), and its phase.
  readonly property string motion: (anims[anim] && anims[anim].motion) || ""
  property real motionT: 0
  property real swing: 0      // pendulum angle while held, in degrees
  Behavior on swing { SpringAnimation { spring: 2.5; damping: 0.12 } }

  readonly property real speed: mode === "chase" ? chaseSpeed
                               : mode === "run" ? runSpeed : walkSpeed
  readonly property bool moving: mode === "walk" || mode === "run" || mode === "chase"
  readonly property bool airborne: mode === "fall" || mode === "climb"
  readonly property bool busyHands: mode === "held" || mode === "fall" || mode === "carried"
  readonly property string anim: animFor(
      mode === "chase" ? (caught ? "dance" : "run")
    : mode === "held" || mode === "carried" ? "hang"
    : mode === "fall" ? "fall"
    : mode === "away" || mode === "peek" ? "idle"
    : mode === "talk" ? (chatBusy ? "talk" : "idle")
    : mode === "react" ? (reactAnim[agentState] || "idle")
    : mode)

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

  // Her corner on the screen she is on (or the first screen).
  function homePoint() {
    const s = screenAt(gx + w / 2, gy + h / 2)
    if (!s) return null
    const inset = 24
    const right = home.indexOf("left") < 0
    const top = home.indexOf("top") === 0
    return {
      x: right ? s.x + s.width - w - inset : s.x + inset,
      y: top ? s.y + topMargin : s.y + s.height - h - 8
    }
  }

  // Homebody routine: walk back to the corner if she is away from it,
  // otherwise sit, stand or nap there.
  function pickHome() {
    caught = false
    afterArrive = ""
    visiting = false
    const p = homePoint()
    if (p && (Math.abs(gx - p.x) > 6 || Math.abs(gy - p.y) > 6)) {
      mode = "walk"
      targetX = p.x
      targetY = p.y
      moodTimer.interval = 30000
      moodTimer.restart()
      return
    }
    const r = Math.random()
    mode = r < 0.6 ? "sit" : r < 0.85 ? "idle" : "sleep"
    moodTimer.interval = mode === "sleep" ? 30000 + Math.random() * 60000
                       : mode === "sit" ? 20000 + Math.random() * 40000
                       : 8000 + Math.random() * 10000
    moodTimer.restart()
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

  function brainSend(message) {
    if (brainProc.running) {
      brainProc.write(JSON.stringify(message) + "\n")
      return true
    }
    return false
  }

  function stopAll() {
    moodTimer.stop()
    jumpAnim.stop()
    peekAnim.stop()
    afterArrive = ""
  }

  function handOff(kind) {
    const s = edgeScreen()
    const yr = s ? Math.max(0, Math.min(1, (gy - s.y) / s.height)) : 0.5
    send({ t: "enter", mode: kind, yr: yr })
    stopAll()
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
      mode = "walk"
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

  // ---- Brain messages ----
  function handleBrain(message) {
    if (message.t === "persona") {
      petName = message.name || ""
      idleLines = message.idleLines || []
      idleChatter = message.idleChatter !== false
      idleChatterMinSec = Math.max(20, message.idleChatterMinSec || 180)
      userScale = Number(message.scale) || 0
      if (userScale > 0) sizeScale = userScale
      if (message.character && message.character !== charDir) charDir = message.character
      if (message.home !== undefined) home = String(message.home)
      chatterTimer.restartRandom()
    } else if (message.t === "chat-start") {
      chatId = message.id
      chatBusy = true
      chatLog.append({ who: "pet", text: "" })
      bubbleText = ""
    } else if (message.t === "chat-token" && message.id === chatId) {
      const last = chatLog.count - 1
      if (last >= 0) chatLog.setProperty(last, "text", chatLog.get(last).text + message.text)
      say(bubbleText + message.text, 15000)
    } else if (message.t === "chat-end" && message.id === chatId) {
      chatBusy = false
      say(bubbleText, 8000)
    } else if (message.t === "chat-error") {
      chatBusy = false
      const last = chatLog.count - 1
      if (last >= 0 && chatLog.get(last).who === "pet" && chatLog.get(last).text === "") chatLog.remove(last)
      chatLog.append({ who: "pet", text: message.text })
      say(message.text, 6000)
    } else if (message.t === "agent") {
      agentEvent(message.state, message.detail || "")
    }
  }

  function trimLog() {
    while (chatLog.count > 8) chatLog.remove(0)
  }

  function sendChat(text) {
    text = text.trim()
    if (!text) return
    chatLog.append({ who: "me", text: text })
    trimLog()
    if (!brainSend({ t: "chat", text: text })) {
      chatLog.append({ who: "pet", text: "Uy, ahora no puedo hablar... 😴" })
      say("Uy, ahora no puedo hablar... 😴", 5000)
      return
    }
    chatBusy = true
    say("…", 60000)
  }

  function openChat() {
    if (!present) return
    const s = screenAt(gx + w / 2, gy + h / 2)
    chatScreen = s ? s.name : ""
    stopAll()
    lift = 0
    mode = "talk"
    chatOpen = true
    if (chatLog.count === 0 && petName) say("¡Hola! Soy " + petName + " ✨", 4000)
  }

  function closeChat() {
    if (!chatOpen) return
    chatOpen = false
    chatBusy = false
    if (mode === "talk") {
      mode = "idle"
      moodTimer.interval = 1500
      moodTimer.restart()
    }
  }

  function clicked() {
    // Like ThatPet: when an agent is waiting for you, a click takes you there.
    if (agentState === "needs" || agentState === "done") {
      brainSend({ t: "focus-agent" })
      agentState = "idle"
      agentDetail = ""
      bubbleText = ""
      pickNext()
      return
    }
    if (autoSleep) wakeUp()
    openChat()
  }

  // ---- Agent reactions ----
  function isTransient(state) { return state === "done" || state === "thanks" || state === "oops" }

  function agentEvent(state, detail) {
    agentSeenAt = Date.now()
    // A transient reaction finishes first; persistent ones queue behind it.
    if (reactHold.running && !isTransient(state)) {
      pendingAgent = state
      pendingDetail = detail
      return
    }
    agentState = state
    agentDetail = detail
    agentStale.restart()
    if (isTransient(state)) {
      pendingAgent = state === "oops" ? "working" : ""
      pendingDetail = ""
      reactHold.interval = state === "done" ? 4500 : state === "oops" ? 2500 : 2000
      reactHold.restart()
      if (state === "done") confettiAnim.restart()
    }
    if (autoSleep && state !== "idle") wakeUp()
    showReaction()
  }

  function reactionText() {
    switch (agentState) {
    case "thinking": return "Mmm… 🤔"
    case "working": return agentDetail || "Trabajando…"
    case "needs": return "¡Te necesito! " + (agentDetail ? "· " + agentDetail : "")
    case "done": return "¡Listo! 🎉"
    case "thanks": return "¡Gracias! 💜"
    case "oops": return "¡Ups! " + (agentDetail ? "· " + agentDetail : "")
    }
    return ""
  }

  function showReaction() {
    if (!present || chatOpen || busyHands || sleepLocked) return
    if (agentState === "idle") { if (mode === "react") pickNext(); return }
    stopAll()
    lift = 0
    mode = "react"
    say(reactionText(), agentState === "working" || agentState === "thinking" || agentState === "needs" ? 120000 : reactHold.interval)
  }

  Timer {
    id: reactHold
    onTriggered: {
      const next = root.pendingAgent
      root.agentState = next || "idle"
      root.agentDetail = root.pendingDetail
      root.pendingAgent = ""
      root.pendingDetail = ""
      if (root.agentState === "idle") { root.bubbleText = ""; if (root.mode === "react") root.pickNext() }
      else root.showReaction()
    }
  }

  // An agent that stopped sending events (crashed, closed) is forgotten.
  Timer {
    id: agentStale
    interval: 180000
    onTriggered: if (root.agentBusy && root.agentState !== "needs") {
      root.agentState = "idle"
      root.bubbleText = ""
      if (root.mode === "react") root.pickNext()
    }
  }

  // ---- Activities ----
  function pickNext() {
    if (!present) return
    if (chatOpen) { mode = "talk"; return }
    if (sleepLocked || autoSleep) {
      caught = false
      mode = "sleep"
      moodTimer.stop()
      return
    }
    if (agentState !== "idle") { showReaction(); return }
    if (homebody) { pickHome(); return }
    const odds = Object.assign({}, weights)
    if (!canChase) delete odds.chase
    if (linkUp()) odds.visit = 1
    let total = 0
    for (const k in odds) total += odds[k]
    let r = Math.random() * total
    let next = "walk"
    for (const k in odds) {
      r -= odds[k]
      if (r <= 0) { next = k; break }
    }
    caught = false
    afterArrive = ""
    if (next === "visit") {
      // Walk off the shared edge; the move timer hands her over there.
      const s = edgeScreen()
      visiting = true
      mode = "walk"
      targetX = peerSide === "left" ? s.x - w - 10 : s.x + s.width + 10
      targetY = s.y + topMargin + Math.random() * Math.max(1, s.height - h - margin - topMargin)
      moodTimer.interval = 30000
      moodTimer.restart()
      return
    }
    visiting = false
    if (next === "climb" || next === "peek") {
      // Walk to the side edge (climb) or down to the bottom (peek) first.
      const s = screenAt(gx + w / 2, gy + h / 2)
      if (!s) return
      afterArrive = next
      mode = "walk"
      if (next === "climb") {
        const left = gx + w / 2 < s.x + s.width / 2
        targetX = left ? s.x : s.x + s.width - w
      } else {
        targetX = Math.max(s.x + margin, Math.min(s.x + s.width - w - margin, gx))
      }
      targetY = s.y + s.height - h - margin
      moodTimer.interval = 30000
      moodTimer.restart()
      return
    }
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

  function arrived() {
    const next = afterArrive
    afterArrive = ""
    const s = screenAt(gx + w / 2, gy + h / 2)
    if (next === "climb" && s) {
      // Up the side of the screen, facing the wall, then let go and fall.
      facingRight = gx + w / 2 > s.x + s.width / 2
      mode = "climb"
      targetY = Math.max(s.y + topMargin, gy - 150 - Math.random() * 250)
      moodTimer.stop()
    } else if (next === "peek" && s) {
      mode = "peek"
      moodTimer.stop()
      peekAnim.from = gy
      peekAnim.to = s.y + s.height - h * 0.3
      peekAnim.restart()
    } else {
      pickNext()
    }
  }

  // ---- Grabbing and throwing (global pointer coordinates) ----
  property real lastGrabX: 0
  property real grabStartX: 0
  property real grabStartY: 0
  property real grabStartedAt: 0
  property bool pressing: false
  property real sampleX: 0
  property real sampleY: 0
  property real sampleAt: 0

  function press(px, py) {
    pressing = true
    grabStartX = px
    grabStartY = py
    grabStartedAt = Date.now()
  }

  // Only a real drag picks her up; a still click is handled on release.
  function pressMove(px, py) {
    if (!pressing) return
    if (mode !== "held") {
      if (Math.abs(px - grabStartX) < 6 && Math.abs(py - grabStartY) < 6) return
      grabStart(px, py)
    }
    grabMove(px, py)
  }

  function grabStart(px, py) {
    if (chatOpen) closeChat()
    stopAll()
    lift = 0
    autoSleep = false
    mode = "held"
    lastGrabX = px
    sampleX = px
    sampleY = py
    sampleAt = Date.now()
    vx = 0
    vy = 0
  }

  function grabMove(px, py) {
    swing = Math.max(-40, Math.min(40, (lastGrabX - px) * 3))
    lastGrabX = px
    const now = Date.now()
    const dt = (now - sampleAt) / 1000
    if (dt > 0.01) {
      // Smoothed pointer velocity, used for the throw.
      vx = 0.5 * vx + 0.5 * (px - sampleX) / dt
      vy = 0.5 * vy + 0.5 * (py - sampleY) / dt
      sampleX = px
      sampleY = py
      sampleAt = now
    }
    gx = px - w / 2
    // Hands sit at the top of the hang frame.
    const hang = anims[animFor("hang")]
    gy = py - (h - (hang ? hang.frameHeight * sizeScale : h)) + 4
    swingReset.restart()
  }

  function release(px, py) {
    pressing = false
    if (mode === "held") {
      if (Date.now() - sampleAt > 120) { vx = 0; vy = 0 } // stopped before letting go
      const fast = Math.sqrt(vx * vx + vy * vy) > 500
      if (fast) throwHer()
      else drop()
      return
    }
    clicked()
  }

  // Right click with a link to cross: carry her across the shared edge.
  function rightClick() {
    if (linkOn) { stopAll(); mode = "carried"; return }
    clicked()
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
    // A gentle drop: down a little from where she was let go (the desktop is
    // a floor plan, not a side view), unless she was hanging off an edge.
    const s = screenAt(gx + w / 2, gy + h / 2)
    const floor = s ? s.y + s.height - h - margin : gy
    floorY = Math.min(floor, gy + 60)
    vx = 0
    // Let go below the floor (she is tall): hop back up onto it.
    vy = gy > floorY ? -Math.sqrt(2 * gravity * (gy - floorY + 30)) : 0
  }

  function throwHer() {
    swing = 0
    mode = "fall"
    vx = Math.max(-2500, Math.min(2500, vx))
    vy = Math.max(-2500, Math.min(2500, vy))
    // Thrown: she flies and lands on the bottom of the screen.
    const s = screenAt(gx + w / 2, gy + h / 2)
    floorY = s ? s.y + s.height - h - margin : gy
  }

  // Let go of an edge: fall all the way down to the bottom of the screen.
  function fallToFloor() {
    swing = 0
    vx = 0
    vy = 0
    mode = "fall"
    const s = screenAt(gx + w / 2, gy + h / 2)
    floorY = s ? s.y + s.height - h - margin : gy
  }

  function desktopBounds() {
    const screens = Quickshell.screens
    let b = { left: 0, right: 0, top: 0 }
    for (let i = 0; i < screens.length; i++) {
      const s = screens[i]
      if (i === 0 || s.x < b.left) b.left = s.x
      if (i === 0 || s.x + s.width > b.right) b.right = s.x + s.width
      if (i === 0 || s.y < b.top) b.top = s.y
    }
    return b
  }

  function landed() {
    vx = 0
    vy = 0
    mode = "idle"
    moodTimer.interval = 1500
    moodTimer.restart()
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
    if (!present || busyHands) return // landing picks next
    if (locked) {
      if (chatOpen) closeChat()
      stopAll()
      lift = 0
      pickNext()
    } else if (mode === "sleep") {
      pickNext()
    }
  }

  function wakeUp() {
    if (!autoSleep) return
    autoSleep = false
    if (mode === "sleep" && !sleepLocked) pickNext()
  }

  Timer {
    id: swingReset
    interval: 80
    onTriggered: root.swing = 0
  }

  // Fall / throw physics and climbing, ~30 fps only while airborne.
  Timer {
    interval: 33
    repeat: true
    running: root.airborne && root.present
    onTriggered: {
      const dt = interval / 1000
      if (root.mode === "climb") {
        root.gy -= root.climbSpeed * dt
        if (root.gy <= root.targetY) root.fallToFloor()
        return
      }
      root.vy += root.gravity * dt
      root.gy += root.vy * dt
      root.gx += root.vx * dt
      // Bounce off the outer sides of the desktop and its top.
      const b = root.desktopBounds()
      if (root.gx < b.left - root.w / 2) { root.gx = b.left - root.w / 2; root.vx = -root.vx * 0.5 }
      if (root.gx > b.right - root.w / 2) { root.gx = b.right - root.w / 2; root.vx = -root.vx * 0.5 }
      if (root.vy < 0 && root.gy < b.top) { root.gy = b.top; root.vy = 0 }
      if (root.vy >= 0 && root.gy >= root.floorY) {
        root.gy = root.floorY
        root.landed()
      }
    }
  }

  // ---- Behaviour clock ----
  // Wait until screens and the character are known and the twin had a
  // chance to say she is over there, then start on the first screen.
  Timer {
    interval: root.linkOn ? 2500 : 1500
    running: root.animsReady
    onTriggered: {
      if (root.started) return
      root.started = true
      if (root.peerHasHer) { root.mode = "away"; return }
      const s = Quickshell.screens[0]
      if (s) {
        root.gx = s.x + s.width / 2
        root.gy = s.y + s.height - root.h - root.margin
        const p = root.homebody ? root.homePoint() : null
        if (p) { root.gx = p.x; root.gy = p.y }
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

  Process {
    id: brainProc
    command: ["python3", String(Qt.resolvedUrl("bin/chibi-brain")).replace("file://", "")]
    running: true
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) {
        let message = null
        try { message = JSON.parse(line) } catch (e) { return }
        root.handleBrain(message)
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

  Timer {
    id: bubbleTimer
    onTriggered: root.bubbleText = ""
  }

  // Random idle lines, rate-limited (personality.json: idleChatter, idleChatterMinSec).
  Timer {
    id: chatterTimer
    function restartRandom() {
      interval = root.idleChatterMinSec * 1000 * (1 + Math.random())
      restart()
    }
    running: false
    onTriggered: {
      const calm = root.mode === "idle" || root.mode === "sit" || root.mode === "walk" || root.mode === "dance"
      if (root.idleChatter && root.present && calm && !root.chatOpen && root.bubbleText === "" && root.idleLines.length)
        root.say(root.idleLines[Math.floor(Math.random() * root.idleLines.length)], 5000)
      restartRandom()
    }
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
        if (root.visiting) root.handOff("walk")
        else if (root.mode !== "chase") root.arrived()
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

  // Peek: sink below the bottom edge until only her head shows, wait, come back.
  SequentialAnimation {
    id: peekAnim
    property real from: 0
    property real to: 0
    NumberAnimation { target: root; property: "gy"; to: peekAnim.to; duration: 900; easing.type: Easing.InOutQuad }
    PauseAnimation { duration: 4000 + Math.random() * 3000 }
    NumberAnimation { target: root; property: "gy"; to: peekAnim.from; duration: 700; easing.type: Easing.InOutQuad }
    ScriptAction { script: if (root.mode === "peek") root.pickNext() }
  }

  // Slow breathing while asleep, in small steps (5 updates a second, not 60).
  Timer {
    interval: 200
    repeat: true
    running: root.mode === "sleep" && root.present
    onTriggered: root.breath = (root.breath + Math.PI * 2 / 15) % (Math.PI * 2)
  }

  // Procedural motion: one 50 ms tick while a strip asks for it, idle otherwise.
  Timer {
    interval: 50
    repeat: true
    running: root.motion !== "" && root.present && !root.busyHands
    onTriggered: root.motionT = (root.motionT + 0.05) % 1000
  }

  // Confetti when an agent finishes.
  property real confettiT: 1
  NumberAnimation {
    id: confettiAnim
    target: root
    property: "confettiT"
    from: 0
    to: 1
    duration: 2600
  }

  Process {
    command: ["sh", "-c", "command -v hyprctl"]
    running: true
    onExited: function(exitCode) {
      root.canChase = exitCode === 0
      if (!root.canChase) console.info("chibi: hyprctl not found, cursor chasing and idle naps disabled")
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

  // ---- Nap when the user is away: the cursor has not moved for a while ----
  property string lastCursor: ""
  property real cursorStillSince: Date.now()
  Process {
    id: idleProc
    command: ["hyprctl", "cursorpos"]
    stdout: SplitParser {
      onRead: function(line) {
        const now = Date.now()
        if (line !== root.lastCursor) {
          root.lastCursor = line
          root.cursorStillSince = now
          root.wakeUp()
        } else if (!root.autoSleep && now - root.cursorStillSince > root.sleepAfterIdleSec * 1000
                   && root.present && !root.chatOpen && !root.busyHands && !root.agentBusy) {
          root.autoSleep = true
          root.stopAll()
          root.lift = 0
          root.mode = "sleep"
        }
      }
    }
  }

  Timer {
    interval: 15000
    repeat: true
    running: root.canChase && root.present
    onTriggered: if (!idleProc.running) idleProc.running = true
  }

  // ---- One overlay per screen ----
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData
      readonly property bool hasChat: root.chatOpen && root.chatScreen === modelData.name

      screen: modelData
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      WlrLayershell.namespace: "danso-chibi"
      WlrLayershell.layer: WlrLayer.Overlay
      // The chat field needs the keyboard; otherwise never take it.
      WlrLayershell.keyboardFocus: hasChat ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      // Only her own box takes pointer input; everything else clicks through.
      // While carried, or while the chat is open, the whole overlay takes it:
      // to follow the pointer, or to close the chat on a click outside it.
      mask: Region { item: root.mode === "carried" || panel.hasChat ? stage : girl }

      Item {
        id: stage
        anchors.fill: parent

        MouseArea {
          anchors.fill: parent
          enabled: root.mode === "carried" || panel.hasChat
          hoverEnabled: root.mode === "carried"
          cursorShape: root.mode === "carried" ? Qt.ClosedHandCursor : Qt.ArrowCursor
          onPositionChanged: function(mouse) {
            root.carryMove(mouse.x + panel.modelData.x, mouse.y + panel.modelData.y)
          }
          onClicked: {
            if (root.mode === "carried") root.drop()
            else root.closeChat()
          }
        }

        // Confetti burst around her when an agent finishes.
        Item {
          id: confetti
          visible: root.confettiT < 1 && girl.onThisScreen && root.present
          x: girl.x + root.w / 2
          y: girl.y
          Repeater {
            model: confetti.visible ? 36 : 0
            Rectangle {
              required property int index
              readonly property real seed: Math.sin(index * 12.9898) * 43758.5453 % 1
              readonly property real ang: index / 36 * Math.PI * 2
              readonly property real spd: 120 + Math.abs(seed) * 180
              width: 7; height: 11; radius: 2
              color: ["#7aa2f7", "#bb9af7", "#9ece6a", "#e0af68", "#f7768e", "#7dcfff"][index % 6]
              x: Math.cos(ang) * spd * root.confettiT * 1.6
              y: -Math.abs(Math.sin(ang)) * spd * root.confettiT * 1.4 + 520 * root.confettiT * root.confettiT
              rotation: root.confettiT * 720 * (index % 2 ? 1 : -1)
              opacity: 1 - root.confettiT
            }
          }
        }

        Item {
          id: girl
          // Whole logical pixels: fractional positions blur the line art.
          x: Math.round(root.gx - panel.modelData.x)
          y: Math.round(root.gy - panel.modelData.y)
          width: root.w
          height: root.h
          readonly property bool onThisScreen: x + width > -200 && x < stage.width + 200
                                            && y + height > -200 && y < stage.height + 200

          MouseArea {
            anchors.fill: parent
            enabled: root.present && root.mode !== "carried"
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: root.mode === "held" ? Qt.ClosedHandCursor : Qt.PointingHandCursor
            // The pointer stays grabbed by this surface while pressed, even
            // past its edges, so dragging carries her onto other screens.
            function globalPos(mouse) {
              const p = mapToItem(stage, mouse.x, mouse.y)
              return { x: p.x + panel.modelData.x, y: p.y + panel.modelData.y }
            }
            onPressed: function(mouse) {
              if (mouse.button === Qt.RightButton) return
              const g = globalPos(mouse)
              root.press(g.x, g.y)
            }
            onPositionChanged: function(mouse) { if (pressed && root.pressing) { const g = globalPos(mouse); root.pressMove(g.x, g.y) } }
            onReleased: function(mouse) {
              if (mouse.button === Qt.RightButton) { root.rightClick(); return }
              const g = globalPos(mouse)
              root.release(g.x, g.y)
            }
          }

          AnimatedSprite {
            id: sprite
            visible: girl.onThisScreen && root.present && root.animsReady
            readonly property var a: root.anims[root.anim] || { frameWidth: 1, frameHeight: 1, frameCount: 1, frameMs: 1000, sideways: false }
            source: root.animsReady ? root.charUrl(root.anim + ".png") : ""
            frameWidth: a.frameWidth
            frameHeight: a.frameHeight
            frameCount: a.frameCount
            frameDuration: a.frameMs
            loops: root.anim === "jump" ? 1 : AnimatedSprite.Infinite
            // Single-frame strips (sleep) need no clock at all.
            running: visible && a.frameCount > 1
            interpolate: false
            smooth: true
            width: a.frameWidth * root.sizeScale
            height: a.frameHeight * root.sizeScale
            x: Math.round((root.w - width) / 2)
            // bounce: small hops; breathe: a slow bob of a pixel or two.
            readonly property real hop: root.motion === "bounce" ? 10 * Math.abs(Math.sin(root.motionT * Math.PI * 2.2))
                                      : root.motion === "breathe" ? 1.5 * (1 + Math.sin(root.motionT * 2.4)) : 0
            y: Math.round(root.h - height - root.lift - hop * root.sizeScale)
            onSourceChanged: restart()
            transform: [
              Scale {
                origin.x: sprite.width / 2
                origin.y: sprite.height
                xScale: sprite.a.sideways && !root.facingRight ? -1 : 1
                yScale: root.mode === "sleep" ? 1 + 0.015 * Math.sin(root.breath)
                      : root.motion === "breathe" ? 1 + 0.008 * Math.sin(root.motionT * 2.4) : 1
              },
              // sway: rocks from her feet (waving).
              Rotation {
                origin.x: sprite.width / 2; origin.y: sprite.height
                angle: root.motion === "sway" ? 3 * Math.sin(root.motionT * 6) : 0
              },
              // Swings from her hands while held.
              Rotation { origin.x: sprite.width / 2; origin.y: 0; angle: root.swing }
            ]
          }
        }

        // ---- Speech bubble over her head ----
        Rectangle {
          id: bubble
          visible: root.bubbleText !== "" && girl.onThisScreen && root.present && !root.busyHands
          readonly property real headY: girl.y + root.h - sprite.height - root.lift
          width: Math.min(280, bubbleLabel.implicitWidth + 24)
          height: bubbleLabel.implicitHeight + 16
          x: Math.max(8, Math.min(stage.width - width - 8, girl.x + root.w / 2 - width / 2))
          // Above her head, or beside her when there is no room above.
          y: headY - height - 10 > 8 ? headY - height - 10 : Math.min(stage.height - height - 8, headY + 10)
          radius: 12
          color: "#1a1b26"
          border.color: root.agentState === "needs" ? "#e0af68" : root.agentState === "oops" ? "#f7768e" : "#7aa2f7"
          border.width: 2
          opacity: 0.95
          Text {
            id: bubbleLabel
            anchors.centerIn: parent
            width: Math.min(256, implicitWidth)
            text: root.bubbleText
            color: "#c0caf5"
            font.pixelSize: 14
            wrapMode: Text.Wrap
          }
        }

        // ---- Chat panel beside her ----
        Rectangle {
          id: chatPanel
          visible: panel.hasChat
          width: 320
          height: 260
          readonly property bool roomRight: girl.x + root.w + width + 16 < stage.width
          x: roomRight ? girl.x + root.w + 8 : Math.max(8, girl.x - width - 8)
          y: Math.max(8, Math.min(stage.height - height - 8, girl.y + root.h * 0.25))
          radius: 12
          color: "#1a1b26"
          border.color: "#7aa2f7"
          border.width: 2
          // Swallow clicks so they don't close the chat.
          MouseArea { anchors.fill: parent }

          Text {
            id: chatTitle
            x: 12; y: 8
            text: (root.petName || "Chat") + (root.chatBusy ? " · escribiendo…" : "")
            color: "#bb9af7"
            font.bold: true
            font.pixelSize: 13
          }

          ListView {
            id: chatList
            x: 10; y: 30
            width: parent.width - 20
            height: parent.height - 80
            clip: true
            spacing: 6
            model: chatLog
            onCountChanged: positionViewAtEnd()
            delegate: Item {
              required property string who
              required property string text
              width: chatList.width
              height: msg.implicitHeight + 10
              Rectangle {
                anchors.fill: msg
                anchors.margins: -5
                radius: 8
                color: who === "me" ? "#2f3549" : "#24283b"
              }
              Text {
                id: msg
                x: who === "me" ? chatList.width - width - 5 : 5
                y: 5
                width: Math.min(chatList.width - 40, implicitWidth)
                text: parent.text === "" ? "…" : parent.text
                wrapMode: Text.Wrap
                color: who === "me" ? "#7dcfff" : "#c0caf5"
                font.pixelSize: 13
              }
            }
          }

          TextField {
            id: chatInput
            x: 10
            y: parent.height - height - 10
            width: parent.width - 20
            placeholderText: "Escríbele algo… (Esc para cerrar)"
            color: "#c0caf5"
            placeholderTextColor: "#565f89"
            font.pixelSize: 13
            background: Rectangle { radius: 8; color: "#24283b"; border.color: chatInput.activeFocus ? "#bb9af7" : "#414868" }
            focus: panel.hasChat
            onVisibleChanged: if (visible) forceActiveFocus()
            onAccepted: { root.sendChat(text); text = "" }
            Keys.onEscapePressed: root.closeChat()
          }
        }
      }
    }
  }
}
