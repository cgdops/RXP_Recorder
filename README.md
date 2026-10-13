# RXP Live Flight Recorder

An in-game scratchpad recorder for speedrunners and leveling guide authors. As you play through your routes, **RXP Live Flight Recorder** automatically tracks your actions and formats them into syntax directly compatible with **RestedXP Guides (RXPGuides)**.

---

## ✨ Features

- **Automatic Quest Event Detection**:
  - Quest Accepts (`.accept <id> >>Accept <title>`)
  - Objective Completions (`.complete <id>,<index> --<text>`)
  - Quest Turn-ins (`.turnin <id> >>Turn in <title>`)
- **Location & Target Tracking**:
  - Automatically captures normalized `.goto <zone>,<x>,<y>` coordinates at the exact moment of interaction.
  - Automatically targets NPCs with `.target <NPC Name>`.
- **Trainer & Flight Master Support**:
  - Logs `.trainer >>Train spells` when interacting with class trainers.
  - Logs `>>Take flight path` upon opening flight master maps.
- **Manual Route Markers**:
  - Inject custom waypoints, notes, or tips anywhere on the fly with `/rc wp [note]`.
- **Built-in Copy/Export Window**:
  - Open a clean in-game popup window anytime using `/rc` to select and copy all recorded steps directly into your guide files (`Ctrl+A`, `Ctrl+C`).
- **Zero Hard Dependencies**:
  - Operates standalone without requiring RXPGuides loaded.

---

## ⌨️ Slash Commands

Use `/rc`, `/rxprecord`, or `/rxpr`:

| Command | Description |
| :--- | :--- |
| `/rc` or `/rc show` | Open the export dialog containing formatted RXP steps. |
| `/rc wp [note]` | Drop a manual waypoint step at your player position with an optional note. |
| `/rc start` (or `/rc on`) | Resume event recording. |
| `/rc stop` (or `/rc pause`) | Pause event recording. |
| `/rc clear` | Clear the recorded step buffer. |

---

## 🚀 How to Use

1. Enable **RXP Live Recorder** on your character selection screen.
2. Play through your intended leveling route. Accepts, turns-ins, objectives, and visits will record in the background.
3. Whenever you want to create a travel checkpoint, type:
   ```text
   /rc wp Run south along the road to the crossroads
   ```
4. Open the export window with `/rc`.
5. Press `Ctrl+A` $\rightarrow$ `Ctrl+C` to copy the generated text, then paste it directly into your `.lua` guide file inside an `RXPGuides.RegisterGuide(...)` block.

---

## 📄 License

This project is licensed under the [MIT License](LICENSE.txt).
