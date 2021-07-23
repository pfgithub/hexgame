const std = @import("std");
const ray = @import("raylib.zig");

const TileEdges = [4]Tile; // ul ur bl br
const Tile = enum{
  /// eg a tile could be [grass, grass, empty, empty] and it
  /// can be used for any transition involving [grass, grass, *, *]
  /// and it should pick which order to try * in based on this
  /// enum order probably so you don't end up with dirt above a grass
  /// transition
  empty,
  grass,
  dirt,
  dark_dirt,
  stone,
};

const TileMap = struct {
  const TileVariants = std.ArrayListUnmanaged(TileVariant);
  const TileVariant = struct {x: u16, y: u16};
  data: std.AutoHashMap(TileEdges, TileVariants),

  fn init(alloc: *std.mem.Allocator) TileMap {
    return .{
      .data = std.AutoHashMap(TileEdges, TileVariants).init(alloc),
    };
  }
  fn add(map: *TileMap, edges: TileEdges, values: []const TileVariant) void {
    const entry = map.data.getOrPut(edges) catch @panic("oom");
    if(!entry.found_existing) {
      entry.value_ptr.* = std.ArrayListUnmanaged(TileVariant){};
    }
    entry.value_ptr.appendSlice(map.data.allocator, values) catch @panic("oom");
  }
  fn get(map: TileMap, edges: TileEdges) TileVariant {
    // todo support air and variants and stuff
    const found = map.data.get(edges);
    if(found == null or found.?.items.len == 0) {
      return .{.x = 20, .y = 7};
    }
    return found.?.items[0];
  }
};

// width: 24
pub fn addFromData(
  map: *TileMap,
  data: []const u8,
  start: TileMap.TileVariant,
  tiles: []const Tile,
) void {
  var pos = start;
  var lines = std.mem.split(data, "\n");
  while(lines.next()) |line| : ({pos.y += 1; pos.x = start.x;}) {
    var items = std.mem.split(line, ",");
    while(items.next()) |item| : (pos.x += 1) {
      map.add(.{
        tiles[item[0] - '0'],
        tiles[item[1] - '0'],
        tiles[item[2] - '0'],
        tiles[item[3] - '0'],
      }, &.{pos});
    }
  }
}
pub fn add6x6(map: *TileMap, start: TileMap.TileVariant, tiles: [2]Tile) void {
  const data = (
    \\1110,1100,1100,1100,1100,1101
    \\1010,0001,0010,0000,0000,0101
    \\1010,0100,1000,0000,0000,0101
    \\1010,1001,0110,0000,0000,0101
    \\1010,0110,1001,0000,0000,0101
    \\1011,0011,0011,0011,0011,0111
  );
  addFromData(map, data, start, &tiles);
}

pub fn createTileMap(map: *TileMap) void {
  add6x6(map, .{.x = 0, .y = 0}, .{.dirt, .grass});
  add6x6(map, .{.x = 0, .y = 6}, .{.stone, .grass});
  add6x6(map, .{.x = 7, .y = 0}, .{.dark_dirt, .dirt});
  add6x6(map, .{.x = 7, .y = 6}, .{.stone, .dirt});
  add6x6(map, .{.x = 13, .y = 0}, .{.dark_dirt, .grass});
  map.add(.{.grass, .grass, .grass, .grass}, &.{.{.x = 6, .y = 6}});
  // would like to have everything→air in here, it'd be useful
  // also, to make this in-program rather than using
  // a fn like createTileMap, you would basically paint
  // the four corners of every tile with the chosen colors
  // it'd be wayy easier
}

const TileSize = enum{
  nano,
  micro,
  mini,
  pub fn step(_: TileSize, scale: f32) ray.Vector2 {
    return .{
      .x = 16 * scale,
      .y = 16 * scale,
    };
  }
};

const Surface = struct {
  // contains chunks which have
  // a bunch of tiles and any associated tile
  // data if needed
  pub fn getTile(_: Surface, pos: TilePos) Tile {
    if(@mod(pos[0], 5) <= 1 and @mod(pos[1], 7) == 1) {
      return Tile.dark_dirt;
    }
    if(@mod(pos[0], 4) == 0 and @mod(pos[1], 5) <= 2) {
      return Tile.dirt;
    }
    return Tile.grass;
  }
  pub fn getCorners(surface: Surface, pos: TilePos) TileEdges {
    return .{
      surface.getTile(pos),
      surface.getTile(pos + @as(TilePos, .{1, 0})),
      surface.getTile(pos + @as(TilePos, .{0, 1})),
      surface.getTile(pos + @as(TilePos, .{1, 1})),
    };
  }
};

const TilePos = std.meta.Vector(2, i32);
const TilePosFloat = std.meta.Vector(2, f32);
pub fn floatFloorToInt(float: TilePosFloat) TilePos {
  return .{
    @floatToInt(i32, @floor(float[0])),
    @floatToInt(i32, @floor(float[1])),
  };
}
const TileRect = struct {
  x: i32,
  y: i32,
  w: i32,
  h: i32,
};

const Camera = struct {
  pixel_size: f32,
  tile_size: TileSize,
  pixel_offset: ray.Vector2,
  
  pub fn move(camera: *Camera, offset: ray.Vector2) void {
    camera.pixel_offset.x += offset.x;
    camera.pixel_offset.y += offset.y;
  }
  pub fn step(camera: Camera) ray.Vector2 {
    return camera.tile_size.step(camera.pixel_size);
  }
  pub fn visibleTileRange(camera: Camera, dest: ray.Rectangle) TileRect {
    const tile_step = camera.step();
    const x_count = @floatToInt(i32, @ceil(dest.width / tile_step.x));
    const y_count = @floatToInt(i32, @ceil(dest.height / tile_step.y));
    const pos_start = floatFloorToInt(camera.screenToWorld(.{.x = dest.x, .y = dest.y}));
    return .{.x = pos_start[0] - 1, .y = pos_start[1] - 1, .w = x_count + 2, .h = y_count + 2};
  }
  pub fn worldToScreen(camera: Camera, world: TilePosFloat) ray.Vector2 {
    const tile_step = camera.step();
    return .{
      .x = (tile_step.x * world[0]) - camera.pixel_offset.x,
      .y = (tile_step.y * world[1]) - camera.pixel_offset.y,
    };
  }
  pub fn screenToWorld(camera: Camera, screen: ray.Vector2) TilePosFloat {
    const tile_step = camera.step();
    return .{
      (camera.pixel_offset.x + screen.x) / tile_step.x,
      (camera.pixel_offset.y + screen.y) / tile_step.y,
    };
  }
};

pub fn renderSurface(
  texture: ray.Texture2D,
  camera: Camera,
  surface: Surface,
  dest: ray.Rectangle,
  map: TileMap,
) void {
  const tile_step = camera.step();
  const range = camera.visibleTileRange(dest);

  var yi: i32 = range.y;
  while(yi < range.y + range.w) : (yi += 1) {
    var xi: i32 = range.x;
    while(xi < range.x + range.w) : (xi += 1) {
    
      var x = @intToFloat(f32, xi + 1) * tile_step.x;
      var y = @intToFloat(f32, yi + 1) * tile_step.y;
      
      x -= camera.pixel_offset.x;
      y -= camera.pixel_offset.y;

      x -= dest.x;
      y -= dest.y;
      
      const variant = map.get(surface.getCorners(.{xi, yi}));
      const tile_src = ray.Rectangle{
        .x = @intToFloat(f32, variant.x) * 16,
        .y = @intToFloat(f32, variant.y) * 16,
        .width = 16,
        .height = 16,
      };
      ray._wDrawTexturePro(
        &texture,
        &tile_src,
        &.{.x = x - (tile_step.x / 2), .y = y - (tile_step.y / 2), .width = tile_step.x, .height = tile_step.y},
        &.{.x = 0, .y = 0},
        0,
        &ray.WHITE,
      );
    }
  }
}

pub fn main() !void {
  const alloc = std.heap.page_allocator;
  
  var tile_map = TileMap.init(alloc);
  createTileMap(&tile_map);

  const window_w = 800;
  const window_h = 450;
  ray.InitWindow(window_w, window_h, "sample");
  
  const texture = ray.LoadTexture("src/img/sheet_19.png");
  const cursor = ray.LoadTexture("src/img/image0004.png");
  
  ray.SetTargetFPS(60);
  
  ray.DisableCursor();
  
  var surface = Surface{};
  var camera = Camera{
    .pixel_size = 4,
    .tile_size = .mini,
    .pixel_offset = .{.x = 0, .y = 0},
  };
  
  var prev_pos = ray.GetMousePosition();
  var cursor_pos: ray.Vector2 = .{.x = 0, .y = 0};
  
  while(!ray.WindowShouldClose()) {
    var frame_arena = std.heap.ArenaAllocator.init(alloc);
    const arena = &frame_arena.allocator;
    _ = arena;
  
    const curr_pos = ray.GetMousePosition();
    const offset = ray.Vector2{.x = curr_pos.x - prev_pos.x, .y = curr_pos.y - prev_pos.y};
    prev_pos = curr_pos;
    
    cursor_pos.x += offset.x;
    cursor_pos.y += offset.y;
    const speed = 1;
    const move_x = @ceil(cursor_pos.x * speed);
    const move_y = @ceil(cursor_pos.y * speed);
    camera.move(.{.x = move_x, .y = move_y});
    cursor_pos.x -= move_x;
    cursor_pos.y -= move_y;
  
    ray.BeginDrawing(); {
      ray.ClearBackground(ray.RAYWHITE);
      
      renderSurface(
        texture,
        camera,
        surface,
        .{.x = 0, .y = 0, .width = window_w, .height = window_h},
        tile_map,
      );

      const m_screen_pos: ray.Vector2 = .{
        .x = (window_w / 2) + cursor_pos.x,
        .y = (window_h / 2) + cursor_pos.y,
      };
      _ = cursor;
      if(false) ray._wDrawTexturePro(
        &cursor,
        &.{.x = 0, .y = 0, .width = 64, .height = 64},
        &.{.x = m_screen_pos.x - (64 / 2), .y = m_screen_pos.y - (64 / 2), .width = 64, .height = 64},
        &.{.x = 0, .y = 0},
        0,
        &ray.WHITE,
      );
      
      const m_world_pos_f = camera.screenToWorld(m_screen_pos);
      const m_world_pos = floatFloorToInt(m_world_pos_f);
      
      const shift1 = m_world_pos_f - @floor(m_world_pos_f);
      const pow = 0.3;
      const one: TilePosFloat = .{1, 1};
      const shift = vecpow(shift1, pow) / (vecpow(shift1, pow) + vecpow(one - shift1, pow));
      
      const selected_tile = camera.worldToScreen(
        @floor(m_world_pos_f) + (shift - @as(TilePosFloat, .{0.5, 0.5}))
      );
      const scale = camera.step();
      ray._wDrawRectangleRec(
        &.{.x = selected_tile.x, .y = selected_tile.y, .width = scale.x, .height = scale.y},
        &.{.r = 255, .g = 255, .b = 255, .a = 128},
      );
      
      ray.DrawText(std.fmt.allocPrint0(arena,
        "{}\n{}",
        .{m_world_pos, surface.getTile(m_world_pos)},
      ) catch @panic("oom"), 10, 10, 20, ray.WHITE);
    } ray.EndDrawing();
  }
}

fn vecpow(x: TilePosFloat, y: f32) TilePosFloat {
  return .{std.math.pow(f32, x[0], y), std.math.pow(f32, x[1], y)};
}

// TODO rather than locking the cursor at the center,
// have it animate towards the center or something
