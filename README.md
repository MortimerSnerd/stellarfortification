# What is it?

Playing around with the Lobster language

Cloning the Star Castle arcade game as a way to 
give direction while learning the language.

![that's not good](/doc/ss.png)

So far, I've found Lobster to be a pretty fun
language to play around in.  I'm probably not
using HOF as much as the language allows, but
I can always review the code at the end and
see if I missed any oportunities to make the code
more clear.

It is surprising how tangled the state can get
for such a simple game.

## Running

You'll need the lobster compiler/interpreter itself, 
which you can get [here](https://github.com/aardappel/lobster)

Then just run:

		lobster sfort.lobster

## Controls

`A` and `D` to turn, `W` to go forward, and 
`Space` to fire.  `Escape` quits. `P` pauses.

## Status

All the pieces are there.  The cannon and sparks are 
implemented, and things get more hectic the more times 
you kill the cannon.  There's a banner and game over
screen now too.

The main thing left is reviewing the code. I know there's
some sloppy state handling that's caused most of the
final bugs, especially around state changes. And I suspect
there's some boilerplate that can be cleaned up by
making better use of Lobster's features.
