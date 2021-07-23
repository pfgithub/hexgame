#include <raylib.h>

#ifdef workaround_implementation
	#define IMPL(body) body
#else
	#define IMPL(body) ;
#endif

void _wDrawTexturePro(
	const Texture2D* texture,
	const Rectangle* source,
	const Rectangle* dest,
	const Vector2* origin,
	float rotation,
	const Color* tint
) IMPL({
	DrawTexturePro(*texture, *source, *dest, *origin, rotation, *tint);
})

void _wDrawRectangleRec(
	const Rectangle* rec, const Color* color
) IMPL({
	DrawRectangleRec(*rec, *color);
})
