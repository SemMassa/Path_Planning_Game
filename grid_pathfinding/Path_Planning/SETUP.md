# Godot Scene Setup

Alle Skripte liegen in `scripts/`. Hier steht, welche Szenen du in Godot anlegen musst.

---

## 1. Projektstruktur anlegen

```
res://
├── scenes/
│   ├── Main.tscn
│   ├── NPC.tscn
│   └── MovingObstacle.tscn
└── scripts/
    ├── MazeGenerator.gd
    ├── GridManager.gd
    ├── NPC.gd
    ├── MovingObstacle.gd
    └── Main.gd
```

---

## 2. NPC.tscn

1. Neue Szene erstellen → Root-Node: **CharacterBody2D**
2. Script anhängen: `scripts/NPC.gd`
3. Child hinzufügen: **CollisionShape2D**
   - Shape: `RectangleShape2D`, Size: `24 x 24`
4. Als `res://scenes/NPC.tscn` speichern

> Die visuelle Darstellung (blauer Kreis) zeichnet das Script selbst via `_draw()`.

---

## 3. MovingObstacle.tscn

1. Neue Szene erstellen → Root-Node: **Node2D**
2. Script anhängen: `scripts/MovingObstacle.gd`
3. Als `res://scenes/MovingObstacle.tscn` speichern

> Das rote Rechteck wird ebenfalls via `_draw()` gezeichnet.
> Kein CollisionShape nötig — die Kollision läuft über den A*-Graph.

---

## 4. Main.tscn

1. Neue Szene erstellen → Root-Node: **Node2D**
2. Script anhängen: `scripts/Main.gd`
3. Folgende Child-Nodes hinzufügen (exakte Namen beachten):

| Name               | Node-Typ | Script            |
|--------------------|----------|-------------------|
| `GridManager`      | Node2D   | `GridManager.gd`  |
| `NPCContainer`     | Node2D   | —                 |
| `ObstacleContainer`| Node2D   | —                 |

4. Als `res://scenes/Main.tscn` speichern und als **Hauptszene** setzen

---

## 5. Kamera (optional aber empfohlen)

Das Grid hat bei 25x25 Zellen und 32px/Zelle eine Größe von 800x800px.

- Child-Node **Camera2D** zu `Main` hinzufügen
- `Position`: `(400, 400)` um das Grid zu zentrieren

---

## Parameter anpassen

Alle Tuning-Werte stehen oben in den jeweiligen Skripten als Konstanten:

| Datei               | Konstante                | Bedeutung                          |
|---------------------|--------------------------|------------------------------------|
| `Main.gd`           | `GRID_WIDTH/HEIGHT`      | Größe des Labyrinths (ungerade!)   |
| `Main.gd`           | `NPC_COUNT`              | Anzahl der NPCs                    |
| `Main.gd`           | `MOVING_OBSTACLE_COUNT`  | Anzahl beweglicher Hindernisse     |
| `GridManager.gd`    | `CELL_SIZE`              | Pixelgröße einer Zelle             |
| `NPC.gd`            | `MOVE_SPEED`             | NPC-Geschwindigkeit (px/s)         |
| `NPC.gd`            | `PATH_RECALC_INTERVAL`   | Wie oft der Pfad neu berechnet wird|
| `MovingObstacle.gd` | `MOVE_SPEED`             | Hindernis-Geschwindigkeit (px/s)   |

---

## Architektur-Übersicht

```
MazeGenerator          GridManager           NPC / MovingObstacle
─────────────          ───────────           ────────────────────
generate(w, h)   →     setup(maze_data)
                        ├── _init_astar()
                        └── _draw()          ←── nutzt get_path()
                                             ←── nutzt set_point_solid()
```

- **MazeGenerator** erzeugt einmalig das Labyrinth-Array
- **GridManager** verwaltet Zustand und A*-Graph dauerhaft
- **NPC** fragt Pfade ab und folgt ihnen
- **MovingObstacle** aktualisiert den A*-Graph live beim Bewegen
