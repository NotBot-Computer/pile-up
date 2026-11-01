# Pile Up

A local party game about stacking bricks on a tower that would rather fall over. Styled after retro pixel art, inspired by *Tricky Towers*.

Built in **Godot 4**. It started life as one of the two modes of *Traffic Tower*; the other mode, the split-screen racer **Don't Crash**, now lives in its own repository (github.com/NotBot-Computer/dont-crash).

## How it plays

One shared tower. Players take turns steering bricks down onto a single narrow platform, under real physics. When everything stops moving, anything that fell off costs the player who dropped it a life — one of the hearts on their card blinks and is gone. Three lives each; last builder standing wins. That's **free-for-all**, one of seven ways to play it — see [Pile Up's variants](#pile-ups-variants). Pile Up is always played as a **cup**: a run of rounds in a different variant each time, first to 15 trophies (see [Cups](#cups)).

## Playing it

Launch the game and you'll get: pick the solo cup or the team cup → pick how many players → each player cycles and locks in a color → the cup's trophy count, which starts the first round.

Your colour marks whichever brick is currently in the air — every brick already on the pile looks the same, whoever put it there — and the three hearts on your HUD card.

There is no computer player yet; every seat is a person.

## Controls
| Player | Left | Right | Down | Dash | Rotate ccw / cw | Skills: self / opponent |
| ------ | ---- | ----- | ---- | ---- | --------------- | ----------------------- |
| P1     | A    | D     | S    | W    | Q / E           | Z / X                   |
| P2     | ←    | →     | ↓    | ↑    | , / .           | N / M                   |
| P3     | F    | H     | G    | T    | R / Y           | V / B                   |
| P4     | J    | L     | K    | I    | U / O           | ; / '                   |

Your brick starts falling the moment it appears — there is no drop button, just a few seconds to place it. It comes in quickly through the open sky and slows to its normal pace once it is a few blocks above the tower, which is where the aiming happens.

- **Left / right** move it **exactly half a block**. Hold to repeat.
- **Dash** (W / ↑ / T / I) dashes **exactly one whole block** in the direction you're holding (or the last one you pressed) — same distance as two taps, but covered in one fast sweep with a trail behind it, so you can see it land.
- **Rotate keys** turn it a quarter turn at a time.
- **Down** makes it fall faster, once you like the line.

You can walk a brick up to two blocks past the platform edge if you want to — that is the whole risk/reward of the mode, and yes, you can walk one clean off the side and lose it.

### Pile Up's variants

None of these is picked on its own: each is a round of one of the two [cups](#cups) — the solo cup plays Free for all, Race, Co-op and Frame, the team cup Teams, Team Race, Co-Pilot and Team Frame. Teams are seats, not a choice: **P1 + P3 are the left team** (both on the left half of the keyboard) and **P2 + P4 the right**, so nobody reaches across a rival and the turn order alternates sides on its own. A team shares one row of lives, shown once on its header above its members' cards.

| Variant | Players | How it plays |
|---|---|---|
| **FREE FOR ALL** | 2-4 | The original: three lives each, last builder standing. |
| **RACE** | 2-4 | Every player gets their own tower, side by side, and everyone builds **at the same time** with the same bricks in the same order. First to settle a tower over the **line 15 blocks up** wins; run out of your **5 lives** and you drop out while the rest race on. A hex you cast lands on **whoever is highest** (ties go to the next seat). With three or four towers each one is narrow, so its HUD becomes one strip across the top. |
| **TEAMS** | 3-4 | One tower, two teams, **6 lives per team**. Turns alternate left, right, left, right, and each side's members take its turns in rotation (with three players, P2 holds the right alone and goes every other turn). A drop costs your *team* a life. You can cast your **self** skill on your teammate's turn to help them — it lands on their brick — but only the player flying can send a hex, and it always goes to the next rival up. |
| **CO-PILOT** | 4 | Two crews of two, **one brick per crew**: one of you steers it (left/right, dash, fall faster) and the other turns it (rotate keys) — your own keys for your own half, nothing else works. You swap halves every brick, and the cards say who has which (STEER / TURN). Either of you can cast; a clean drop charges you both. |
| **CO-OP: THE STORM** | 1-4 | Everyone on one crew, **5 lives**, building to the **GOAL line 14 blocks up**. Every 3 turns the storm sends a random hex at whoever is up next (every 2 once you're past halfway). Only self skills drop in co-op — there's no one to hex. Settle the tower over the line to win. In the solo cup the round is placed by **fewest bricks dropped**; an equal count is an equal place. |
| **TEAM RACE** | 2-4 | A tower each, side by side, building **at the same time**. Same bricks, same order, both sides. First team to settle its tower over the **line 15 blocks up** wins; run out of your **5 lives** first and you lose. A hex you cast lands on the *other* tower's next brick. A bar along the bottom of each tower shows its progress to the line. |
| **FRAME** | 2-4 | A tower each, side by side, and on every platform **the same outline** — a frame to fill. Everyone gets **the same 10 bricks in the same order**, and the frame is built out of exactly those bricks, so it can always be filled perfectly (in the order they come, on the half-block steps the keys move in). Bricks you lay inside the frame count for you and anything **sticking out of it counts against you**; a brick that falls off just leaves its part of the frame empty. When everyone has placed their 10, the **best fit** wins (a bar under each tower shows the fit as it goes). No lives and no skills in this one. Sometimes a frame has a small window in it — that's a gap the bricks leave when stacked in that order, and it isn't part of the frame. |
| **TEAM FRAME** | 2-4 | The same, a frame per team: P1 + P3 build the left one and P2 + P4 the right, taking turns. Best fit wins. |

### Cups

A cup is several rounds of Pile Up, **a different variant every round**, scored by where you finish: **3 trophies for 1st, 2 for 2nd, 1 for 3rd, none for 4th** — in the team cup, **3 for the winning team and none for the losers**. First to **15 trophies** wins the cup. They are the only two choices on the screen after **PILE UP**:

| Cup | Players | Rounds, in turn |
|---|---|---|
| **SOLO CUP** | 2-4 | Free for all → Race → Co-op: The Storm → Frame → Free for all → … |
| **TEAM CUP** | 3-4 | Teams → Team Race → Co-Pilot → Team Frame → … (Co-Pilot only with four) — the trophies go to the team: 3 for a round won, 0 for a round lost, so it's first to five wins |

Between rounds a **trophy count** shows every player's (or team's) row, marked by their own car on the left. Each trophy is a car **in the colour of whoever won that round**: if blue wins, the winner gets three blue cars, 2nd two blue cars and 3rd one; if purple wins the next round, that round's trophies are all purple. So each row is a coloured history of the cup — whose rounds you scored in — with dark empty spaces up to a finish flag at 15. A winning team's trophies alternate its two members' colours. It names the mode coming next; **Enter** starts it (the first Enter skips the count-up). A round's result screen moves on to the count by itself after a few seconds, or straight away on Enter. How a round is ranked: on one tower, whoever is left standing is 1st and the rest in reverse order of going out; in a race, whoever crosses the line is 1st, then anyone still building by height, then whoever dropped out, last one out highest; in co-op, whoever dropped the fewest bricks is 1st, and players who dropped the same number share a place and its trophies (1st, 1st, 3rd); in a frame round, best fit first, and an equal fit (to the percent) is a shared place too. If two players pass 15 in the same round, the higher total wins, and a tie goes to whoever placed better in that round. **Esc** leaves the cup.

Skills are earned by building. Every **clean placement** — your brick landed and nothing fell — fills one segment of the charge bar along the top of your card; two of them hand you a random skill into whichever of your two slots is empty. The green slot is a **self** skill and the red one is a **hex**, each on its own key (shown under the slot), and both can only be cast **while your own brick is in the air**. A self skill goes off on the spot. A hex waits for its target's next turn and lands the moment their brick appears — the tower is shared and a turn's falls are charged to whoever is on the clock, so a hex that hit during *your* turn would only ever hurt you. Hexes in flight are listed under the turn banner, so the player about to receive one sees it coming.

The nine skills, by pack (`scripts/tower_skills/packs/`):

| | Skill | Kind | What it does |
|---|---|---|---|
| A | **CEMENT** | self | Your brick sets to whatever it touches. Hang it off the edge — it stays. |
| A | **TREMOR** | hex | The ground shakes on their turn — hardest the instant their brick lands. Whatever is wobbly finds out. |
| A | **PETRIFY** | self | The tower is stone until your turn ends. Whatever it was going to drop, it drops on the next player's clock. |
| B | **PLUMB LINE** | self | Your brick falls at half speed with a line to exactly where it will land — any corner over thin air shows red. |
| B | **CROSSWIND** | hex | A wind gusts across their next turn, shoving the brick a whole block sideways every gust — and it may turn on them. |
| B | **NIGHTFALL** | hex | Night falls on their next **two** turns: the tower and their own falling brick both vanish, and the only look they get is when lightning strikes — a third of a second of daylight every couple of seconds. The lights come back up the moment the brick lands, and for good once the two turns are over. |
| C | **TAILOR** | self | Your NEXT brick is cut to fit the top of the tower — whichever shape fills the gaps best, instead of the one on the card — with a ghost showing where it goes. |
| C | **KEYSTONE** | hex | A brick is pulled out from under the top of the tower on their turn — whatever comes down is on them. |
| C | **RUBBLE** | hex | A stray brick drops onto the tower at the start of their turn, a beat ahead of their own. It costs nothing if it bounces off — whatever it knocks off is on them, and whatever it leaves is theirs to build on. |

A self skill and a hex are drawn with equal odds into whichever slot is empty; within a category every skill is equally likely.

The bag holds nineteen shapes in two categories: the seven classic tetrominoes, and all twelve pentominoes. They are not equally likely — a classic turns up about 13% of the time and a five-cell piece under 1%, so roughly **nine bricks in ten are the shapes you already know** and an odd one is a rare surprise. `TowerMode.CLASSIC_BIAS` is the single number that sets that split.

Coming up against the side of a taller part of the tower doesn't end your turn. You keep steering for as long as you like and can always back out of it — a turn ends when something is actually *underneath* the brick, and at no other time.

The moment the brick touches down it stops being yours and becomes ordinary physics: it tips, slides and settles, and so does everything under it. The turn does not end when it lands, it ends when the *whole tower* has stopped moving — so a brick that settles innocently and then shoves the pile over five seconds later still counts against you.

## Running it

Open the project folder in the Godot 4 editor (`godot --path .` from this directory, or `Import` from the project manager), then press **F5** / the Play button.

## Backdrop and ground

Pile Up plays in front of `sprites/bg/tower_backdrop.png`, in two layers cut from that one image.

The **backdrop** is drawn in screen space on its own layer and scrolled at a fraction of the camera. Screen-space rather than part of the world on purpose: the camera pans up without limit as the tower grows, so world-space art would be left behind within a few bricks. Above the picture's own top edge the sky simply continues in the image's own sky colour, so a tall tower climbs into open sky instead of into a hard edge.

The **near ground** is the grass shelf from the bottom of the same image, drawn in world space at the foot of the tower and *in front of* the bricks — so a brick knocked off the tower slides down behind the grass and is gone. It tracks the camera exactly, because it is where the tower actually stands. The two layers are aligned at the start of a match and separate as the tower climbs, near ground falling away faster than far.

The tower itself stands on a rock outcrop whose body is cut from the same picture's earth band, so it is literally made of the stone the rest of the world is made of rather than painted to look like it.

## Menu art

The menus — the title screen with its two cups, the player count, the colour pick and the cup's trophy count — are pixel art built from the game's own bricks. The title screen and the player count are rows of big cards, picked with the **left/right arrow keys**, chosen with **Enter** and left with **Esc** (the mouse does nothing there). Each card is just a preview and a name; the selected one plays its preview and the rest hold still, dimmed: one tower for the solo cup and two for the team cup, and on the player count that many strips with a brick falling in each. The title is spelled in bricks: each letter is one brick-shaped piece, outlined and bevelled the way the bricks are, in the seven classic bricks' colours, and the letters drop in when the screen opens. Behind every menu but the trophy count the bricks rain down and pile up along the bottom; a full pile sinks away and a new one starts. Buttons and panels are chunky framed boxes with notched corners, and the keyboard's current button is lit in the O brick's yellow. Nothing here is new art: shapes come from `GameSettings.BRICKS` and colours are read off the brick sprites themselves (`scripts/PixelUI.gd`).

The font is **Press Start 2P** by CodeMan38 (`fonts/PressStart2P-Regular.ttf`), under the **SIL Open Font License 1.1** — the licence is committed beside it as `fonts/PressStart2P-OFL.txt`. It is imported with antialiasing, hinting and subpixel positioning off, and sized in multiples of 8 so its pixels stay square. Only the menus use it; the in-round HUDs still use Godot's default font.

## Brick art

Pile Up's nineteen bricks (`sprites/blocks/piece_*.png`) are the seven tetrominoes and all twelve pentominoes, flat saturated fills inside a heavy black outline, cut from six supplied sheets (`tat1.png` - `tat6.png`) by `scripts/dev/extract_blocks.py`. That script removes each sheet's white background by flood-filling in from the border rather than by threshold — the hole in the U pentomino is background by colour and must survive — and normalises every piece to an exact grid of square cells, since a cell is 142px on one sheet and 268px on another and is drawn up to 14% wider than it is tall within a single piece. `GameSettings.BRICKS` can then give each piece its collision as plain cell-unit rectangles, generated by the same script so the two cannot drift apart. Unlike the car-part sheet this replaced, the art has no up: a flat coloured polyomino can be dropped in whatever orientation it was drawn, so the shape table follows the sheets instead of the sheets being re-laid to fit the table.

## Player art

Each player's colour is shown as a car (`sprites/cars/sedan_*.png`, six colours) on the colour pick, and the cup's trophies are drawn as the car of whoever won the round — the last of the art from the racing game this one was split from.

## Project structure

```
project.godot
sprites/
  cars/               the six player cars (colour swatches and trophies)
  blocks/             Pile Up's nineteen bricks — 7 tetrominoes, 12 pentominoes
  bg/                 Pile Up's parallax backdrop
  ui/                 countdown glyphs, and the life heart
  skills/             Pile Up skill icons (placeholders, from scripts/dev/make_tower_skill_icons.py)
fonts/                Press Start 2P (the menus' pixel font) and its SIL OFL 1.1 licence
scenes/
  MainMenu.tscn       title screen: the solo cup or the team cup
  PlayerSelect.tscn    choose how many players (only the counts the cup allows)
  SkinSelect.tscn      each player picks + locks in a colour
  TowerMode.tscn       Pile Up: the shared tower, its platform and its HUD
  TowerRace.tscn       Pile Up's races: a TowerMode per team (or per player) side by side in SubViewports
  TowerCup.tscn        a cup's trophy count, between its rounds
  TowerPiece.tscn      one car-tetromino brick (a real RigidBody2D)
scripts/
  GameSettings.gd      autoload: player count, chosen skins, sprite tables, key bindings
  MainMenu.gd          the title screen and cup picker, built from GameSettings.TOWER_CUPS
  PlayerSelect.gd
  PixelUI.gd           the menus' pixel look: font, framed buttons and panels, bricks redrawn as pixel art
  BrickRain.gd         bricks raining and piling up behind a menu
  BrickTitle.gd        a title spelled in brick-shaped letters that drop in
  ModeCard.gd          one menu card with its live preview
  CardRow.gd           a row of cards picked with the arrow keys, Enter and Esc
  SkinSelect.gd        dynamic per-player sprite-pick panels, duplicate-skin avoidance
  HeartPips.gd          the life pip, and its per-player recolour
  TowerMode.gd          Pile Up: turn order, drop/settle/resolve loop, lives, camera
                        — and the variants: teams, crews, goal lines, the storm
  TowerRace.gd          hosts a race's towers, relays hexes (to the leader), owns its result screen
  TowerCup.gd           the cup's trophy count: each player's cars by the round, and the next round's mode
  TowerPiece.gd         one brick: collision from cell rects, physics material, fall cap
  TowerMode.gd          (see above) also owns the shape-query movement model
  TowerHUD.gd           Pile Up's side-column panels — lives, next brick, controls
  TowerFrame.gd         FRAME: builds a frame out of the deal's bricks, and marks a tower against it
  TowerBackground.gd    Pile Up's parallax backdrop
  TowerGround.gd        Pile Up's near ground — a foreground layer bricks fall behind
  tower_skills/         Pile Up's skills — the contract, the catalogue (three packs) and one file per skill
  dev/                  headless measurement harnesses, not part of the game
```

## Roadmap

- An AI that can play Pile Up, so a round can be handed to a bot and watched
- Gamepad support
- Export to web (HTML5) and/or desktop builds
