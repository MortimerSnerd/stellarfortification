import std
import color
import vec

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

class Seg:
  hp = 3 

class Ring:
  segs: [Seg]
  rot: float
  dRot: float
  radius: float
  color: color

class Thingy:
  pos: xy_f
  velocity: xy_f
  vDecay: float
  rot: float
  dRot: float
  rotDecay: float

class Player: Thingy
  thrusting = true

var rings = []

def go():
  fatal(gl_window("Stellar Fort", 640, 480))
  initRings()

  let player = Player {pos: xy_f {0.7, 0.7}, velocity: xy_y, vDecay: 0.98, rot: 0.0, rotDecay: 0.9, dRot: 0.0}
  let starfield = mkStarfield()

  while gl_frame() and gl_button("escape") != 1:
    let wdims = float(gl_window_size())
    let dT = gl_delta_time()
    updateRings(dT)
    processInput(player, dT)
    updatePlayer(player, dT)

    gl_clear(color_black)
    gl_scale(wdims.y):
      renderStarfield(starfield, wdims)
      renderPlayer(player, wdims)
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

def almost(a: float, b:float, eps:float):
  return abs(a - b) <= eps

def updatePlayer(t:: Player, dT: float):
  let vToPlayer = pos - Center
  let minPush = 1
  if magnitude(vToPlayer) < (rings.top().radius + PlayerRadius):
    // We do not want to worry about rings pushing
    // the ship around, so do not go in there.
    let n = normalize(vToPlayer)

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
  gl_color(r.color)
  liveSegments(r, wdims) p1, p2:
    gl_line(p1, p2, 1/wdims.y)

def liveSegments(r: Ring, wdims: xy_f, blk):
  let center = xy_f{0.5, 0.5}
  for(r.segs) s, i: 
    if s.hp > 0:
      let a1  = r.rot + i * segArc
      let a2  = a1 + segArc
      let sc1 = sincos(a1) * r.radius + center
      let sc2 = sincos(a2) * r.radius + center
      blk(sc1, sc2)

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
  rings[0].segs[3].hp = 0

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


go()
