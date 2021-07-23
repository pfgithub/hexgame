const std = @import("std");
const ray = @import("raylib.zig");

const Tile = enum{
  desert,
  plains,
  grassland,
  unknown_1,
  tundra_1,
  tundra_2,
  mountain_1,
  city,
  temperate_forest,
  rain_forest,
  boreal_forest,
  mountain_2,
  control_base,
  unknown_2,
  water,
  forested_mountain,
  farmland_0,
  farmland_1,
  farmland_2,
  farmland_3,
  tile_highlight,
  pub fn toMiniCoords(tile: Tile) ray.Rectangle {
    const index: f32 = @intToFloat(f32, @enumToInt(tile));
    const x = 1 + @mod(index, 7) * (15 + 1);
    const y = 1 + @divFloor(index, 7) * (18 + 1);
    
    return .{.x = x, .y = y, .width = 15, .height = 18};
  }
};

const TileSize = enum{
  nano,
  micro,
  mini,
  pub fn step(_: TileSize, scale: f32) TileStep {
    return .{
      .x = 14 * scale,
      .y = 9 * scale,
      .w = 15 * scale,
      .h = 18 * scale,
      .mid = 7 * scale,
      .top = 5 * scale,
    };
  }
};

const TileStep = struct {
  x: f32,
  y: f32,
  w: f32,
  h: f32,
  mid: f32,
  top: f32,
};

const Surface = struct {
  // contains chunks which have
  // a bunch of tiles and any associated tile
  // data if needed
  pub fn getTile(_: Surface, pos: TilePos) Tile {
    if(@mod(pos.x, 4) == 0 and @mod(pos.y, 5) <= 2) {
      return Tile.water;
    }
    return Tile.grassland;
  }
};

const TilePos = struct {
  x: i32,
  y: i32,
};
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
  pub fn step(camera: Camera) TileStep {
    return camera.tile_size.step(camera.pixel_size);
  }
  pub fn visibleTileRange(camera: Camera, dest: ray.Rectangle) TileRect {
    const tile_step = camera.step();
    const x_count = @floatToInt(i32, @ceil(dest.width / tile_step.x));
    const y_count = @floatToInt(i32, @ceil(dest.height / tile_step.y));
    return .{.x = 0 - 1, .y = 0 - 1, .w = x_count + 2, .h = y_count + 2};
  }
};

pub fn renderSurface(texture: ray.Texture2D, camera: Camera, surface: Surface, dest: ray.Rectangle) void {
  const tile_step = camera.step();
  const range = camera.visibleTileRange(dest);

  var yi: i32 = range.y;
  while(yi < range.y + range.w) : (yi += 1) {
    var xi: i32 = range.x;
    while(xi < range.x + range.w) : (xi += 1) {
    
      var x = @intToFloat(f32, xi) * tile_step.x;
      var y = @intToFloat(f32, yi) * tile_step.y;
      
      if(@mod(yi, 2) == 1) {
        x += tile_step.mid;
      }
      
      x -= camera.pixel_offset.x;
      y -= camera.pixel_offset.y;

      x -= dest.x;
      y -= dest.y;
      
      const tile_src = surface.getTile(.{.x = xi, .y = yi}).toMiniCoords();
      ray._wDrawTexturePro(
        &texture,
        &tile_src,
        &.{.x = x, .y = y - tile_step.top, .width = tile_step.w, .height = tile_step.h},
        &.{.x = 0, .y = 0},
        0,
        &ray.WHITE,
      );
    }
  }
}

pub fn main() !void {
  const window_w = 800;
  const window_h = 450;
  ray.InitWindow(window_w, window_h, "sample");
  
  const texture = ray.LoadTexture("src/img/pixil-frame-0.png");
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
  
  while(!ray.WindowShouldClose()) {
    const curr_pos = ray.GetMousePosition();
    const offset = ray.Vector2{.x = curr_pos.x - prev_pos.x, .y = curr_pos.y - prev_pos.y};
    prev_pos = curr_pos;
    
    camera.move(offset);
  
    ray.BeginDrawing(); {
      ray.ClearBackground(ray.RAYWHITE);
      
      renderSurface(texture, camera, surface, .{.x = 0, .y = 0, .width = window_w, .height = window_h});

      ray._wDrawTexturePro(
        &cursor,
        &.{.x = 0, .y = 0, .width = 64, .height = 64},
        &.{.x = (window_w / 2) - (64 / 2), .y = (window_h / 2) - (64 / 2), .width = 64, .height = 64},
        &.{.x = 0, .y = 0},
        0,
        &ray.WHITE,
      );
    } ray.EndDrawing();
  }
}

// TODO rather than locking the cursor at the center,
// have it animate towards the center or something
