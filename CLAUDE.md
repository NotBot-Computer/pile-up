# Pile Up — CLAUDE.md

Godot 4.7 local-multiplayer physics tower-stacking party game. **Until 2026-10-21 this repo was Traffic Tower, with two modes**; the racing mode, Don't Crash, was split off into its own repository (`github.com/NotBot-Computer/dont-crash`, checked out at `~/Desktop/dont-crash`) and this one is Pile Up alone (docs/PROJECT_STATE.md §0). See [docs/PROJECT_STATE.md](docs/PROJECT_STATE.md) for the full technical handoff (architecture, decisions, current state, next steps) before making changes — read it first, it's the source of truth for project context.

## Run / validate

Editor (GUI, for playtesting — this project has no automated test suite, manual playtesting is the only way to verify gameplay feel):
```bash
cd /Users/berkantkucukomer/Desktop/traffic-tower && godot .
```

Headless compile check (catches GDScript parse/compile errors only — does NOT verify gameplay behavior or visuals):
```bash
cd /Users/berkantkucukomer/Desktop/traffic-tower && godot --headless --quit
```
Any `SCRIPT ERROR:` or `Failed to load script` in the output means a script is broken. Clean output (just the engine banner line) means all scripts *reachable from the boot scene* compiled — **the bare command only boots `MainMenu.tscn` and quits, so it never loads `TowerMode.tscn`/`TowerRace.tscn`/`TowerCup.tscn` or anything else only reached by playing through the menu flow.** A parse error in one of those scripts can ship silently past this check (this happened once — see docs/PROJECT_STATE.md §8/§12). When changing a script that isn't in the boot scene's own chain, also run the check against the actual scene, e.g.:
```bash
cd /Users/berkantkucukomer/Desktop/traffic-tower && godot --headless --quit res://scenes/TowerMode.tscn
```

**Pile Up has no bot**, so there is nothing to hand a round to — but it does have a headless harness that plays whole matches and checks the physics and the turn loop:
```bash
cd /Users/berkantkucukomer/Desktop/traffic-tower && godot --headless --fixed-fps 240 res://scenes/dev/TowerProbe.tscn -- --spread=0.3
```
`--spread` is how much of the legal aim range a brick may be steered to: `1.0` models nonsense, `0.1`-`0.3` models a player who is trying. Run both — the interesting signal is the *difference* between them, which is what caught the drop-speed bug in docs/PROJECT_STATE.md §5 session S. Note it sets the commanded position directly rather than pressing keys, so it says nothing about the half-cell step, the dash, the hold-repeat or the soft drop, and nothing at all about how the mode feels.

There is also a much smaller harness for Pile Up's lateral input, which asserts that a dash is *distinguishable* from two ordinary taps rather than that it moves any particular distance (the dash once shipped moving the right distance at the wrong speed, and was invisible — see docs/PROJECT_STATE.md §5 session S):
```bash
cd /Users/berkantkucukomer/Desktop/traffic-tower && godot --headless --fixed-fps 60 res://scenes/dev/DashProbe.tscn
```

`DashProbe` calls `_dash()` with a direction already chosen, so it only ever sees what a dash *does*. `DashFeelProbe` presses real keys through `Input.parse_input_event()` and measures the brick's actual per-frame movement: both orders of the dash chord (hold either key, press the other) against each other, across the six phases of one hold-repeat tick, plus each half of the chord pressed alone. That is where two dashes in a row can behave differently for reasons the player has no control over (docs/PROJECT_STATE.md §5 session U):
```bash
cd /Users/berkantkucukomer/Desktop/traffic-tower && godot --headless --fixed-fps 60 res://scenes/dev/DashFeelProbe.tscn
```

And one for Pile Up's landings, which asks whether anything is actually under a brick at the moment the player stops being able to steer it:
```bash
cd /Users/berkantkucukomer/Desktop/traffic-tower && godot --headless --fixed-fps 240 res://scenes/dev/LandingProbe.tscn
```

And one for Pile Up's *descent*, which asks whether a brick ever stops falling part way down and stays stopped. It is the only tower probe that steers the way the keyboard does — through `_press_steer()`, on the exact half-cell lattice — and that is the whole point: the others aim with `randf()`, so they never line a brick's faces up flush with the stack the way a player does every single turn (docs/PROJECT_STATE.md §5 session T):
```bash
cd /Users/berkantkucukomer/Desktop/traffic-tower && godot --headless --fixed-fps 240 res://scenes/dev/StallProbe.tscn
```

And one for Pile Up's *pace*, which splits a turn into the descent, the settle and the pause before the next brick — the three things "the hand-off takes too long" can actually mean (docs/PROJECT_STATE.md §5 session T):
```bash
cd /Users/berkantkucukomer/Desktop/traffic-tower && godot --headless --fixed-fps 240 res://scenes/dev/PaceProbe.tscn
```

And one for Pile Up's **skills** (`scripts/tower_skills/`), the counterpart of `SkillProbe` for the tower: it plays real turns in a three-player match and runs every catalogued skill through three lifecycles — runs its turns out, cut mid-effect by `_clear_skill_effects()`, cut by `_start_match()` — demanding the mode come back identical each time (nothing live or queued, every descent multiplier at 1.0, no control flipped or locked, camera zoom / `Engine.time_scale` / the space's gravity untouched, no node left under the mode, its Foreground or its HUD). It also checks the plumbing: every catalogue row is well-formed, a charge grants after `CHARGE_TO_SKILL` clean drops, and a cast outside the caster's own piloting is refused. Run it after touching anything under `scripts/tower_skills/` or the `# --- Skills` section of `TowerMode.gd`. Like `SkillProbe` it cannot see drawing, so a skill whose visuals are broken passes it:
```bash
cd /Users/berkantkucukomer/Desktop/traffic-tower && godot --headless --fixed-fps 240 res://scenes/dev/TowerSkillProbe.tscn
```

And one for Pile Up's **variants** (`GameSettings.TOWER_*` — teams, co-pilot, co-op, the race; docs/PROJECT_STATE.md §5 session AE). Free-for-all is not in it on purpose: it is "every player is a team of one", the probes above still cover it, and after the variants landed they reproduced their pre-variant output **byte for byte** — keep it that way, and diff them against a saved run after touching the team plumbing in `TowerMode.gd`. `TeamProbe` plays the other four and checks what only they can get wrong: teams alternating and members rotating, the shared pool charged to the team on the clock, support casts landing on the flyer, hexes landing on the next *rival*; co-pilot's key split (through `handle_key()`), role swaps and a skill following the crew across the swap; co-op's goal line and storm cadence (the storm casts as slot -1); and the race's two worlds, simultaneous play, identical brick order, a hex crossing towers, a real key reaching the right tower through the host, and exactly one result per race; and the free-for-all race's tower per player, compact HUD, hexes landing on the leader, and drop-outs that leave the rest racing. `--only=teams|copilot|coop|race|solo` runs one section — and **compare a section only with the same section run the same way**: physics results depend on what ran earlier in the process, so a full run and an `--only` run of one section give different (each reproducible) numbers:
```bash
cd /Users/berkantkucukomer/Desktop/traffic-tower && godot --headless --fixed-fps 240 res://scenes/dev/TeamProbe.tscn
```

And one for Pile Up's **cups** (`GameSettings.tower_cup`, `scripts/TowerCup.gd`; docs/PROJECT_STATE.md §5 session AG). It plays whole cups — the solo cup (free-for-all → race → co-op) at 2, 3 and 4 players and the team cup at 3 and 4 — round after round with blind aim until somebody wins, and checks every round paid out exactly once, to every competitor, in the order the probe *watched* the round happen (the last one eliminated 2nd; in a race, still-building by height, then drop-outs last-out-highest; in co-op, fewest bricks dropped with equal counts sharing a place), that every trophy a round hands out is a car of that round's winner, plus the tally screen's split of each total into before and this round's award. It never changes scene — it cancels a finished round's own timer to the tally — so the scene-to-scene hand-off and the Enter key are not in it:
```bash
cd /Users/berkantkucukomer/Desktop/traffic-tower && godot --headless --fixed-fps 240 res://scenes/dev/CupProbe.tscn
```

And one for Pile Up's **FRAME** rounds (`scripts/TowerFrame.gd`, `GameSettings.tower_is_frame`; docs/PROJECT_STATE.md §5 sessions AL and AM). It checks the frame generator over 400 deals (deterministic, on the platform, holes counted, how long one takes to make), then **builds 100 frames exactly to their own plan under the real physics and requires 100% fit every time** (`-- --perfect=400` for a longer run, ~4 minutes; the grid's own stability rule has been wrong before and only this caught it, docs/PROJECT_STATE.md §5 session AM) — the claim the whole mode rests on, that every frame can be filled with the bricks dealt — then plays whole rounds under `TowerRace` (one tower to plan, the rest blind) and checks nothing is decided until every tower is done and the order is best fit first. `-- --only=frames|perfect|rounds` runs one part. It sets aim directly, so it says nothing about whether a frame is easy to *see* or to line up with the keys:
```bash
cd /Users/berkantkucukomer/Desktop/traffic-tower && godot --headless --fixed-fps 240 res://scenes/dev/FrameProbe.tscn
```

Adding or replacing art means running Godot's importer first — a `preload()` of an unimported PNG is a parse error, so every check above fails misleadingly until this has run:
```bash
cd /Users/berkantkucukomer/Desktop/traffic-tower && godot --headless --import
```

A round opens with a ~2.7s countdown (`scripts/Countdown.gd`), so anything that waits for play to start — a probe, a screenshot, your own patience — waits through it first. The probes already do; they wait on `state == "piloting"` and simply reach it later.

Godot binary lives at `/opt/homebrew/bin/godot` (CLI) — there's also `Godot.app` in `/Applications` for the GUI editor, but the `godot` CLI command works for both editor (`godot .`) and headless (`godot --headless ...`) use.

## Workflow rules

- **Always let the user playtest a change in the editor before running `git commit`.** This is a standing preference — do not commit immediately after an edit just because headless validation passed clean; headless checks only catch compile errors, not whether the fix actually looks/plays right.
- Only commit once the user confirms (e.g. "it's great", "push it"). Then commit and push to `origin/main` (`github.com/NotBot-Computer/pile-up`, formerly `trafucker`) in the same turn unless told otherwise.
- Write commit messages that explain *why*, not just what — this codebase's history is full of physics/illusion bugs where the reasoning matters more than the diff (see docs/PROJECT_STATE.md's "approaches that didn't work" section).
