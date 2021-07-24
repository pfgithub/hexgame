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

void _wGetMousePosition(
	Vector2* out
) IMPL({
	*out = GetMousePosition();
})

void _wDrawRectangleRounded(
	const Rectangle* rect,
	const float* radius,
	const Color* color
) IMPL({
	float min_s = rect->width > rect->height ? rect->height : rect->width;
	float roundedness = *radius / min_s;
	int segments = *radius; // raylib segment calculation seems to be very off.
	if(segments > 15) segments = 0;
	DrawRectangleRounded(*rect, roundedness, segments, *color);
})
