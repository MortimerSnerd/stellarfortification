import std
import nonstd
import color
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

def mils(f: float): return f * 0.001
def percent(x): return float(x)*0.01

let segsPerRing= 12
let segArc = 360.0 / segsPerRing
let RingMargin = 40.mils          // Distances between rings.
let OuterRingRadius = RingMargin * 3
let WrapMargin = 18.mils          // How far past the window edge before we wrap to other side of screen.
let TurnSpeed = 230.0             // deg/s
let PlayerAccel = 1.0
let PlayerRadius = 15.mils
let ThrusterLen = 10.mils
let FireCooldown = 1/7.0
let SegMaxHp = 2
let PlasmaSpeed = 0.5
let MaxPlasmaCooldown = 1.0
let DPlasmaCooldown = 0.15
let CannonRadius = RingMargin / 2 // Used for collision detection.
let DeathPeriod = 5               // Number of seconds before a cannon respawns.
let SegPoints = 5                 // number of points for destroying a segment.
let BaseSparkSpeed = 0.15
let MinSparkAwareness = 1.0/5.0   // How close spark needs to be to player to notice them.
let DSparkAwareness = 0.05        // How much awareness range increases per level.
let SparkNoticeChance = 10.percent
let MaxSparkReactionTime = 0.3
let SparkTurnSpeed = 0.7          // How fast can we lerp a direction
let BaseRingSpeed = 45.0
let DRingSpeed = 10.0             // Degrees per second per level
let CannonRotSpeed = 1
let DCannonRotSpeed = 0.1         // Change in cannon rot speed per level.
var Volume = 32

// Line path used to draw cannon. Centered on 0,0
let CannonLines: [xy_f] = map([xy_0, xy_f{3,0}, xy_f{3,-1}, xy_f{1,-1}, xy_f{-3,-4},
  xy_f{ -2,-1}, xy_f{ -2,1}, xy_f{-3,4}, xy_f{1,1}, xy_f{3,1}, xy_f{3,0}]): _ * 5.mils

class Seg:
  hp = SegMaxHp

class Ring:
  segs: [Seg] // In order from inner ring to outer.
  rot: float
  dRot: float
  radius: float
  targetRadius: float
  color: color

enum SparkState:
  SeekingPlayer
  SeekingRing
  Riding

class Spark:
  pos: xy_f 
  dir: xy_f                        // Has a direction so we can fake momentum
  state: SparkState = SeekingRing
  hitch: Ring?                     // ring we are hitched to when state == Riding
  seg: int                         // ring #} when state == Riding
  playerCheckInterval: float = 0.0 // Reaction time of sparks noticing player.
  soundInterval = 0.0

class Bullet:
  pos: xy_f
  velocity: xy_f

enum FortState:
  Seeking
  Dying

class Fort:
  rings: [Ring]
  cannonRot: xy_f       // sincos of cannon rotation.
  cannonCooldown: float // Can't fire until <= 0.
  plasmaBalls: [Bullet]
  state: FortState
  timeToRespawn: float
  sparks: [Spark]
  numDeaths = 0         // Used to scale speeds etc for harder levels.

class Thingy:
  pos: xy_f
  velocity: xy_f
  vDecay: float
  rot: float
  dRot: float
  rotDecay: float

class Player: Thingy
  thrusting = true
  fireCooldown = 0.0
  bullets: [Bullet]
  score = 0


def go():
  fatal(gl_window("Stellar Fort", 640, 480))

  let BCD = 3.6
  var bgnoiseCooldown = 0.0

  let player = Player {pos: xy_f {0.7, 0.7}, velocity: xy_0, vDecay: 0.98, rot: 0.0, rotDecay: 0.75, dRot: 0.0,
    bullets: []}
  let fort = mkFort()
  let starfield = mkStarfield()

  while gl_frame() and gl_button("escape") != 1:
    let wdims = float(gl_window_size())
    let coordScale = xy_1 * wdims.y
    let playfieldDims = xy_f {wdims.x/wdims.y, 1.0}
    let pixelLineWidth = 1/wdims.y

    let dT = gl_delta_time()

    bgnoiseCooldown -= dT
    if bgnoiseCooldown <= 0 and fort.state != Dying:
      play_sfxr("data/sfx/bgnoise.sfxr", Volume)
      bgnoiseCooldown = BCD

    updateFort(fort, player, playfieldDims, dT)
    processInput(player, dT)
    updatePlayer(player, fort, playfieldDims, dT)

    gl_clear(color_black)
    gl_scale(coordScale):
      gl_color(color_blue)
      renderStarfield(starfield, pixelLineWidth)
      renderPlayer(player, fort, pixelLineWidth, wdims.y)
      renderFort(fort, playfieldDims, pixelLineWidth)

// Sets up the fort state for the death animation, and
// score screen.
def killFort(f:: Fort):
  if state != Dying:
    play_sfxr("data/sfx/fortboom.sfxr")
    state = Dying
    timeToRespawn = DeathPeriod
    for(rings) r:
      r.targetRadius = 1.mils // Collapsing rings.

// Called to move
def respawnFort(f:: Fort, pfDims):
  if state != Seeking:
    numDeaths++
    state = Seeking
    play_sfxr("data/sfx/fortspawn.sfxr", Volume)
    respaceRings(rings)
    for(rings) r, i:
      r.dRot = lvlRingSpeed(f, i)

      for(r.segs) sg:
        sg.hp = SegMaxHp
    //TODO increase rot speed etc.

    for(sparks) s:
      s.state = SeekingRing
      s.pos = pfDims*0.5

def lvlRingSpeed(f: Fort, ringIdx:int):
  let fac = if ringIdx == 1: -1 else: 1

  return fac*(BaseRingSpeed + (2-ringIdx)*15.0 + DRingSpeed*f.numDeaths)

def renderPlayer(p: Player, fort: Fort, lineWidth, winHeight):
  renderBullets(p, lineWidth)

  gl_translate(p.pos):
    let sc = sincos(p.rot)
    gl_rotate_z(sc):
      gl_line_mode(true):
        let d = PlayerRadius
        let rear1 = xy_f {-d, -d}
        let rear2 = xy_f {-d, d}

        if p.thrusting:
          // Draw the thruster exhaust.
          let mid = lerp(rear1, rear2, 0.5)
          gl_color(color_red)
          for(4): 
            gl_line(jitterY(mid, 0.005), jitterY(mid + xy_x * -ThrusterLen, 0.7*ThrusterLen), 
                    lineWidth)

        gl_color(color_white)
        gl_polygon([rear1, 
                    rear2, 
                    xy_f {d*1.5, 0.0}])

  if fort.state == Dying:
    let msg = "score: " + p.score + "     level: " + (fort.numDeaths)
    gl_color(color_blue)
    renderText(msg, 2/winHeight, lineWidth, xy_f{400.mils, 12.mils})

def processInput(p:: Player, dT: float):
  if gl_button("a") > 0:
    dRot = -TurnSpeed

  if gl_button("d") > 0:
    dRot = TurnSpeed

  if gl_button("w") > 0:
    velocity += sincos(rot) * PlayerAccel * dT
    thrusting = true
  else:
    thrusting = false

  fireCooldown -= dT
  if fireCooldown <=0 and gl_button("space") > 0:
    p.bullets.push(fireBullet(p))
    fireCooldown = FireCooldown
    play_sfxr("data/sfx/pshot.sfxr", Volume)

def updatePlayer(t:: Player, fort: Fort, pfDims: xy_f, dT: float):
  let vToPlayer = pos - pfDims * 0.5
  let minPush = 1
  if magnitude(vToPlayer) < (OuterRingRadius + PlayerRadius):
    // We do not want to worry about rings pushing
    // the ship around, so do not go in there.
    let n = normalize(vToPlayer)
    let nvel = normalize(velocity)

    // Don't interfere with the ship if it is heading away
    // from the fort.
    if dot(n, nvel) <= 0:
      if almost(magnitude(velocity), 0, 0.015):
        // Do not allow a lack of velocity from pushing
        // us out of there.
        velocity = n * -minPush * 0.10

      let reflect = velocity - n*2*dot(velocity, n)
      velocity = reflect * max(magnitude(velocity), minPush) * 0.8

  updateThingy(t, pfDims, dT)
  var numSegsBroke = 0
  bullets, numSegsBroke = updateBullets(bullets, fort, dT, pfDims)
  if fort.state != Dying:
    score += numSegsBroke * SegPoints

  if numSegsBroke > 0:
    play_sfxr("data/sfx/ringhit.sfxr", Volume)

  // Did we hit the cannon?
  if fort.state != Dying:
    let center = pfDims * 0.5
    for(bullets) b:
      let dist = magnitude(b.pos - center)
      if dist < CannonRadius:
        killFort(fort)
        score += 300
        return

def updateThingy(t:: Thingy, pfDims: xy_f, dT: float):
  pos += velocity * dT
  velocity *= vDecay

  rot += dRot * dT
  dRot *= rotDecay

  // Leaving edge of screen wraps around.
  if pos.x < -WrapMargin:
    pos += xy_f {pfDims.x + WrapMargin*2, 0}
  else:
    if pos.x > (pfDims.x+WrapMargin):
      pos -= xy_f{pfDims.x + WrapMargin*2, 0}

  if pos.y < -WrapMargin:
    pos += xy_f {0, pfDims.y + WrapMargin*2}
  else:
    if pos.y > (WrapMargin+1):
      pos -= xy_f{0, pfDims.y + WrapMargin*2}

def mkFort():
  let rv = Fort {rings: vector_reserve(typeof return, 3),
     cannonRot: xy_x,  cannonCooldown: MaxPlasmaCooldown,
     plasmaBalls: [], state: Dying, timeToRespawn: 0,
     sparks: initialSparks()}

  initRings(rv, rv.rings)
  return rv

def initialSparks():
  let rv = []
  for(3):
    rv.push(Spark{pos: xy_1*0.5, dir: xy_x, state: SeekingRing, hitch: nil, seg: 0})

  return rv


def updateFort(f:: Fort, player: Player, pfDims: xy_f, dT: float):
  let center = pfDims*0.5
  let vToPlayer = normalize(player.pos - center)

  if almost(-1.0, dot(vToPlayer, normalize(cannonRot)), 0.01):
    // The player is directly behind us. If we don't nudge
    // here, the turning will be painfully slow, since we're
    // essentially trying to lerp towards the center of the
    // cannon.  (maybe this vector lerping sucks more than
    // originally anticipated).
    cannonRot = normalize(lerp(cannonRot, xy_f{cannonRot.y, cannonRot.x}, lvlCannonRotSpeed(f)*dT))
  else:
    let na = lerp(cannonRot, vToPlayer, lvlCannonRotSpeed(f)*dT)

    if not almost(0, magnitude(na), 0.001):
      cannonRot = normalize(na)

  var numSegsBroke = 0
  plasmaBalls, numSegsBroke = updateBullets(plasmaBalls, f, dT, pfDims)
  if numSegsBroke:
    play_sfxr("data/sfx/ringhit.sfxr", Volume)

  cannonCooldown -= dT
  switch state:
    case Seeking:
      if canFire() and not hitRingSegment(f, center, cannonRot*2, pfDims):
        cannonCooldown = lvlPlasmaCooldown(f)
        plasmaBalls.push(Bullet{pos: center, velocity: cannonRot*PlasmaSpeed})
        play_sfxr("data/sfx/plasma.sfxr", max(128, 2*Volume))

      // Clean out any dead rings and regrow them.
      let live, dead = partition(rings) r:
        exists(r.segs) s:
          s.hp > 0

      if length(dead) > 0:
        // Dead rings regenerate from the inside.
        for(dead) r:
          r.radius = 0
          for(r.segs) s:
            s.hp = SegMaxHp

        rings = append(dead, live)
        respaceRings(rings)
        play_sfxr("data/sfx/ringgrow.sfxr")

    case Dying:
      timeToRespawn -= dT
      if timeToRespawn <= 0:
        respawnFort(pfDims)

  for(rings) r:
    let dRad = r.targetRadius - r.radius
    if not almost(dRad, 0, 0.001):
      r.radius += dT*dRad*2 
    r.rot += r.dRot * dT

  if f.state != Dying:
    updateSparks(f, player, dT, pfDims)

def renderSparks(f: Fort, pfDims, pixelLineWidth):
  gl_color(color_blue)
  for(f.sparks) s:
    let r1 = pfDims.y/100
    let r2 = pfDims.y/200

    if s.state == Riding:
      renderSparkleBall(s.pos, 3, r1, r2, pixelLineWidth)
    else:
      renderSparkleBall(s.pos, 3, r1*0.5, r2*0.5, pixelLineWidth)
      renderSparkleBall(s.pos+s.dir*r1*0.8, 3, r1*0.5, r2*0.5, pixelLineWidth)

// Plasma cannon cooldown scaled for level.
def lvlPlasmaCooldown(f: Fort):
  return max(0.1, MaxPlasmaCooldown - f.numDeaths*DPlasmaCooldown)

def lvlCannonRotSpeed(f: Fort):
  return CannonRotSpeed + f.numDeaths*DCannonRotSpeed

def updateSparks(f: Fort, player: Player, dT, pfDims):
  for(f.sparks) s:
    let vToPlayer = player.pos - s.pos
    let pdist = magnitude(vToPlayer)
    let center = pfDims*00.5

    if pdist < PlayerRadius:
      play_sfxr("data/sfx/playerboom.sfxr", Volume)
      //TODO more to do when player actually has a dead state.
    else:
      switch s.state:
        case SeekingPlayer:
          if pdist > lvlSparkAwarenessDist(f):
            s.state = SeekingRing
          else:
            s.dir = lerp(s.dir, vToPlayer/pdist, SparkTurnSpeed*dT)
            s.pos +=  s.dir * dT * BaseSparkSpeed

        case Riding:
          if s.hitch == nil:
            s.state = SeekingRing
            s.dir = normalize(center - s.pos)
          else:
            s.playerCheckInterval -= dT
            if s.playerCheckInterval <= 0:
              s.playerCheckInterval = MaxSparkReactionTime

              if pdist < lvlSparkAwarenessDist(f) and rnd_float() < SparkNoticeChance:
                s.state = SeekingPlayer
                s.dir = normalize(jitter(vToPlayer/pdist, xy_1*0.2))

            if s.state == Riding:  // still
              if s.hitch.targetRadius == 0 or s.hitch.segs[s.seg].hp <= 0:
                // Well crap, they shot the ring out from under us.
                s.state = SeekingPlayer
                s.dir = normalize(jitter(vToPlayer/pdist, xy_1*0.2))
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
              s.dir = lerp(s.dir, vToFort/fortDist, SparkTurnSpeed*dT)
              s.pos += s.dir*dT*BaseSparkSpeed

      if s.state == SeekingPlayer or s.state == SeekingRing:
        s.soundInterval -= dT
        if s.soundInterval <= 0:
          play_sfxr("data/sfx/sparkmove.sfxr", Volume)
          s.soundInterval += 0.3

// Returns spark awareness range, scaled for
// level.
def lvlSparkAwarenessDist(f: Fort):
  return MinSparkAwareness + f.numDeaths*DSparkAwareness

// Returns true if there is already a spark
// riding on the given segment.
def anySparkOnSeg(f: Fort, ring: Ring?, seg: int):
  return exists(f.sparks) s:
    s.state == Riding and s.hitch == ring and s.seg == seg

// Returns the midpoint of the ring segment addressed by
// `hitch`.
def ringMidpoint(ring: Ring, seg: int, center: xy_f):
  let numSegs = length(ring.segs)
  let dang = 360.0 / numSegs
  let ang = ring.rot + dang * float(seg)
  let ang2 = ang + dang*0.5

  return center + sincos(ang2) * ring.radius


def respaceRings(rings):
  for(rings) r, i:
    r.targetRadius = (1+i)*RingMargin

def canFire(f:: Fort):
  return f.cannonCooldown <= 0

def renderFort(f: Fort, pfDims, pixelLineWidth):
  for(f.rings) r: render(r, pfDims, pixelLineWidth)
  if f.state != Dying:
    renderSparks(f, pfDims, pixelLineWidth)

  var col = color_white 
  var scale = 1.0

  if f.state == Dying:
    // Shrink away.  Would look better to explode into pieces.
    let c = rnd_float() 
    col = color {c, c, c, 1}
    scale = max(0, f.timeToRespawn) / (3*DeathPeriod)
  else:
    // Turn blue and jitter color when charged and ready to fire.
    let fact = max(0, f.cannonCooldown) / MaxPlasmaCooldown
    let bc = lerp(1.0, 0.0, fact)
    col = color {1.0-bc, 1.0-bc, bc, 1.0}

  gl_color(col)
  gl_translate(pfDims*0.5):
    gl_scale(scale):
      gl_rotate_z(f.cannonRot):
        loop(1,length(CannonLines)-1) i:
          gl_line(CannonLines[i-1], CannonLines[i], pixelLineWidth)

  gl_color(color_white)
  for(f.plasmaBalls) p:
    renderSparkleBall(p.pos, 15, pfDims.y/40, pfDims.y/60, pixelLineWidth)

def renderSparkleBall(pos: xy_f, numLines: int, radius, radiusJitter, pixelLineWidth):
  for(numLines):
    let v = jitter(sincos(360*rnd_float())*radius, xy_f{radiusJitter, radiusJitter})
    gl_line(pos, pos + v,
      jitter(pixelLineWidth, pixelLineWidth*2))

def render(r: Ring, pfDims: xy_f, pixelLineWidth):
  liveSegments(r, pfDims) p1, p2, sg:
    gl_color(r.color * (sg.hp + 1) / (SegMaxHp+1))
    gl_line(p1, p2, pixelLineWidth + pixelLineWidth*rnd_float()*1.5)

def liveSegments(r: Ring, pfDims: xy_f, blk):
  let center = pfDims * 0.5
  for(r.segs) s, i: 
    if s.hp > 0:
      let a1  = r.rot + i * segArc
      let a2  = a1 + segArc
      let sc1 = sincos(a1) * r.radius + center
      let sc2 = sincos(a2) * r.radius + center
      blk(sc1, sc2, s)

def mkRing(dRot, radius, color):
  let r = Ring {segs: vector_reserve(typeof return, segsPerRing), 
                rot: 0.0, dRot: dRot, radius: 0, targetRadius: radius, color: color }
  for(segsPerRing): r.segs.push(Seg{})
  return r

def initRings(f: Fort, rings):
  rings.push(mkRing(lvlRingSpeed(f, 0), RingMargin, color_white))
  rings.push(mkRing(lvlRingSpeed(f, 1), RingMargin * 2, color_blue))
  rings.push(mkRing(lvlRingSpeed(f, 2), RingMargin * 3, color_green))

def mkStarfield():
  let z = 0.0
  let nPts = 120
  let pps = vector_reserve(typeof return, nPts)
  let colors = vector_reserve(typeof return, nPts)

  for(nPts):
    // The window size may change, so for now generate
    // stars in wider world coordinate system than necessary.
    // The y coordinate in the world system is always 1.
    pps.push(xyz_f {rnd_float() * 3, rnd_float(), z})
    colors.push(xyzw_f {rnd_float() * 0.2, rnd_float() * 0.7, rnd_float() * 0.8,
      1.0})

  let rv = gl_new_mesh("PC", pps, colors, [], [], [])
  gl_mesh_pointsize(rv, 1)
  return rv

def renderStarfield(mesh, pixelLineWidth: float):
  gl_point_scale(1 / pixelLineWidth / jitter(150, 80))
  gl_set_shader("color_attr_particle")
  gl_render_mesh(mesh)
  gl_set_shader("color")

def renderBullets(pl: Player, pixelLineWidth):
  for(pl.bullets) b:
    let p1 = b.pos + normalize(b.velocity) * 6.mils
    gl_line(b.pos, p1, 2 * pixelLineWidth)

// Updates the bullets, and removes any that have
// hit something, or gone off the playfield
def updateBullets(bs: [Bullet], f: Fort, dT: float, pfDims: xy_f) -> [Bullet], int:
  var segsKilled = 0
  let newbs = filter(bs) b:
    let oldpos = b.pos
    b.pos += b.velocity * dT
    let sg = hitRingSegment(f, oldpos, b.pos, pfDims)
    if sg:
      sg.hp--
      segsKilled++

    inPlayfield(b.pos, pfDims) and not sg

  return newbs, segsKilled

def inPlayfield(p, pfDims):
  return p.x >= -WrapMargin and p.y >= -WrapMargin and p.x <= (pfDims.x+WrapMargin) and p.y <= (pfDims.y+WrapMargin)

// Tests for a hit against a ring segment.
// If there is a hit, returns the segment, nil otherwise.
def hitRingSegment(f: Fort, p0, p1: xy_f, pfDims: xy_f) -> Seg?:
  for(f.rings) r:
    liveSegments(r, pfDims) x0, x1, sg:
      let hit, hpos = line_intersect(p0, p1, x0, x1)
      if hit:
        return sg

  return nil

// Returns a new bullet to be added to the bullets
// array.
def fireBullet(pl: Player):
  return Bullet{pos: pl.pos, velocity: sincos(pl.rot) + pl.velocity}
go()
