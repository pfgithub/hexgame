pub usingnamespace @cImport({
    @cInclude("raylib.h");
    @cInclude("workaround.h");
});
const c = @This();

// undefine GetMousePosition
pub fn wGetMousePosition() c.Vector2 {
    var res: c.Vector2 = undefined;
    c._wGetMousePosition(&res);
    return res;
}
