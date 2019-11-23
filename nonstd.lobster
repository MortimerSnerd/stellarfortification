// Generic utility functions not specific to any project.
import vec

// Jitters `p` along the y axis
// by ± `amt`.
def jitterY(p: xy_f, amt: float):
  return p + xy_y * 2 * (rnd_float() - 0.5) * amt

// Jitters `f` by ± `range`.
def jitter(f: float, range: float):
  return f + (rnd_float() * range - range/2)

// Jitters `p` by {±range.x, ±range.y}
def jitter(p: xy_f, range: xy_f):
  return xy_f{jitter(p.x, range.x), jitter(p.y, range.y)}

// Are `a` and `b` equal with a tolerance of `eps`?
def almost(a: float, b:float, eps:float):
  return abs(a - b) <= eps

// Loop with index from `start` to `end`, by 1. 
def loop(start, end, body):
  var i = start
  while i <= end:
    body(i)
    i++


