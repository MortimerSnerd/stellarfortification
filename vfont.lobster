// Port of a debugging vector font I wrote for debugging
// in Nim.
import std
import nonstd
import vec

// Sentinel marking end of continuous line.
private let EndLine = 255

// Sentinel for end of sequence of lines making up a letter.
private let EndLetter = 254

// Code for character we draw when we encounter a 
// character not in the font
private let UnknownChar = 1

private class LT:
  ch: int
  lines: [int]

private let letters = [
  LT{UnknownChar, [1, 6,  0, 7,  0, 9,  1, 10,  5, 10,  6, 9,  6, 6,  5, 5,  4, 5, 3, 4, 3, 2,  EndLine, 3, 0,  3, 1]},
  LT{'!', [1, 0,  0, 7,  EndLine, 0, 9, 0, 10]},
  LT{'(', [2, 0,  0, 2,  0, 8, 2, 10]},
  LT{')', [1, 0,  3, 2,  3, 8,  1, 10]},
  LT{',', [1, 9,  1, 10,  0, 11]},
  LT{'-', [1, 5, 4, 5]},
  LT{'.', [0, 9, 0, 10]},
  LT{'0', [0, 1,  0, 9,  1, 10,  3, 10,  4, 9,  4, 1,  3, 0,  1, 0, 0, 1,  EndLine,  2, 4,  2, 6]},
  LT{'1', [0, 1,  2, 0,  2, 10]},
  LT{'2', [0, 1,  1, 0,  3, 0,  4, 1,  4, 5,  0, 10,  4, 10]},
  LT{'3', [0, 1,  1, 0,  3, 0,  4, 1,  4, 4,  3, 5,  1, 5,  EndLine,  3, 5,  4, 6,  4, 9,  3, 10,  1, 10,  0, 9]},
  LT{'4', [0, 0,  0, 4,  4, 4,  EndLine,  3, 0,  3, 10]},
  LT{'5', [0, 9,  1, 10,  3, 10,  4, 9,  4, 5,  3, 4,  1, 4,  0, 4,  0, 0,  4, 0]},
  LT{'6', [4, 1,  3, 0,  1, 0,  0, 1,  0, 9,  1, 10,  3, 10,  4, 9,  4, 5,  3, 5,  0, 5]},
  LT{'7', [0, 0,  4, 0, 2, 10]},
  LT{'8', [0, 1,  0, 4,  1, 5, 0, 6,  0, 9,  1, 10,  3, 10,  4, 9,  4, 6,  3, 5,  4, 4,  4, 1,  3, 0,  1, 0,  0, 1,  EndLine,  1, 5,  3, 5]},
  LT{'9', [4, 10,  4, 1,  3, 0,  1, 0,  0, 1,  0, 4,  1, 5,  4, 5]},
  LT{':', [0, 2,  0, 3,  EndLine,  0, 7,  0, 8]},
  LT{'=', [0, 4,  4, 4,  EndLine,  0, 6,  4, 6]},
  LT{'?', [0, 3,  0, 1,  1, 0,  3, 0,  4, 1,  4, 5,  3, 6,  3, 7,  EndLine,  3, 9, 3, 10]},
  LT{'A', [0, 10,  0, 3,  3, 0,  6, 3,  6, 10,  EndLine,  0, 5,  6, 5]},
  LT{'B', [0, 0,  0, 10,  5, 10,  6, 8,  6, 5,  5, 4,  6, 3,  6, 2,  4, 0,  0, 0,  EndLine, 0, 4,  5, 4]},
  LT{'C', [6, 1,  5, 0,  1, 0,  0, 1, 0, 9,  1, 10,  5, 10,  6, 9]},
  LT{'D', [0, 0,  0, 10,  3, 10,  6, 8,  6, 2,  3, 0,  0, 0]},
  LT{'E', [6, 0,  0, 0,  0, 10,  6, 10,  EndLine,  0, 5,  5, 5]},
  LT{'F', [6, 0,  0, 0,  0, 10,  EndLine,  0, 5,  5, 5]},
  LT{'G', [6, 1,  5, 0,  1, 0,  0, 1,  0, 9,  1, 10,  5, 10,  6, 9,  6, 6,  4, 6]},
  LT{'H', [0, 0,  0, 10,  EndLine,  6, 0,  6, 10,  EndLine,  0, 5,  6, 5]},
  LT{'I', [0, 0,  6, 0,  EndLine,  0, 10,  6, 10,  EndLine,  3, 0,  3, 10]},
  LT{'J', [0, 7,  0, 8,  2, 10,  5, 10,  6, 7,  6, 0,  4, 0]},
  LT{'K', [0, 0,  0, 10,  EndLine,  6, 0,  0, 5,  6, 10]},
  LT{'L', [0, 0,  0, 10,  6, 10]},
  LT{'M', [0, 10,  1, 0,  3, 5,  5, 0,  6, 10]},
  LT{'N', [0, 10,  0, 0,  6, 10,  6, 0]},
  LT{'O', [0, 2,  0, 8,  2, 10,  4, 10,  6, 8,  6, 2,  4, 0,  2, 0,  0, 2]},
  LT{'P', [0, 10,  0, 0,  4, 0,  6, 1,  6, 4,  5, 5,  0, 5]},
  LT{'Q', [0, 2,  0, 8,  2, 10,  4, 10,  6, 8,  6, 2,  4, 0,  2, 0,  0, 2, EndLine,  6, 11,  4, 8]},
  LT{'R', [0, 10,  0, 0,  5, 0,  6, 1,  6, 4,  5, 5,  0, 5,  EndLine, 4, 5,  6, 10]},
  LT{'S', [0, 9,  1, 10,  5, 10,  6, 9,  6, 6,  5, 5,  1, 5,  0, 4,  0, 1,  1, 0,  5, 0,  6, 1]},
  LT{'T', [0, 0,  6, 0,  EndLine,  3, 0,  3, 10]},
  LT{'U', [0, 0,  0, 9,  1, 10,  5, 10,  6, 9,  6, 0]},
  LT{'V', [0, 0,  3, 10,  6, 0]},
  LT{'W', [0, 0,  1, 10,  3, 5,  5, 10,  5, 0]},
  LT{'X', [0, 0,  6, 10,  EndLine,  6, 0,  0, 10]},
  LT{'Y', [3, 10,  3, 5,  0, 0,  EndLine, 3, 5,  6, 0]},
  LT{'Z', [0, 0,  6, 0,  0, 10,  6, 10]}
]

// Ensure at runtime our array is in order.
loop(1, length(letters)-1) i:
  assert letters[i-1].ch < letters[i].ch

// Iterates all the lines for a given letter at
// the given scale.
private let NoLast = xy_1 * -1.0
private def lines(ix, scale: float, body):
  var pc = 0
  var last = NoLast

  while pc < length(letters[ix].lines):
    if letters[ix].lines[pc] == EndLine:
      last = NoLast
      pc += 1
    else:
      let x = letters[ix].lines[pc++]
      let y = letters[ix].lines[pc++]

      assert x >= 0 and y >= 0
      let p = xy_f{x*scale, y*scale}

      if last != NoLast:
        body(last, p)
      last = p

// Just a linear search for now.
private def lookupLetterIndex(c: int) -> int:
  for(letters) l,i:
    if c == l.ch:
      return i

  // None found, return index of UnknownChar.
  return lookupLetterIndex(UnknownChar)

// Renders a letter, and returns the maximum xy value
// drawn to.
private def renderLetter(c: int, scale: float, lineWidth: float, pos: xy_f, drawing: bool):
  if c == 32:
    return pos + xy_f{4*scale, 0}
  else:
    let ix = lookupLetterIndex(c)
    var maxp = pos

    lines(ix, scale) o1, o2:
      let p1 = o1 + pos
      let p2 = o2 + pos

      if drawing:
        gl_line(p1, p2, lineWidth)

      maxp = xy_f{max(maxp.x, p1.x), max(maxp.y, p1.y)}
      maxp = xy_f{max(maxp.x, p2.x), max(maxp.y, p2.y)}

    return maxp

// Renders a string, returning the maxium xy value drawn to.
private let LetterSpacing=2
private def renderText(msg: string, scale: float, lineWidth: float, pos: xy_f, drawing: bool):
  var cpos = pos

  var maxy = cpos.y
  for(uppercase(msg)) c:
    let blk = renderLetter(c, scale, lineWidth, cpos, drawing) + LetterSpacing * scale
    maxy = max(maxy, blk.y)
    cpos = xy_f {blk.x, cpos.y}

  return xy_f{cpos.x, maxy}

// Renders a string, returning the maxium xy value drawn to.
def renderText(msg: string, scale: float, lineWidth: float, pos: xy_f):
  return renderText(msg, scale, lineWidth, pos, true)

// Returns xy_f dims of text when rendered.
def textDims(msg: string, scale: float):
  return renderText(msg, scale, 1, xy_0, false)

// Renders a string centered on `pos`, returning the maxium xy value drawn to.
def renderCenteredText(msg: string, scale: float, lineWidth: float, pos: xy_f):
  let dims = textDims(msg, scale)

  renderText(msg, scale, lineWidth, pos - dims*0.5, true)

