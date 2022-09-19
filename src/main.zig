const std = @import("std");
const ray = @import("raylib.zig");

const TileEdges = [4]Tile; // ul ur bl br

const Tile = enum(u32) {
    /// area that hasn't been loaded
    unloaded = std.math.maxInt(u32) - 1,
    /// eg a tile could be [grass, grass, empty, empty] and it
    /// can be used for any transition involving [grass, grass, *, *]
    /// and it should pick which order to try * in based on this
    /// enum order probably so you don't end up with dirt above a grass
    /// transition
    any_below = std.math.maxInt(u32),
    /// tiles are defined in the TileSet
    _,
    pub fn name(tile: Tile, set: TileSet) []const u8 {
        return switch (tile) {
            .unloaded => ".unloaded",
            .any_below => ".any_below",
            _ => |x| set.tiles.items[@enumToInt(x)].name,
        };
    }
};

const TileSetKind = enum {
    // each image is the center of four tiles
    center_of_4,
    // each image is its own tile, the surrounding
    // tiles are used for automatic variant selection
    surrounding_8,
};
const TileInfo = struct {
    name: []const u8,
};
const TileSet = struct {
    tiles: std.ArrayListUnmanaged(TileInfo),
    variants: TileVariantMap,
    kind: TileSetKind = .center_of_4,

    pub fn new(alloc: std.mem.Allocator) *TileSet {
        var res = alloc.create(TileSet) catch @panic("oom");
        res.* = .{
            .variants = TileVariantMap.init(alloc),
            .tiles = std.ArrayListUnmanaged(TileInfo){},
        };
        return res;
    }
    pub fn addTile(set: *TileSet, info: TileInfo) Tile {
        const index = set.tiles.items.len;
        set.tiles.append(set.variants.data.allocator, info) catch @panic("oom");
        return @intToEnum(Tile, @intCast(u32, index));
    }
    pub fn fromString(set: TileSet, str: []const u8) ?Tile {
        // n² when fromString is called in a loop, oops
        for (set.tiles.items) |tile, i| {
            if (std.mem.eql(u8, str, tile.name)) {
                return @intToEnum(Tile, @intCast(u32, i));
            }
        }
        return null;
    }
};
const TileVariantMap = struct {
    const TileVariants = std.ArrayListUnmanaged(TileVariant);
    const TileVariant = struct { x: u16, y: u16 };

    data: std.AutoHashMap(TileEdges, TileVariants),

    fn init(alloc: std.mem.Allocator) TileVariantMap {
        return .{
            .data = std.AutoHashMap(TileEdges, TileVariants).init(alloc),
        };
    }
    fn add(map: *TileVariantMap, edges: TileEdges, values: []const TileVariant) void {
        const entry = map.data.getOrPut(edges) catch @panic("oom");
        if (!entry.found_existing) {
            entry.value_ptr.* = std.ArrayListUnmanaged(TileVariant){};
        }
        entry.value_ptr.appendSlice(map.data.allocator, values) catch @panic("oom");
    }
    fn get(map: TileVariantMap, edges: TileEdges) []TileVariant {
        // todo support air and variants and stuff
        const found = map.data.get(edges);
        if (found == null or found.?.items.len == 0) {
            return &[_]TileVariant{};
        }
        return found.?.items;
    }
};

// width: 24
pub fn addFromData(
    map: *TileVariantMap,
    data: []const u8,
    start: TileVariantMap.TileVariant,
    tiles: []const Tile,
) void {
    var pos = start;
    var lines = std.mem.split(u8, data, "\n");
    while (lines.next()) |line| : ({
        pos.y += 1;
        pos.x = start.x;
    }) {
        var items = std.mem.split(u8, line, ",");
        while (items.next()) |item| : (pos.x += 1) {
            map.add(.{
                tiles[item[0] - '0'],
                tiles[item[1] - '0'],
                tiles[item[2] - '0'],
                tiles[item[3] - '0'],
            }, &.{pos});
        }
    }
}
pub fn add6x6(map: *TileVariantMap, start: TileVariantMap.TileVariant, tiles: [2]Tile) void {
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

pub fn createSampleSet(alloc: std.mem.Allocator) *TileSet {
    const set = TileSet.new(alloc);

    const grass = set.addTile(.{ .name = "grass" });
    const dirt = set.addTile(.{ .name = "dirt" });
    const water = set.addTile(.{ .name = "water" });
    const dark_dirt = set.addTile(.{ .name = "dark_dirt" });

    add6x6(&set.variants, .{ .x = 0, .y = 0 }, .{ dirt, grass });
    add6x6(&set.variants, .{ .x = 0, .y = 6 }, .{ water, grass });
    add6x6(&set.variants, .{ .x = 7, .y = 0 }, .{ dark_dirt, dirt });
    add6x6(&set.variants, .{ .x = 7, .y = 6 }, .{ water, dirt });
    add6x6(&set.variants, .{ .x = 13, .y = 0 }, .{ dark_dirt, grass });
    add6x6(&set.variants, .{ .x = 0, .y = 12 }, .{ .any_below, grass });
    add6x6(&set.variants, .{ .x = 6, .y = 12 }, .{ .any_below, dirt });
    set.variants.add(.{ grass, grass, grass, grass }, &.{.{ .x = 6, .y = 6 }});
    set.variants.add(.{ .unloaded, .unloaded, .unloaded, .unloaded }, &.{.{ .x = 23, .y = 0 }});

    // would like to have everything→air in here, it'd be useful
    // also, to make this in-program rather than using
    // a fn like createTileMap, you would basically paint
    // the four corners of every tile with the chosen colors
    // it'd be wayy easier

    return set;
}

const TileSize = enum {
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

const Chunk = [128 * 128]Tile;

fn loadChunk(text: []const u8, tileset: *TileSet, chunk: *Chunk, alloc: std.mem.Allocator) !void {
    var components = std.mem.split(u8, text, "----\n");
    {
        const header = components.next() orelse return error.Corrupted;
        if (!std.mem.eql(u8, header, "chunk-v1\n")) {
            std.log.err("Chunk is for unsupported version", .{});
            return error.BadVersion;
        }
    }
    var final_map = std.ArrayList(Tile).init(alloc);
    defer final_map.deinit();
    {
        var mappings = std.mem.split(u8, components.next() orelse return error.Corrupted, "\n");
        while (mappings.next()) |str| {
            if (str.len == 0) break;
            final_map.append(tileset.fromString(str) orelse {
                std.log.err("Missing tile to load chunk `{s}`", .{str});
                return error.MissingTiles;
            }) catch @panic("oom");
        }
    }
    {
        var chunk_data = std.mem.tokenize(u8, components.next() orelse return error.Corrupted, ",\n");
        var i: usize = 0;
        while (chunk_data.next()) |tile_idx_str| : (i += 1) {
            if (tile_idx_str.len == 0) break;
            const tile_idx = @bitCast(u32, std.fmt.parseInt(i32, tile_idx_str, 16) catch return error.Corrupted);
            if (tile_idx == std.math.maxInt(u32)) {
                chunk[i] = .any_below;
                continue;
            }
            if (tile_idx >= final_map.items.len) return error.Corrupted;
            const tile = final_map.items[tile_idx];
            chunk[i] = tile;
        }
        if (i != 128 * 128) return error.Corrupted;
    }
}
fn saveChunk(chunk: Chunk, tileset: *TileSet, out: anytype) void {
    const separator = "----\n";
    out.print("chunk-v1\n", .{}) catch @panic("oom");
    out.writeAll(separator) catch @panic("oom");
    for (tileset.tiles.items) |tile| {
        out.print("{s}\n", .{tile.name}) catch @panic("oom");
    }
    out.writeAll(separator) catch @panic("oom");
    for (chunk) |tile, i| {
        out.print("{x}", .{@bitCast(i32, @enumToInt(tile))}) catch @panic("oom");
        if (i % 128 == 127) out.writeAll("\n") catch @panic("oom") //
        else out.writeAll(",") catch @panic("oom");
    }
}

const Surface = struct {
    alloc: std.mem.Allocator,
    chunk: *Chunk,

    // TODO it needs to be possible to
    // store information in every line and point
    // on the grid. so point info would be eg
    // variant selection, it can store "hey
    //  you should select variant <> for this
    //  midpoint"
    // and for surrounding 8 you may want line
    // info so eg "hey, for this line, use
    // this color or smth

    // contains chunks which have
    // a bunch of tiles and any associated tile
    // data if needed
    pub fn init(alloc: std.mem.Allocator) Surface {
        const root_chunk = alloc.create(Chunk) catch @panic("oom");
        for (root_chunk) |*tile| tile.* = .any_below;
        return .{
            .alloc = alloc,
            .chunk = root_chunk,
        };
    }
    pub fn getTile(surface: Surface, pos: TilePos) Tile {
        if (pos[0] < 0 or pos[0] >= 128 or pos[1] < 0 or pos[1] >= 128) {
            return .unloaded;
        }
        return surface.chunk[@intCast(usize, pos[1] * 128 + pos[0])];
    }
    pub fn setTile(surface: *Surface, pos: TilePos, tile: Tile) bool {
        if (pos[0] < 0 or pos[0] >= 128 or pos[1] < 0 or pos[1] >= 128) {
            return false;
        }
        surface.chunk[@intCast(usize, pos[1] * 128 + pos[0])] = tile;
        return true;
    }
    pub fn getCorners(surface: Surface, pos: TilePos) TileEdges {
        return .{
            surface.getTile(pos),
            surface.getTile(pos + @as(TilePos, .{ 1, 0 })),
            surface.getTile(pos + @as(TilePos, .{ 0, 1 })),
            surface.getTile(pos + @as(TilePos, .{ 1, 1 })),
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
        const pos_start = floatFloorToInt(camera.screenToWorld(.{ .x = dest.x, .y = dest.y }));
        return .{ .x = pos_start[0] - 1, .y = pos_start[1] - 1, .w = x_count + 2, .h = y_count + 2 };
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

pub fn renderTile(
    texture: ray.Texture2D,
    tile_pos: ray.Rectangle,
    corners: TileEdges,
    tile_set: *TileSet,
) void {
    const variants = tile_set.variants.get(corners);
    if (variants.len > 0) {
        const variant = variants[0];
        const tile_src = ray.Rectangle{
            .x = @intToFloat(f32, variant.x) * 16,
            .y = @intToFloat(f32, variant.y) * 16,
            .width = 16,
            .height = 16,
        };
        ray._wDrawTexturePro(
            &texture,
            &tile_src,
            &tile_pos,
            &ray.Vector2{ .x = 0, .y = 0 },
            0,
            &ray.WHITE,
        );
    } else {
        // TODO in order of highest to lowest, try rendering
        // each layer as only the current layer + air tiles
        // and then for the bottom layer, render all four corners
        // as that item.
        // (highest is highest in the enum)
        for (corners) |corner, i| {
            const materials = tile_set.variants.get(.{ corner, corner, corner, corner });
            if (materials.len == 0) continue;
            const material = materials[0];
            const ix = @intToFloat(f32, i % 2);
            const iy = @intToFloat(f32, i / 2);
            ray._wDrawTexturePro(
                &texture,
                &ray.Rectangle{
                    .x = @intToFloat(f32, material.x) * 16 + (ix * 8),
                    .y = @intToFloat(f32, material.y) * 16 + (iy * 8),
                    .width = 8,
                    .height = 8,
                },
                &ray.Rectangle{
                    .x = tile_pos.x + (ix * (tile_pos.width / 2)),
                    .y = tile_pos.y + (iy * (tile_pos.height / 2)),
                    .width = tile_pos.width / 2,
                    .height = tile_pos.height / 2,
                },
                &ray.Vector2{ .x = 0, .y = 0 },
                0,
                &ray.WHITE,
            );
        }
    }
}

pub fn renderSurface(
    texture: ray.Texture2D,
    camera: Camera,
    surface: Surface,
    dest: ray.Rectangle,
    tile_set: *TileSet,
) void {
    const tile_step = camera.step();
    const range = camera.visibleTileRange(dest);

    var yi: i32 = range.y;
    while (yi < range.y + range.w) : (yi += 1) {
        var xi: i32 = range.x;
        while (xi < range.x + range.w) : (xi += 1) {
            var x = @intToFloat(f32, xi + 1) * tile_step.x;
            var y = @intToFloat(f32, yi + 1) * tile_step.y;

            x -= camera.pixel_offset.x;
            y -= camera.pixel_offset.y;

            x -= dest.x;
            y -= dest.y;

            const tile_pos: ray.Rectangle = .{
                .x = x - (tile_step.x / 2),
                .y = y - (tile_step.y / 2),
                .width = tile_step.x,
                .height = tile_step.y,
            };

            const corners = surface.getCorners(.{ xi, yi });
            renderTile(texture, tile_pos, corners, tile_set);
        }
    }
}

pub fn main() !void {
    const alloc = std.heap.page_allocator;

    const window_w = 800;
    const window_h = 450;
    ray.InitWindow(window_w, window_h, "sample");

    const texture = ray.LoadTexture("src/img/sheet_19.png");
    const tile_set = createSampleSet(alloc);

    const cursor = ray.LoadTexture("src/img/image0004.png");

    ray.SetTargetFPS(60);

    ray.DisableCursor();

    var surface = Surface.init(alloc);
    var camera = Camera{
        .pixel_size = 4,
        .tile_size = .mini,
        .pixel_offset = .{ .x = 0, .y = 0 },
    };

    blk: {
        std.log.info("Loading chunk…", .{});
        const saved_chunk = std.fs.cwd().readFileAlloc(alloc, "./saved_chunk.tgc", std.math.maxInt(usize)) catch |err| {
            std.log.info("Load chunk error {}", .{err});
            break :blk;
        };
        defer alloc.free(saved_chunk);
        loadChunk(saved_chunk, tile_set, surface.chunk, alloc) catch |err| {
            std.log.err("Chunk is corrupted {}", .{err});
            @panic("Chunk corrupted");
        };
        std.log.info("✓ Loaded", .{});
    }

    var prev_pos = ray.wGetMousePosition();
    var cursor_pos: ray.Vector2 = .{ .x = 0, .y = 0 };

    // settings
    const hotbar_items = &[_]Tile{
        @intToEnum(Tile, 0),
        @intToEnum(Tile, 1),
        @intToEnum(Tile, 2),
        @intToEnum(Tile, 3),
    };
    var hotbar_selection: usize = 0;
    const hotbar_item_width = 16 * 3;
    const hotbar_item_height = 16 * 3;
    const hotbar_spacing = 12;
    const hotbar_selector_size = 8;
    const hotbar_border_radius: f32 = 10;
    const hotbar_mode = false;

    const pan_speed = 1;
    const pan_safe_area_w = window_w / 2;
    const pan_safe_area_h = window_h / 2;

    while (!ray.WindowShouldClose()) {
        var frame_arena = std.heap.ArenaAllocator.init(alloc);
        const arena = frame_arena.allocator();

        const curr_pos = ray.wGetMousePosition();
        const offset = ray.Vector2{ .x = curr_pos.x - prev_pos.x, .y = curr_pos.y - prev_pos.y };
        prev_pos = curr_pos;

        cursor_pos.x += offset.x;
        cursor_pos.y += offset.y;
        if (cursor_pos.x > pan_safe_area_w) {
            cursor_pos.x -= pan_safe_area_w;

            const move_x = @ceil(cursor_pos.x * pan_speed);
            camera.move(.{ .x = move_x, .y = 0 });
            cursor_pos.x -= move_x;

            cursor_pos.x += pan_safe_area_w;
        }
        if (cursor_pos.y > pan_safe_area_h) {
            cursor_pos.y -= pan_safe_area_h;

            const move_y = @ceil(cursor_pos.y * pan_speed);
            camera.move(.{ .x = 0, .y = move_y });
            cursor_pos.y -= move_y;

            cursor_pos.y += pan_safe_area_h;
        }
        if (cursor_pos.x < -pan_safe_area_w) {
            cursor_pos.x += pan_safe_area_w;

            const move_x = @ceil(cursor_pos.x * pan_speed);
            camera.move(.{ .x = move_x, .y = 0 });
            cursor_pos.x -= move_x;

            cursor_pos.x -= pan_safe_area_w;
        }
        if (cursor_pos.y < -pan_safe_area_h) {
            cursor_pos.y += pan_safe_area_h;

            const move_y = @ceil(cursor_pos.y * pan_speed);
            camera.move(.{ .x = 0, .y = move_y });
            cursor_pos.y -= move_y;

            cursor_pos.y -= pan_safe_area_h;
        }
        if (ray.IsKeyPressed(ray.KEY_LEFT_BRACKET)) {
            if (hotbar_selection == 0) hotbar_selection = hotbar_items.len;
            hotbar_selection -= 1;
        } else if (ray.IsKeyPressed(ray.KEY_RIGHT_BRACKET)) {
            hotbar_selection += 1;
            hotbar_selection %= hotbar_items.len;
        }

        for ([_]c_int{
            ray.KEY_ONE,
            ray.KEY_TWO,
            ray.KEY_THREE,
            ray.KEY_FOUR,
            ray.KEY_FIVE,
            ray.KEY_SIX,
            ray.KEY_SEVEN,
            ray.KEY_EIGHT,
            ray.KEY_NINE,
            ray.KEY_ZERO,
        }) |key, i| {
            if (hotbar_items.len > i and ray.IsKeyPressed(key)) {
                hotbar_selection = i;
            }
        }

        const m_screen_pos: ray.Vector2 = .{
            .x = (window_w / 2) + cursor_pos.x,
            .y = (window_h / 2) + cursor_pos.y,
        };
        const scroll = ray.GetMouseWheelMove();

        if (scroll != 0) {
            var start_c = camera.screenToWorld(m_screen_pos);
            camera.pixel_offset = .{ .x = 0, .y = 0 };
            // glhf zooming on trackpad
            camera.pixel_size *= if (scroll > 0) @as(f32, 2) else 0.5;
            if (camera.pixel_size < 0.5) camera.pixel_size = 0.5;
            camera.pixel_offset = camera.worldToScreen(start_c);
            camera.pixel_offset.x -= m_screen_pos.x;
            camera.pixel_offset.y -= m_screen_pos.y;
            camera.pixel_offset.x = @floor(camera.pixel_offset.x);
            camera.pixel_offset.y = @floor(camera.pixel_offset.y);
        }

        ray.BeginDrawing();
        {
            ray.ClearBackground(ray.GRAY);

            renderSurface(
                texture,
                camera,
                surface,
                .{ .x = 0, .y = 0, .width = window_w, .height = window_h },
                tile_set,
            );

            if (true) ray._wDrawTexturePro(
                &cursor,
                &ray.Rectangle{ .x = 0, .y = 0, .width = 64, .height = 64 },
                &ray.Rectangle{ .x = m_screen_pos.x - (64 / 2), .y = m_screen_pos.y - (64 / 2), .width = 64, .height = 64 },
                &ray.Vector2{ .x = 0, .y = 0 },
                0,
                &ray.WHITE,
            );

            const m_world_pos_f = camera.screenToWorld(m_screen_pos);
            const m_world_pos = floatFloorToInt(m_world_pos_f);

            const shift1 = m_world_pos_f - @floor(m_world_pos_f);
            const pow = 0.3;
            const one: TilePosFloat = .{ 1, 1 };
            const shift = vecpow(shift1, pow) / (vecpow(shift1, pow) + vecpow(one - shift1, pow));

            const selected_tile = camera.worldToScreen(@floor(m_world_pos_f) + (shift - @as(TilePosFloat, .{ 0.5, 0.5 })));
            const scale = camera.step();
            ray._wDrawRectangleRec(
                &ray.Rectangle{ .x = selected_tile.x, .y = selected_tile.y, .width = scale.x, .height = scale.y },
                &ray.Color{ .r = 255, .g = 255, .b = 255, .a = 128 },
            );

            ray.DrawText((std.fmt.allocPrintZ(
                arena,
                "{}\n{s}",
                .{ m_world_pos, surface.getTile(m_world_pos).name(tile_set.*) },
            ) catch @panic("oom")).ptr, 10, 10, 20, ray.WHITE);

            if (ray.IsMouseButtonDown(ray.MOUSE_BUTTON_LEFT)) {
                const ntile = hotbar_items[hotbar_selection];
                if (!surface.setTile(m_world_pos, ntile)) {
                    std.log.info("Could not set tile", .{});
                }
            } else if (ray.IsMouseButtonDown(ray.MOUSE_BUTTON_RIGHT)) {
                if (!surface.setTile(m_world_pos, .any_below)) {
                    std.log.info("Could not set tile", .{});
                }
            }

            const hotbar_width: f32 = hotbar_items.len * (hotbar_item_width + hotbar_spacing) + hotbar_spacing;
            const hotbar_height: f32 = hotbar_item_height + hotbar_spacing * 2;
            const hotbar_left: f32 = window_w / 2 - hotbar_width / 2;
            const hotbar_top = window_h - hotbar_height;
            ray._wDrawRectangleRounded(&ray.Rectangle{
                .x = hotbar_left,
                .y = hotbar_top,
                .width = hotbar_width,
                .height = hotbar_height + 100,
            }, &hotbar_border_radius, &ray.Color{ .r = 240, .g = 240, .b = 240, .a = 240 });
            {
                const selection_x = (@intToFloat(f32, hotbar_selection) * (hotbar_item_width + hotbar_spacing) + hotbar_spacing + hotbar_left);
                ray._wDrawRectangleRounded(&ray.Rectangle{
                    .x = selection_x - hotbar_spacing,
                    .y = hotbar_top - hotbar_selector_size,
                    .width = hotbar_item_width + 2 * hotbar_spacing,
                    .height = hotbar_height + 100,
                }, &hotbar_border_radius, &ray.Color{ .r = 255, .g = 255, .b = 255, .a = 255 });
            }
            for (hotbar_items) |item, i| {
                const item_x = @intToFloat(f32, i) * (hotbar_item_width + hotbar_spacing) + hotbar_spacing + hotbar_left;
                var item_y = hotbar_top + hotbar_spacing;
                if (i == hotbar_selection) item_y -= hotbar_selector_size;

                if (hotbar_mode) {
                    const whalf = hotbar_item_width / 2;
                    const hhalf = hotbar_item_height / 2;

                    renderTile(texture, .{
                        .x = item_x - whalf,
                        .y = item_y - hhalf,
                        .width = hotbar_item_width,
                        .height = hotbar_item_height,
                    }, .{ .any_below, .any_below, .any_below, item }, tile_set);
                    renderTile(texture, .{
                        .x = item_x + whalf,
                        .y = item_y - hhalf,
                        .width = hotbar_item_width,
                        .height = hotbar_item_height,
                    }, .{ .any_below, .any_below, item, .any_below }, tile_set);
                    renderTile(texture, .{
                        .x = item_x - whalf,
                        .y = item_y + hhalf,
                        .width = hotbar_item_width,
                        .height = hotbar_item_height,
                    }, .{ .any_below, item, .any_below, .any_below }, tile_set);
                    renderTile(texture, .{
                        .x = item_x + whalf,
                        .y = item_y + hhalf,
                        .width = hotbar_item_width,
                        .height = hotbar_item_height,
                    }, .{ item, .any_below, .any_below, .any_below }, tile_set);
                } else {
                    renderTile(texture, .{
                        .x = item_x,
                        .y = item_y,
                        .width = hotbar_item_width,
                        .height = hotbar_item_height,
                    }, .{ item, item, item, item }, tile_set);
                }
            }
        }
        ray.EndDrawing();
    }

    {
        var out_w = std.ArrayList(u8).init(alloc);
        defer out_w.deinit();

        const out = out_w.writer();
        saveChunk(surface.chunk.*, tile_set, out);

        std.log.info("Saving chunk…", .{});
        try std.fs.cwd().writeFile("./saved_chunk.tgc", out_w.items);
        std.log.info("✓ Saved", .{});
    }
}

fn vecpow(x: TilePosFloat, y: f32) TilePosFloat {
    return .{ std.math.pow(f32, x[0], y), std.math.pow(f32, x[1], y) };
}

// TODO rather than locking the cursor at the center,
// have it animate towards the center or something
