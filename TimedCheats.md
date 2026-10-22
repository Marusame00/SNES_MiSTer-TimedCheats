# Timed Cheats

A "for fun" fork feature of [SNES_MiSTer](https://github.com/MiSTer-devel/SNES_MiSTer)
that lets you control **when** your loaded cheats kick in, on a real-time clock,
instead of all of them being on the moment the game starts.

The idea: pick a few cheats that alter how a game plays, and have them switch on,
off, or in, at chosen time points for a bit of "planned spontaneity" — a recolor
that pops in for 5 seconds, a hard-mode cheat that unlocks after 1 minute, an
invincibility that flickers on/off every 10 seconds, etc.

## The basics

Everything is driven by a real-time elapsed-seconds counter that:

- starts counting **the first time you close the OSD menu after a game loads**,
- is derived from the SNES's own 21.28/21.48 MHz clock (accurate regardless of
  video refresh rate or region), and
- resets when you load a new game or reset the core.

There are **three independent knobs**, all in the new `P4,Timed Cheats` OSD page.

## OSD options (page `P4`)

| Option | Choices | Default | Effect |
|---|---|---|---|
| `On-Screen Timer` | Off / On | Off | Draws an MM:SS overlay in the bottom-right of the active picture (kept inside the 4:3-safe region so CRT players see it too). |
| `Timed Cheats` | Off / On | On | Master switch for gating. When **Off**, all cheats behave exactly like stock SNES_MiSTer (only the normal `C,Cheats > Cheats Enabled` switch matters). |
| `Timed Delay` | 5 Sec · 10 Sec · 30 Sec · 1 Min · 5 Min · 10 Min · 15 Min · 20 Min | 5 Min | How much time must elapse before the "timed" tier of cheats activates. |
| `Immediate Cheats` | First 1 / First 2 | First 1 | How many cheats at the **top of your cheat file** stay active from the start (always on). |
| `Cycle Timed Cheats` | Off / On | On | When **On**, after the delay elapses the timed tier keeps flipping **On for `delay` then Off for `delay`**, repeating, instead of unlocking once and staying on forever. |

### How the gate works

Each loaded cheat is assigned a slot by the order it appears in your `.cht`/cheat
file (slot 0 = first entry, slot 1 = second, …). A cheat only ever applies when
**both** of these are true:

```
normal "Cheats Enabled" is Yes        (the stock C,Cheats switch)
AND the cheat's slot is "allowed"     (see below)
```

A slot is *allowed* when any of these holds:

- `Timed Cheats` is **Off** (everything unlocks, stock behaviour), or
- the slot is within your `Immediate Cheats` front group (first 1 or 2 entries),
  or
- the timed tier has activated (delay elapsed, and in Cycle mode also currently
  **On**).

So with `Immediate Cheats = First 1` and `Delay = 10 Sec`, if your file lists
`[swim in any level]` first and `[mario recolor]` second, you'd swim constantly
while the recolor blinks in for 10 seconds on, 10 seconds off, starting 10 seconds
after you close the OSD — assuming Cycle is On.

### Ordering matters

"Immediate" and "timed" are purely positional — control which cheats act as the
always-on group by **ordering the entries in your cheat file**. Put your
always-on/entry cheats firstley, your timed/burst ones after.

## Full-cycle example

1. Load a game with a `.cht` of, say, four cheats ordered:
   - `#1 invincibility`
   - `#2 swim in any level`
   - `#3 mario recolor`
   - `#4 hard mode`
2. OSD page `P4,Timed Cheats`: set `Timed Cheats=On`, `Timed Delay=1 Min`,
   `Immediate Cheats=First 1`, `Cycle Timed Cheats=Off`, `On-Screen Timer=On`.
3. Close the OSD → timer starts.
4. `0:00` — `invincibility` (#1) is active immediately.
5. `1:00` — `swim` (#2), `recolor` (#3) and `hard mode` (#4) all activate and stay on.

With `Cycle Timed Cheats=On` and a `Timed Delay` of `5 Sec`, the timed trio instead
flicks on for 5 s, off for 5 s, repeating — while `invincibility` stays on the whole time.

## Notes / scope

- This is a **two-tier** system (immediate front group + one timed tier), not yet
  per-cheat staggered time lines ("cheat #2 at 5:00, #3 at 10:00"). That richer
  variant is a natural future extension but needs more OSD status-bit budget than
  the core has spare.
- True in-game "trigger" cheats (e.g. "every 5th koopa stomp starts a 5 s timer")
  are out of scope for this version — the featured roadmap idea, not yet built.
- The on-screen timer counts *elapsed play time*, not wall clock; it is independent
  of the RTC and any RTC battery state.
