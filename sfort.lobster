//TODO move rings array into Fort class.  Fort will also keep up with
//     the cannon state, and the sparks.  May move it to its own module
//     to clean things up a bit. And also the state needed to animate
//     new ring growth.

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
let SegMaxHp = 3
let PlasmaSpeed = 0.5
let MaxPlasmaCooldown = 1.0
let CannonRadius = RingMargin / 2 // Used for collision detection.
let DeathPeriod = 5               // Number of seconds before a cannon respawns.
let SegPoints = 5                 // number of points for destroying a segment.

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

class Bullet:
  pos: xy_f
  velocity: xy_f

enum FortState:
  Seeking
  Dying

class Fort:
  rings: [Ring]
  cannonRot: xy_f       // sincos of cannon rotation.
  rotSpeed: float       // This increases with levels.
  cannonCooldown: float // Can't fire until <= 0.
  plasmaBalls: [Bullet]
  state: FortState
  timeToRespawn: float

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
    state = Dying
    timeToRespawn = DeathPeriod
    for(rings) r:
      r.targetRadius = 1.mils // Collapsing rings.

// Called to move
def respawnFort(f:: Fort):
  if state != Seeking:
    state = Seeking
    respaceRings(rings)
    for(rings) r:
      for(r.segs) sg:
        sg.hp = SegMaxHp
    //TODO increase rot speed etc.

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
    let msg = "score: " + p.score
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
     cannonRot: xy_x, rotSpeed: 1, cannonCooldown: MaxPlasmaCooldown,
     plasmaBalls: [], state: Seeking, timeToRespawn: 0 }

  initRings(rv.rings)
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
    cannonRot = lerp(cannonRot, xy_f{cannonRot.y, cannonRot.x}, rotSpeed*dT)
    print "ass"
  else:
    let na = lerp(cannonRot, vToPlayer, rotSpeed*dT)

    if not almost(0, magnitude(na), 0.001):
      cannonRot = normalize(na)

  var numSegsBroke = 0
  plasmaBalls, numSegsBroke = updateBullets(plasmaBalls, f, dT, pfDims)

  cannonCooldown -= dT
  switch state:
    case Seeking:
      if canFire() and not hitRingSegment(f, center, cannonRot*2, pfDims):
        cannonCooldown = MaxPlasmaCooldown
        plasmaBalls.push(Bullet{pos: center, velocity: cannonRot*PlasmaSpeed})

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

    case Dying:
      timeToRespawn -= dT
      if timeToRespawn <= 0:
        respawnFort()

  for(rings) r:
    let dRad = r.targetRadius - r.radius
    if not almost(dRad, 0, 0.001):
      r.radius += dT*dRad*2 
    r.rot += r.dRot * dT

def respaceRings(rings):
  for(rings) r, i:
    r.targetRadius = (1+i)*RingMargin

def canFire(f:: Fort):
  return f.cannonCooldown <= 0

def renderFort(f: Fort, pfDims, pixelLineWidth):
  for(f.rings) r: render(r, pfDims, pixelLineWidth)

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
    for(15):
      let v = sincos(360*rnd_float())*pfDims.y/(40+10*rnd_float())
      gl_line(p.pos, p.pos + v,
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

def initRings(rings):
  rings.push(mkRing(30.0, RingMargin, color_white))
  rings.push(mkRing(-30.0, RingMargin * 2, color_blue))
  rings.push(mkRing(35, RingMargin * 3, color_green))

def mkStarfield():
  let z = 0.0
  let nPts = 120
  let pps = vector_reserve(typeof return, nPts)
  let colors = vector_reserve(typeof return, nPts)

  rnd_seed(0xdeadbeef)
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
