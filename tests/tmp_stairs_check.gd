extends SceneTree
## Throwaway check for levelled flats. Deleted once it has been read.

var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true

	var terrain := TerrainAuthor.new()
	terrain.name = "Terrain"
	var collision := CollisionPolygon2D.new()
	collision.name = "Collision"
	terrain.add_child(collision)
	var fill := Polygon2D.new()
	fill.name = "Fill"
	terrain.add_child(fill)
	var surface := Line2D.new()
	surface.name = "Surface"
	terrain.add_child(surface)
	terrain.flat_start_segments = 2
	terrain.flat_end_segments = 2
	terrain.shape_text = """
flat 192
flat 192 -96
flat 192 -192
flat 192 -288
up 384 20
flat 192 0
"""
	root.add_child(terrain)

	print("readout: ", terrain.readout)
	print("shapes:  ", terrain.shape_list())
	print("warnings: ", terrain._get_configuration_warnings())
	var heights := PackedFloat32Array()
	for i in terrain._profile_segments() + 1:
		heights.append(terrain._profile_height(i))
	print("heights: ", heights)
	print("finish_x: ", terrain.finish_x(), "  end_x: ", terrain.end_x())

	# The plain-flat regression: no levels at all should build exactly as before.
	var plain := TerrainAuthor.new()
	plain.name = "Plain"
	plain.add_child(CollisionPolygon2D.new())
	plain.shape_text = "flat 300\nup 600 16\nflat 200\ndown 900 20\nup 500 24\n"
	root.add_child(plain)
	print("plain readout: ", plain.readout)

	return true
