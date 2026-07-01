# NPCTrail.gd
# Color-coded particle trail that follows an NPC and visualizes its path.
#
# Implements the four-step particle lifecycle from the lecture:
#
#   Step 1 — PRODUCE / INJECT
#     A new particle is emitted at the NPC's current world position
#     every EMIT_INTERVAL seconds.
#
#   Step 2 — ATTRIBUTES
#     Each newly created particle receives:
#       • pos       : current world position of the NPC (spawn location)
#       • vel       : small random lateral drift velocity
#       • ttl       : time-to-live counter (starts at PARTICLE_TTL)
#       • max_ttl   : stored once for the alpha fade ratio
#
#   Step 3 — TRANSPORT / MODIFICATION
#     Every frame each particle's position is updated by its velocity,
#     and its ttl is decremented by delta.
#     Alpha is derived from ttl / max_ttl so particles fade out over time.
#     The radius also shrinks proportionally for a dissolve effect.
#
#   Step 4 — VANISH
#     Particles whose ttl has reached 0 are removed from the array.
#     The _draw() call is skipped for vanished entries automatically.
#
# Add this node as a sibling of the NPC inside NPCContainer so its
# coordinate space matches world space (position stays at Vector2.ZERO).

class_name NPCTrail
extends Node2D

# Seconds between particle emissions (lower = denser trail)
const EMIT_INTERVAL:   float = 0.06

# How long each particle lives before vanishing
const PARTICLE_TTL:    float = 1.1

# Maximum radius of a freshly spawned particle (px)
const PARTICLE_RADIUS: float = 5.5

# Random lateral drift speed (px/s) — keeps the trail from looking like a line
const DRIFT_SPEED:     float = 12.0

var _npc:        Node2D = null   # reference to the owning NPC
var _color:      Color  = Color.WHITE
var _particles:  Array  = []     # Array of Dictionaries (one per live particle)
var _emit_timer: float  = 0.0


# ---- Public API -----------------------------------------------------------

# Call once right after adding this node to the tree.
# npc   : the NPC node whose position is sampled every frame
# color : trail color (should match the NPC's body color)
func setup(npc: Node2D, color: Color) -> void:
	_npc   = npc
	_color = color


# ---- Godot callbacks ------------------------------------------------------

func _process(delta: float) -> void:
	if _npc == null or not is_instance_valid(_npc):
		return

	# ── Step 1 + 2: PRODUCE and assign ATTRIBUTES ─────────────────────────
	_emit_timer += delta
	if _emit_timer >= EMIT_INTERVAL:
		_emit_timer = 0.0
		_inject_particle()

	# ── Step 3: TRANSPORT / MODIFICATION ──────────────────────────────────
	for p in _particles:
		p["ttl"] -= delta
		p["pos"] += p["vel"] * delta
		# Alpha fades linearly from 1.0 to 0.0 over the particle's lifetime

	# ── Step 4: VANISH — remove all expired particles ─────────────────────
	_particles = _particles.filter(func(p): return p["ttl"] > 0.0)

	queue_redraw()


func _draw() -> void:
	# Draw each surviving particle; opacity and size reflect remaining TTL
	for p in _particles:
		var life_ratio: float = p["ttl"] / PARTICLE_TTL        # 1.0 → 0.0
		var radius:     float = PARTICLE_RADIUS * life_ratio    # shrinks with age
		var alpha:      float = life_ratio * 0.80               # fades with age

		var c := Color(_color.r, _color.g, _color.b, alpha)

		# to_local converts the stored world position into this node's local space
		draw_circle(to_local(p["pos"]), radius, c)


# ---- Private --------------------------------------------------------------

# Step 1: inject one particle at the NPC's current location.
# Step 2: assign its initial attributes.
func _inject_particle() -> void:
	# Random drift direction so the trail has a soft, organic spread
	var drift := Vector2(
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0)
	).normalized() * DRIFT_SPEED

	_particles.append({
		"pos":     _npc.global_position,   # world-space spawn point
		"vel":     drift,                  # lateral drift velocity
		"ttl":     PARTICLE_TTL,           # remaining lifetime
	})
