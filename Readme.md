# Turing Machine Interpreter
Runs turing machines and visualizes them.
Store Turing machines in .tumi files.

Example:
```
TM1: 
a 0 2 -> b
a 1 2 -> <H>
# This is a comment

run TM1 [0 2 0 0]
trace TM1 [0 2 0 0]
render TM1 [0 2 0 0]
```
<current state> <read frome tape> <write to tape> <head movement> <next state> 
- `<head movement>`: Either `->`(right), `<-` (left), `.` (stays at current position)
- `<next state>`: `<H>` as a reserved symbol for the halting state
- `-` is the default symbol for Blank
