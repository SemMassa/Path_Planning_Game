class_name CollisionSystem
extends RefCounted
## Hand written broad phase and narrow phase collision test between the NPC's
## circle and an Obstacle's box. Godot's physics engine is not used for this
## at all, on purpose: the assignment asks for the detection phases
## themselves, not an engine call.
##
## Adapted from npc-test's aabb_vs_aabb()/narrow_phase() approach, but with a
## real circle test in the narrow phase. npc-test approximates every shape,
## circles included, as a plain bounding square, which does not actually
## satisfy an AABB-Circle requirement. This version keeps the circle a circle.

## Broad phase: cheap axis aligned bounding box overlap test, the same check
## as npc-test's aabb_vs_aabb(). Filters out pairs that are nowhere near each
## other before paying for the exact circle test below.
static func aabb_overlap(box_a: Rect2, box_b: Rect2) -> bool:
	return (box_a.position.x < box_b.end.x and box_a.end.x > box_b.position.x) \
		and (box_a.position.y < box_b.end.y and box_a.end.y > box_b.position.y)

## Narrow phase: exact circle vs rectangle test. Clamps the circle's center
## onto box to find the closest point on it, then checks that point against
## radius, the standard AABB-Circle intersection test.
static func circle_intersects_box(center: Vector2, radius: float, box: Rect2) -> bool:
	var closest_point: Vector2 = Vector2(
		clampf(center.x, box.position.x, box.end.x),
		clampf(center.y, box.position.y, box.end.y)
	)
	return center.distance_squared_to(closest_point) <= radius * radius

## Full two phase check: broad phase first using the circle's own bounding
## box, narrow phase only runs if that passes.
static func circle_vs_box_collides(center: Vector2, radius: float, box: Rect2) -> bool:
	var circle_bounds := Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
	if not aabb_overlap(circle_bounds, box):
		return false
	return circle_intersects_box(center, radius, box)

## Minimum translation vector resolution: moves center just clear of box.
## Two cases, because clamping center onto box only finds a useful nearest
## point when center is outside it, if center is inside, clamping just
## returns center itself, with zero distance and no direction to escape in.
static func push_circle_out_of_box(center: Vector2, radius: float, box: Rect2) -> Vector2:
	var closest_point: Vector2 = Vector2(
		clampf(center.x, box.position.x, box.end.x),
		clampf(center.y, box.position.y, box.end.y)
	)

	if closest_point != center:
		# Center is outside box: push straight away from the nearest point
		# on its edge, by however far the circle still reaches past it.
		var escape_direction: Vector2 = (center - closest_point).normalized()
		var penetration_depth: float = radius - center.distance_to(closest_point)
		return center + escape_direction * (penetration_depth + 0.5)

	# Center is inside box: there is no single nearest edge point to aim
	# at, push out through whichever of the four edges is closest instead.
	var distance_to_left: float = center.x - box.position.x
	var distance_to_right: float = box.end.x - center.x
	var distance_to_top: float = center.y - box.position.y
	var distance_to_bottom: float = box.end.y - center.y
	var shallowest: float = min(
		distance_to_left, distance_to_right, distance_to_top, distance_to_bottom
	)

	if shallowest == distance_to_left:
		return Vector2(box.position.x - radius - 0.5, center.y)
	if shallowest == distance_to_right:
		return Vector2(box.end.x + radius + 0.5, center.y)
	if shallowest == distance_to_top:
		return Vector2(center.x, box.position.y - radius - 0.5)
	return Vector2(center.x, box.end.y + radius + 0.5)
