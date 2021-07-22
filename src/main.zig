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
  pub fn toMiniCoords(tile: Tile) ray.Rectangle {
    const index: f32 = @intToFloat(f32, @enumToInt(tile));
    const x = 1 + @mod(index, 7) * (15 + 1);
    const y = 1 + @divFloor(index, 7) * (18 + 1);
    
    return .{.x = x, .y = y, .width = 15, .height = 18};
  }
};

const Scale = enum{
  nano,
  micro,
  mini,
};

pub fn main() !void {
  const window_w = 800;
  const window_h = 450;
  ray.InitWindow(window_w, window_h, "sample");
  
  const texture = ray.LoadTexture("src/img/pixil-frame-0.png");
  
  ray.SetTargetFPS(60);
  
  while(!ray.WindowShouldClose()) {
    ray.BeginDrawing(); {
      ray.ClearBackground(ray.RAYWHITE);
      
      const scale = 2;
      var yi: usize = 0;
      var i: u5 = 0;
      while(yi < 10) : (yi += 1) {
        var xi: usize = 0;
        while(xi < 10) : (xi += 1) {
          var x = @intToFloat(f32, xi * 15 * scale);
          const y = @intToFloat(f32, yi * 9 * scale);
          
          if(yi % 2 == 1) {
            x += 7 * scale;
          }
          
          const tile_coords = @intToEnum(Tile, i).toMiniCoords();
          ray._wDrawTexturePro(
            &texture,
            &tile_coords,
            &.{.x = x, .y = y - (5 * scale), .width = 15 * scale, .height = 18 * scale},
            &.{.x = 0, .y = 0},
            0,
            &ray.WHITE,
          );
          
          i +%= 1;
          i %= @as(comptime_int, std.meta.fields(Tile).len);
        }
      }
    } ray.EndDrawing();
  }
}

// I want to make a thing so it captures mouse
// movement and when I move my mouse it moves it on screen
// and animates towards the center
