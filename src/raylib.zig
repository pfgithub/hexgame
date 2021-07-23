pub usingnamespace @cImport({
  @cInclude("raylib.h");
  @cInclude("workaround.h");
});

// undefine GetMousePosition
pub fn wGetMousePosition() Vector2 {
  var res: Vector2 = undefined;
  _wGetMousePosition(&res);
  return res;
}
