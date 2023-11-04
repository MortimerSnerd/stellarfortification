import std
import nonstd
import color
import gl
import vec
import vfont

// Notes
// Coordinates are "playfield" coordinates, unless
// otherwise specified.  The entire playfield is
// mapped to (0,0) - (X,1), where X depends on the
// aspect ratio.
//
// TODO one downside of this as a coordinate system
// is that changing the window size changes the positions
// of moving objects (player, bullets) relative to
// objects whose position is fixed based on the playfield
// dimensions (the always centered fort). Looks like the
// only way to detect a window size change is to keep
// with the last size and check it per-frame.

def mils(f): return float(f) * 0.001
def percent(x): return float(x)*0.01

let SegsPerRing= 12
let SegArc = 360.0 / SegsPerRing
let RingMargin = 40.mils          // Distances between rings.
let OuterRingRadius = RingMargin * 3.0
let WrapMargin = 18.mils          // How far past the window edge before we wrap to other side of screen.
let TurnSpeed = 230.0             // deg/s
let PlayerAccel = 1.0
let PlayerRadius = 15.mils
let ThrusterLen = 10.mils
let FireCooldown = 1.0/7.0
let SegMaxHp = 2
let PlasmaSpeed = 0.5
let MaxPlasmaCooldown = 1.0
let DPlasmaCooldown = 0.10
let PlasmaRadius = 1.0/40.0
let CannonRadius = RingMargin / 2.0 // Used for collision detection.
let DeathPeriod = 5               // Number of seconds before a cannon respawns.
let SegPoints = 5                 // number of points for destroying a segment.
let BaseSparkSpeed = 0.15
let DSparkSpeed = 0.025           // How much faster do sparks get each level?
let MinSparkAwareness = 1.0/5.0   // How close spark needs to be to player to notice them.
let DSparkAwareness = 0.05        // How much awareness range increases per level.
let SparkNoticeChance = 10.percent
let MaxSparkReactionTime = 0.3
let SparkTurnSpeed = 0.7          // How fast can we lerp a direction
let BaseRingSpeed = 45.0
let DRingSpeed = 10.0             // Degrees per second per level
let CannonRotSpeed = 1
let DCannonRotSpeed = 0.1         // Change in cannon rot speed per level.
let GameOverLen = 10.0
let PlayerDeathLength = 4.0
let Volume = 32

// Line path used to draw cannon. Centered on 0,0
let CannonLines: [float2] = map([float2_0, float2{3.0,0.0}, float2{3.0,-1.0}, float2{1.0,-1.0}, float2{-3.0,-4.0},
  float2{ -2.0,-1.0}, float2{ -2.0,1.0}, float2{-3.0,4.0}, float2{1.0,1.0}, float2{3.0,1.0}, float2{3.0,0.0}]): _ * 5.mils

class Seg:
  hp = SegMaxHp

class Ring:
  segs: [Seg] // In order from inner ring to outer.
  rot: float
  radius: float
  targetRadius: float
  color: color

enum SparkState:
  SeekingPlayer
  SeekingRing
  Riding

class Spark:
  pos: float2
  velocity: float2 // Velocity per second.
  state: SparkState = SeekingRing
  hitch: Ring?                     // ring we are hitched to when state == Riding
  seg: int                         // ring # when state == Riding
  playerCheckInterval: float = 0.0 // Reaction time of sparks noticing player.
  soundInterval = 0.0

class Bullet:
  pos: float2
  velocity: float2 // Velocity per second.

enum FortState:
  Seeking
  Dying

class Fort:
  rings: [Ring]
  cannonRot: float2       // sincos of cannon rotation.
  cannonCooldown: float // Can't fire until <= 0.
  plasmaBalls: [Bullet]
  state: FortState
  timeToRespawn: float
  sparks: [Spark]
  numDeaths = 0         // Used to scale speeds etc for harder levels.

class Player: 
  pos: float2
  velocity: float2 // Velocity per second.
  vDecay: float
  rot: float
  dRot: float
  rotDecay: float
  thrusting = true
  fireCooldown = 0.0
  bullets: [Bullet]
  score = 0
  lives = 3
  dead = false
  deadCooldown = 0.0

enum MainState:
  StartScreen
  Playing
  GameOver
  Paused

//
// Parameters that scale with the number of times
// the fort has been destroyed.
//
 
def lvlPlasmaCooldown(f: Fort):
  return max(0.1, MaxPlasmaCooldown - f.numDeaths*DPlasmaCooldown)

def lvlCannonRotSpeed(f: Fort):
  return CannonRotSpeed + f.numDeaths*DCannonRotSpeed

def lvlRingSpeed(f: Fort, ringIdx:int):
  let fac = if ringIdx == 1: -1 else: 1

  return fac*(BaseRingSpeed + (2-ringIdx)*15.0 + DRingSpeed*f.numDeaths)

def lvlSparkSpeed(f: Fort):
  return BaseSparkSpeed + f.numDeaths*DSparkSpeed

// Returns spark awareness range, scaled for
// level.
def lvlSparkAwarenessDist(f: Fort):
  return MinSparkAwareness + f.numDeaths*DSparkAwareness


// Compat function that resembles old play_sound
def play_sound(fx: string, volume: int = 128):
   let chan = play_sfxr(fx)

   if chan >= 0:
      sound_volume(chan, float(volume) / 128.0)

// Game loop.
def go():
  fatal(gl.window("Stellar Fort", 640, 480))
  preloadSounds()

  let BCD = 3.6
  var bgnoiseCooldown = 0.0

  let player = Player {pos: float2 {0.7, 0.7}, velocity: float2_0, vDecay: 0.98, rot: 0.0, rotDecay: 0.75, dRot: 0.0,
    bullets: []}
  let fort = mkFort()
  let starfield = mkStarfield()
  var state = StartScreen
  var goCooldown = 0.0

  while gl.frame() and gl.button("escape") != 1:
    let wdims = float(gl.window_size())
    let coordScale = float2_1 * wdims.y
    let playfieldDims = float2 {wdims.x/wdims.y, 1.0}
    let pixelLineWidth = 1.0/wdims.y

    let dT = gl.delta_time()

    switch state:
      case StartScreen:
        gl.scale(coordScale):
          renderStartScreen(starfield, playfieldDims, wdims.y, pixelLineWidth)
        if gl.button("space") == 1:
          state = Playing
          fort.state = Dying
          respawnFort(fort, playfieldDims)
          respawnPlayer(player, fort, playfieldDims)

          // Reset the per-game state, this could be organized
          // better.
          player.score = 0
          fort.numDeaths = 0
          fort.plasmaBalls = []

      case GameOver:
        gl.scale(coordScale):
          renderGameOverScreen(player, playfieldDims, pixelLineWidth, wdims.y)
        goCooldown -= dT
        if goCooldown < 0.0:
          state = StartScreen

      case Playing, Paused:
        bgnoiseCooldown -= dT
        if bgnoiseCooldown <= 0.0 and fort.state != Dying:
          play_sound("data/sfx/bgnoise.sfxr", Volume)
          bgnoiseCooldown = BCD

        if state == Paused:
          if gl.button("p") == 1:
            state = Playing
        else:
          if gl.button("p") == 1:
            state = Paused

          if player.dead:
            player.deadCooldown -= dT
            if player.deadCooldown <= 0.0:
              if player.lives <= 0.0:
                state = GameOver
                goCooldown = GameOverLen
                player.lives = 3
              else:
                respawnPlayer(player, fort, playfieldDims)


          updateFort(fort, player, playfieldDims, dT)
          if not player.dead:
            processInput(player, dT)

          updatePlayer(player, fort, playfieldDims, dT)

        gl.clear(color_black)
        gl.scale(coordScale):
          gl.color(color_blue)
          renderStarfield(starfield, pixelLineWidth)
          renderPlayer(player, fort, pixelLineWidth, wdims.y, playfieldDims)
          renderFort(fort, playfieldDims, pixelLineWidth)
          if state == Paused:
            renderCenteredText("Paused", 4.0/wdims.y, pixelLineWidth, playfieldDims*0.5)

def renderStartScreen(starfield, pfDims, winHeight, pixelLineWidth):
  let c = pfDims*0.5
  gl.clear(color_black)
  renderStarfield(starfield, pixelLineWidth)

  gl.color(color_white)
  renderCenteredText("Stellar Fortification", 4.0/winHeight, pixelLineWidth, c)
  renderCenteredText("Press Space to Start", 3.0/winHeight, pixelLineWidth, c + float2_y * 140.mils)

def renderGameOverScreen(player, pfDims, pixelLineWidth, winHeight):
  let c = pfDims*0.5
  gl.clear(color_black)
  gl.color(color_blue)
  renderCenteredText("Game Over", 4.0/winHeight, pixelLineWidth, c)
  renderCenteredText("Score: " + player.score, 3.0/winHeight, pixelLineWidth, c + float2_y * 140.mils)



//
// Player functions
//

// Returns a new bullet to be added to the bullets
// array.
def fireBullet(pl: Player):
  return Bullet{pos: pl.pos, velocity: sincos(pl.rot) + pl.velocity}

def renderBullets(pl: Player, pixelLineWidth):
  for(pl.bullets) b:
    let p1 = b.pos + normalize(b.velocity) * 6.mils
    gl.line(b.pos, p1, 2.0 * pixelLineWidth)

// Updates the bullets, and removes any that have
// hit something, or gone off the playfield
def updateBullets(bs: [Bullet], f: Fort, dT: float, pfDims: float2, applyDamage:bool) -> [Bullet], int:
  var segsKilled = 0
  let newbs = filter(bs) b:
    let oldpos = b.pos
    updateMovable(b, dT)
    let sg = hitRingSegment(f, oldpos, b.pos, pfDims)
    if applyDamage and sg:
      sg.hp--
      segsKilled++

    inPlayfield(b.pos, pfDims) and not sg

  return newbs, segsKilled

// Player is dead.  Subtract a life, and
// setup to animate the death.
def killPlayer(p: Player):
  if not p.dead:
    p.lives--
    p.dead = true
    p.deadCooldown = PlayerDeathLength
    p.thrusting = false // no longer
    p.velocity = float2_0
    play_sound("data/sfx/playerboom.sfxr")

def respawnPlayer(player, fort, pfDims):
  player.dead = false
  player.pos = float2_1 * pfDims*0.75
  player.bullets = []
  sendSparksToRings(fort, pfDims)

def renderPlayer(p: Player, fort: Fort, lineWidth, winHeight, pfDims):
  renderBullets(p, lineWidth)

  gl.translate(p.pos):
    let sc = sincos(p.rot)
    gl.rotate_z(sc):
      gl.line_mode(true):
        let d = PlayerRadius
        let rear1 = float2 {-d, -d}
        let rear2 = float2 {-d, d}

        if p.thrusting:
          // Draw the thruster exhaust.
          let mid = lerp(rear1, rear2, 0.5)
          gl.color(color_red)
          for(4): 
            gl.line(jitterY(mid, 0.005), jitterY(mid + float2_x * -ThrusterLen, 0.7*ThrusterLen), 
                    lineWidth)

        var scale = 1.0
        if p.dead:
          let t = max(0.0, (max(0.0, p.deadCooldown) - 3.0)/3.0)
          scale = lerp(0.001, 1.0, t)

        gl.color(color_white)
        gl.scale(scale):
          gl.polygon([rear1, 
                      rear2, 
                      float2 {d*1.5, 0.0}])
          if p.dead:
            renderSparkleBall(float2_0, 3, PlayerRadius, PlayerRadius/8.0, lineWidth)

  if fort.state == Dying:
    let msg = "score: " + p.score + "   lives: " + p.lives + "    level: " + (1+fort.numDeaths)
    gl.color(color_blue)
    renderCenteredText(msg, 2.0/winHeight, lineWidth, float2{pfDims.x*0.5, 20.mils})

  if p.dead:
    gl.color(color_blue)
    renderCenteredText("Lives left: " + p.lives, 2.0/winHeight, lineWidth, pfDims*0.5 + float2_y*0.3)
    renderCenteredText("score: " + p.score + "    level: " + (fort.numDeaths+1), 2.0/winHeight, lineWidth, pfDims*0.5 + float2_y*0.4)

def processInput(p:: Player, dT: float):
  if gl.button("a") > 0:
    dRot = -TurnSpeed

  if gl.button("d") > 0:
    dRot = TurnSpeed

  if gl.button("w") > 0:
    velocity += sincos(rot) * PlayerAccel * dT
    thrusting = true
  else:
    thrusting = false

  fireCooldown -= dT
  if fireCooldown <= 0.0 and gl.button("space") > 0.0:
    p.bullets.push(fireBullet(p))
    fireCooldown = FireCooldown
    play_sound("data/sfx/pshot.sfxr", Volume)

def updatePlayer(t:: Player, fort: Fort, pfDims: float2, dT: float):
  let vToPlayer = pos - pfDims * 0.5
  let minPush = 1

  if not dead:
    if magnitude(vToPlayer) < (OuterRingRadius + PlayerRadius):
      // We do not want to worry about rings pushing
      // the ship around, so do not go in there.
      let n = normalize(vToPlayer)
      let nvel = normalize(velocity)

      // Don't interfere with the ship if it is heading away
      // from the fort.
      if dot(n, nvel) <= 0.0:
        if almost(magnitude(velocity), 0.0, 0.015):
          // Do not allow a lack of velocity from pushing
          // us out of there.
          velocity = n * -minPush * 0.10

        let reflect = velocity - n*2.0*dot(velocity, n)
        velocity = reflect * max(magnitude(velocity), minPush) * 0.8

    updateMovable(t, dT)
    velocity *= vDecay

    rot += dRot * dT
    dRot *= rotDecay

    // Leaving edge of screen wraps around.
    if pos.x < -WrapMargin:
      pos += float2 {pfDims.x + WrapMargin*2.0, 0.0}
    else:
      if pos.x > (pfDims.x+WrapMargin):
        pos -= float2{pfDims.x + WrapMargin*2.0, 0.0}

    if pos.y < -WrapMargin:
      pos += float2 {0.0, pfDims.y + WrapMargin*2.0}
    else:
      if pos.y > (WrapMargin+1.0):
        pos -= float2{0.0, pfDims.y + WrapMargin*2.0}

  var numSegsBroke = 0
  bullets, numSegsBroke = updateBullets(bullets, fort, dT, pfDims, true)
  if fort.state != Dying:
    score += numSegsBroke * SegPoints

  if numSegsBroke > 0:
    play_sound("data/sfx/ringhit.sfxr", Volume)

  // Did we hit the cannon?
  if fort.state != Dying:
    let center = pfDims * 0.5
    for(bullets) b:
      let dist = magnitude(b.pos - center)
      if dist < CannonRadius:
        killFort(fort)
        score += 300
        return

//
// Fort functions
//

// Sets up the fort state for the death animation, and
// score screen.
def killFort(f:: Fort):
  if state != Dying:
    play_sound("data/sfx/fortboom.sfxr")
    state = Dying
    timeToRespawn = DeathPeriod
    for(rings) r:
      r.targetRadius = 1.mils // Collapsing rings.

// Called to move
def respawnFort(f:: Fort, pfDims):
  if state != Seeking:
    numDeaths++
    state = Seeking
    play_sound("data/sfx/fortspawn.sfxr", Volume)
    respaceRings(rings)
    for(rings) r:
      for(r.segs) sg:
        sg.hp = SegMaxHp

    sendSparksToRings(f, pfDims)

def sendSparksToRings(f: Fort, pfDims):
  for(f.sparks) s:
    s.state = SeekingRing
    s.pos = pfDims*0.5

// Tests for a hit against a ring segment.
// If there is a hit, returns the segment, nil otherwise.
def hitRingSegment(f: Fort, p0, p1: float2, pfDims: float2) -> Seg?:
  for(f.rings) r:
    liveSegments(r, pfDims) x0, x1, sg:
      let hit = line_intersect(p0, p1, x0, x1)
      if hit:
        return sg

  return nil

def mkFort():
  let rv = Fort {rings: [],
     cannonRot: float2_x,  cannonCooldown: MaxPlasmaCooldown,
     plasmaBalls: [], state: Dying, timeToRespawn: 0.0,
     sparks: initialSparks()}

  initRings(rv, rv.rings)
  return rv

def initialSparks():
  let rv = []
  for(3):
    rv.push(Spark{pos: float2_1*0.5, velocity: float2_x, state: SeekingRing, hitch: nil, seg: 0})

  return rv

def updateFort(f:: Fort, player: Player, pfDims: float2, dT: float):
  let center = pfDims*0.5
  let vToPlayer = normalize(player.pos - center)

  if almost(-1.0, dot(vToPlayer, normalize(cannonRot)), 0.01):
    // The player is directly behind us. If we don't nudge
    // here, the turning will be painfully slow, since we're
    // essentially trying to lerp towards the center of the
    // cannon.  (maybe this vector lerping sucks more than
    // originally anticipated).
    cannonRot = normalize(lerp(cannonRot, float2{cannonRot.y, cannonRot.x}, lvlCannonRotSpeed(f)*dT))
  else:
    let na = lerp(cannonRot, vToPlayer, lvlCannonRotSpeed(f)*dT)

    if not almost(0.0, magnitude(na), 0.001):
      cannonRot = normalize(na)

  var numSegsBroke = 0
  plasmaBalls, numSegsBroke = updateBullets(plasmaBalls, f, dT, pfDims, false)

  for(plasmaBalls) pb:
    if magnitude(player.pos - pb.pos) < (PlayerRadius+PlasmaRadius):
      killPlayer(player)

  cannonCooldown -= dT
  switch state:
    case Seeking:
      if not player.dead and canFire() and not hitRingSegment(f, center, cannonRot*2.0, pfDims):
        cannonCooldown = lvlPlasmaCooldown(f)
        plasmaBalls.push(Bullet{pos: center, velocity: cannonRot*PlasmaSpeed})
        play_sound("data/sfx/plasma.sfxr", max(128, 2*Volume))

      // Clean out any dead rings and regrow them.
      let live, dead = partition(rings) r:
        exists(r.segs) s:
          s.hp > 0

      if length(dead) > 0:
        // Dead rings regenerate from the inside.
        for(dead) r:
          r.radius = 0.0
          for(r.segs) s:
            s.hp = SegMaxHp

        rings = append(dead, live)
        respaceRings(rings)
        play_sound("data/sfx/ringgrow.sfxr")

    case Dying:
      timeToRespawn -= dT
      if timeToRespawn <= 0.0:
        respawnFort(pfDims)

  for(rings) r, ridx:
    let dRad = r.targetRadius - r.radius
    if not almost(dRad, 0.0, 0.001):
      r.radius += dT*dRad*2.0 
    r.rot += lvlRingSpeed(f, ridx) * dT 

  if f.state != Dying:
    updateSparks(f, player, dT, pfDims)

def renderSparks(f: Fort, pfDims, pixelLineWidth):
  gl.color(color_blue)
  for(f.sparks) s:
    let r1 = pfDims.y/100.0
    let r2 = pfDims.y/200.0

    if s.state == Riding:
      renderSparkleBall(s.pos, 3, r1, r2, pixelLineWidth)
    else:
      renderSparkleBall(s.pos, 3, r1*0.5, r2*0.5, pixelLineWidth)
      renderSparkleBall(s.pos+s.velocity*r1*0.8, 3, r1*0.5, r2*0.5, pixelLineWidth)

def updateSparks(f: Fort, player: Player, dT, pfDims):
  for(f.sparks) s:
    let vToPlayer = player.pos - s.pos
    let pdist = magnitude(vToPlayer)
    let center = pfDims*00.5

    if pdist < PlayerRadius:
      killPlayer(player)
    else:
      switch s.state:
        case SeekingPlayer:
          if pdist > lvlSparkAwarenessDist(f):
            s.state = SeekingRing
          else:
            s.velocity = lerp(s.velocity, vToPlayer*lvlSparkSpeed(f)/pdist, SparkTurnSpeed*dT)
            updateMovable(s, dT)

        case Riding:
          if s.hitch == nil:
            s.state = SeekingRing
            s.velocity = normalize(center - s.pos) * lvlSparkSpeed(f)
          else:
            s.playerCheckInterval -= dT
            if s.playerCheckInterval <= 0.0:
              s.playerCheckInterval = MaxSparkReactionTime

              if pdist < lvlSparkAwarenessDist(f) and rnd_float() < SparkNoticeChance:
                s.state = SeekingPlayer
                s.velocity = normalize(jitter(vToPlayer/pdist, float2_1*0.2)) * lvlSparkSpeed(f)

            if s.state == Riding:  // still
              if s.hitch.targetRadius == 0.0 or s.hitch.segs[s.seg].hp <= 0.0:
                // Well crap, they shot the ring out from under us.
                s.state = SeekingPlayer
                s.velocity = normalize(jitter(vToPlayer/pdist, float2_1*0.2)) * lvlSparkSpeed(f)
              else:
                s.pos = ringMidpoint(s.hitch, s.seg, center)

        case SeekingRing:
          let vToFort = center - s.pos
          let fortDist = magnitude(vToFort)

          if pdist < lvlSparkAwarenessDist(f):
            s.state = SeekingPlayer
          else:
            if fortDist <= OuterRingRadius*0.7:
              let ring = rnd(length(f.rings))
              let seg = rnd(length(f.rings[ring].segs))

              if not anySparkOnSeg(f, f.rings[ring], seg) and f.rings[ring].segs[seg].hp > 0:
                s.hitch = f.rings[ring]
                s.seg = seg
                s.state = Riding
            else:
              s.velocity= lerp(s.velocity, vToFort*lvlSparkSpeed(f)/fortDist, SparkTurnSpeed*dT)
              updateMovable(s, dT)

      if s.state == SeekingPlayer or s.state == SeekingRing:
        s.soundInterval -= dT
        if s.soundInterval <= 0.0:
          play_sound("data/sfx/sparkmove.sfxr", Volume)
          s.soundInterval += 0.3

// Returns true if there is already a spark
// riding on the given segment.
def anySparkOnSeg(f: Fort, ring: Ring?, seg: int):
  return exists(f.sparks) s:
    s.state == Riding and s.hitch == ring and s.seg == seg

// Returns the midpoint of the ring segment addressed by
// `hitch`.
def ringMidpoint(ring: Ring, seg: int, center: float2):
  let numSegs = length(ring.segs)
  let dang = 360.0 / numSegs
  let ang = ring.rot + dang * float(seg)
  let ang2 = ang + dang*0.5

  return center + sincos(ang2) * ring.radius

def respaceRings(rings):
  for(rings) r, i:
    r.targetRadius = (1+i)*RingMargin

def canFire(f:: Fort):
  return f.cannonCooldown <= 0.0

def renderFort(f: Fort, pfDims, pixelLineWidth):
  for(f.rings) r: render(r, pfDims, pixelLineWidth)
  if f.state != Dying:
    renderSparks(f, pfDims, pixelLineWidth)

  var col = color_white 
  var scale = 1.0

  if f.state == Dying:
    // Shrink away.  Would look better to explode into pieces.
    let c = rnd_float() 
    col = color {c, c, c, 1.0}
    scale = max(0.0, f.timeToRespawn) / (3.0*DeathPeriod)
  else:
    // Turn blue and jitter color when charged and ready to fire.
    let fact = max(0.0, f.cannonCooldown) / MaxPlasmaCooldown
    let bc = lerp(1.0, 0.0, fact)
    col = color {1.0-bc, 1.0-bc, bc, 1.0}

  gl.color(col)
  gl.translate(pfDims*0.5):
    gl.scale(scale):
      gl.rotate_z(f.cannonRot):
        loop(1,length(CannonLines)-1) i:
          gl.line(CannonLines[i-1], CannonLines[i], pixelLineWidth)

  gl.color(color_white)
  for(f.plasmaBalls) p:
    renderSparkleBall(p.pos, 15, PlasmaRadius, PlasmaRadius/4.0, pixelLineWidth)

def render(r: Ring, pfDims: float2, pixelLineWidth):
  liveSegments(r, pfDims) p1, p2, sg:
    gl.color(r.color * (sg.hp + 1) / (SegMaxHp+1))
    gl.line(p1, p2, pixelLineWidth + pixelLineWidth*rnd_float()*1.5)

def liveSegments(r: Ring, pfDims: float2, blk):
  let center = pfDims * 0.5
  for(r.segs) s, i: 
    if s.hp > 0:
      let a1  = r.rot + i * SegArc
      let a2  = a1 + SegArc
      let sc1 = sincos(a1) * r.radius + center
      let sc2 = sincos(a2) * r.radius + center
      blk(sc1, sc2, s)

def mkRing(radius, color):
  let r = Ring {segs: [], 
                rot: 0.0, radius: 0.0, targetRadius: radius, color: color }
  for(SegsPerRing): r.segs.push(Seg{})
  return r

def initRings(f: Fort, rings):
  rings.push(mkRing(RingMargin, color_white))
  rings.push(mkRing(RingMargin * 2.0, color_blue))
  rings.push(mkRing(RingMargin * 3.0, color_green))

//
// Misc
//

def updateMovable(m, dT: float):
  m.pos += m.velocity * dT

def mkStarfield():
  let z = 0.0
  let nPts = 120
  let pps = []
  let colors = []

  for(nPts):
    // The window size may change, so for now generate
    // stars in wider world coordinate system than necessary.
    // The y coordinate in the world system is always 1.
    pps.push(float3 {rnd_float() * 3.0, rnd_float(), z})
    colors.push(float4 {rnd_float() * 0.2, rnd_float() * 0.7, rnd_float() * 0.8,
      1.0})

  let rv = gl.new_mesh("PC", pps, colors, [], [], [])
  gl.mesh_pointsize(rv, 1.0)
  return rv

def renderStarfield(mesh, pixelLineWidth: float):
  gl.point_scale(1.0 / pixelLineWidth / jitter(150.0, 80.0))
  gl.set_shader("color_attr_particle")
  gl.render_mesh(mesh)
  gl.set_shader("color")

def inPlayfield(p, pfDims):
  return p.x >= -WrapMargin and p.y >= -WrapMargin and p.x <= (pfDims.x+WrapMargin) and p.y <= (pfDims.y+WrapMargin)

def renderSparkleBall(pos: float2, numLines: int, radius, radiusJitter, pixelLineWidth):
  for(numLines):
    let v = jitter(sincos(360.0*rnd_float())*radius, float2{radiusJitter, radiusJitter})
    gl.line(pos, pos + v,
      jitter(pixelLineWidth, pixelLineWidth*2.0))

// Sounds are loaded lazily.  Not a problem for most things, but
// the lag is noticable for some, so we do this to preload some
// of the sounds at startup.
def preloadSounds():
  let snds = [ "data/sfx/fortboom.sfxr",
    "data/sfx/playerboom.sfxr",
    "data/sfx/ringgrow.sfxr",
    "data/sfx/pshot.sfxr" ]

  for(snds) s: play_sound(s, 1)

go()
