//TODO fix scaling so we can use the entire screen.
//     if we have to letterbox, at least do it in a
//     way that it is centered.
//TODO move rings array into Fort class.  Fort will also keep up with
//     the cannon state, and the sparks.  May move it to its own module
//     to clean things up a bit. And also the state needed to animate
//     new ring growth.

import std
import color
import vec
import vfont

// Notes
// Coordinates are "world" coordinates, unless
// otherwise specified.  The entire playfield is
// mapped to (0,0) - (1,1), with it scaled for the
// height of the window.

def mils(f: float): return f * 0.001

let segsPerRing= 12
let segArc = 360.0 / segsPerRing
let RingMargin = 40.mils       // Distances between rings. 
let WrapMargin = 18.mils       // How far past the window edge before we wrap to other side of screen.
let TurnSpeed = 230.0          // deg/s
let PlayerAccel = 1.0
let PlayerRadius = 15.mils
let ThrusterLen = 10.mils
let Center = xy_f { 0.5, 0.5 } // Center in "world" coordinates.
let FireCooldown = 1/5.0
let SegMaxHp = 3

class Seg:
  hp = SegMaxHp 

class Ring:
  segs: [Seg]
  rot: float
  dRot: float
  radius: float
  color: color

class Fort:
  rings: [Ring] = []


class Thingy:
  pos: xy_f
  velocity: xy_f
  vDecay: float
  rot: float
  dRot: float
  rotDecay: float

class Bullet:
  pos: xy_f
  velocity: xy_f

class Player: Thingy
  thrusting = true
  fireCooldown = 0.0
  bullets: [Bullet]

var rings = []

def go():
  fatal(gl_window("Stellar Fort", 640, 480))
  initRings()

  let player = Player {pos: xy_f {0.7, 0.7}, velocity: xy_y, vDecay: 0.98, rot: 0.0, rotDecay: 0.85, dRot: 0.0,
    bullets: []}
  let starfield = mkStarfield()

  while gl_frame() and gl_button("escape") != 1:
    let wdims = float(gl_window_size())
    let dT = gl_delta_time()
    updateRings(dT)
    player.bullets = updateBullets(player.bullets, dT, wdims)
    processInput(player, dT)
    updatePlayer(player, dT)

    gl_clear(color_black)
    gl_scale(wdims.y):
      gl_color(color_blue)
      renderText("Eat a crap?", 2/wdims.y, 1/wdims.y, xy_f{12.mils, 12.mils})
      renderStarfield(starfield, wdims)
      renderPlayer(player, wdims)
      renderBullets(player, wdims)

      for(rings) r: render(r, wdims)
      gl_line_mode(true):
        gl_translate(xy_f {0.5, 0.5}):
          gl_rect(xy_1/2, true)

def jitterY(p: xy_f, amt: float):
  return p + xy_y * 2 * (rnd_float() - 0.5) * amt

def renderPlayer(p: Player, wdim: xy_f):
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
                    1/wdim.y)

        gl_color(color_white)
        gl_polygon([rear1, 
                    rear2, 
                    xy_f {d*1.5, 0.0}])


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

def almost(a: float, b:float, eps:float):
  return abs(a - b) <= eps

def updatePlayer(t:: Player, dT: float):
  let vToPlayer = pos - Center
  let minPush = 1
  if magnitude(vToPlayer) < (rings.top().radius + PlayerRadius):
    // We do not want to worry about rings pushing
    // the ship around, so do not go in there.
    let n = normalize(vToPlayer)
    let nvel = normalize(velocity)

    // Only futz with the velocity if we're heading
    // into the rings.  Don't interfere with the ship
    // if it is heading out.
    if dot(n, nvel) <= 0:
      if almost(magnitude(velocity), 0, 0.015):
        // Do not allow a lack of velocity from pushing
        // us out of there.
        velocity = n * -minPush * 0.10

      let reflect = velocity - n*2*dot(velocity, n)
      velocity = reflect * max(magnitude(velocity), minPush) * 0.8

  updateThingy(t, dT)

def updateThingy(t:: Thingy, dT: float):
  pos += velocity * dT
  velocity *= vDecay

  rot += dRot * dT
  dRot *= rotDecay

  // Leaving edge of screen wraps around.
  if pos.x < -WrapMargin:
    pos += xy_x + WrapMargin*2
  else:
    if pos.x > (1+WrapMargin):
      pos -= xy_x + WrapMargin*2

  if pos.y < -WrapMargin:
    pos += xy_y + WrapMargin*2
  else:
    if pos.y > (WrapMargin+1):
      pos -= xy_y + WrapMargin*2

def updateRings(dT: float): 
  for(rings) r:
    r.rot += r.dRot * dT

def render(r: Ring, wdims: xy_f):
  //TODO color modified by ring segment hp.
  liveSegments(r, wdims) p1, p2, sg:
    gl_color(r.color * (sg.hp + 1) / (SegMaxHp+1))
    gl_line(p1, p2, (1 + rnd_float()*2)/wdims.y)

def liveSegments(r: Ring, wdims: xy_f, blk):
  let center = xy_f{0.5, 0.5}
  for(r.segs) s, i: 
    if s.hp > 0:
      let a1  = r.rot + i * segArc
      let a2  = a1 + segArc
      let sc1 = sincos(a1) * r.radius + center
      let sc2 = sincos(a2) * r.radius + center
      blk(sc1, sc2, s)

def mkRing(dRot, radius, color):
  let r = Ring {segs: vector_reserve(typeof return, segsPerRing), 
                rot: 0.0, dRot: dRot, radius: radius, color: color }
  for(segsPerRing): r.segs.push(Seg{})
  return r 

def initRings():
  rings = vector_reserve(typeof return, 3)
  rings.push(mkRing(30.0, RingMargin, color_white))
  rings.push(mkRing(-30.0, RingMargin * 2, color_blue))
  rings.push(mkRing(35, RingMargin * 3, color_green))

def mkStarfield():
  let z = 0.0
  let nPts = 40
  let pps = vector_reserve(typeof return, nPts)
  let colors = vector_reserve(typeof return, nPts)

  rnd_seed(0xdeadbeef)
  for(nPts):
    pps.push(xyz_f {rnd_float(), rnd_float(), z})
    colors.push(xyzw_f {rnd_float() * 0.2, rnd_float() * 0.7, rnd_float() * 0.8,
      1.0})

  let rv = gl_new_mesh("PC", pps, colors, [], [], [])
  gl_mesh_pointsize(rv, 1)
  return rv

def jitter(f: float, range: float):
  return f + (rnd_float() * range - range/2)

def renderStarfield(mesh, wdims: xy_f):
  gl_point_scale( wdims.y / jitter(150, 80) )
  gl_set_shader("color_attr_particle")
  gl_render_mesh(mesh)
  gl_set_shader("color")

def renderBullets(pl: Player, wdims: xy_f):
  for(pl.bullets) b:
    let p1 = b.pos + normalize(pl.velocity) * 3.mils
    gl_line(b.pos, p1, 2/wdims.y)

def updateBullets(bs: [Bullet], dT: float, wdims: xy_f):
  return filter(bs) b:
    let newpos = b.pos +  b.velocity * dT
    let rv = inPlayfield(b.pos) and not hitRingSegment(b.pos, newpos, wdims)
    b.pos = newpos
    rv

def inPlayfield(p):
  return p.x >= -WrapMargin and p.y >= -WrapMargin and p.x <= (1+WrapMargin) and p.y <= (1+WrapMargin)

// Tests for a hit against a ring segment.
// If there is a hit, the ring is damaged, and
// this returns true.
def hitRingSegment(p0, p1: xy_f, wdims: xy_f):
  for(rings) r:
    liveSegments(r, wdims) x0, x1, sg:
      let hit, hpos = line_intersect(p0, p1, x0, x1)
      if hit:
        sg.hp--
        return true

  return false

// Returns a new bullet to be added to the bullets
// array.
def fireBullet(pl: Player):
  return Bullet{pos: pl.pos, velocity: sincos(pl.rot) + pl.velocity}
go()
