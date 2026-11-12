extends SceneTree
## Run once from the command line to (re)build the TileSet resource:
##   godot --headless --path . -s res://tools/build_tileset.gd
## Tile (0,0) = ground, (1,0) = ground with grass top  -> physics layer 0 = collision layer 1 "World"
## Tile (2,0) = one-way platform                       -> physics layer 1 = collision layer 7 "Platforms"
## Tile (3,0) = one-way LEDGE (between stacked rooms)    -> physics layer 2 = collision layer 8 "Ledges"
##              The ground slam does NOT go through ledges, drop-through (down + jump) does.

func _init() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1) # Layer 1 = World
	ts.set_physics_layer_collision_mask(0, 0)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(1, 64) # Layer 7 = Platforms
	ts.set_physics_layer_collision_mask(1, 0)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(2, 128) # Layer 8 = Ledges
	ts.set_physics_layer_collision_mask(2, 0)

	var src := TileSetAtlasSource.new()
	src.texture = load("res://assets/tiles/tiles.png")
	src.texture_region_size = Vector2i(16, 16)
	ts.add_source(src, 0)

	var full := PackedVector2Array([Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8)])
	var thin := PackedVector2Array([Vector2(-8, -8), Vector2(8, -8), Vector2(8, -2), Vector2(-8, -2)])
	for x in 4:
		var coords := Vector2i(x, 0)
		src.create_tile(coords)
		var data := src.get_tile_data(coords, 0)
		if x >= 2:
			var layer := 1 if x == 2 else 2
			data.add_collision_polygon(layer)
			data.set_collision_polygon_points(layer, 0, thin)
			data.set_collision_polygon_one_way(layer, 0, true)
		else:
			data.add_collision_polygon(0)
			data.set_collision_polygon_points(0, 0, full)

	var err := ResourceSaver.save(ts, "res://assets/tiles/tileset.tres")
	print("TileSet saved: ", error_string(err))
	quit()
