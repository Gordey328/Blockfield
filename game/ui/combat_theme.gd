class_name CombatTheme
extends RefCounted
## Authored combat presentation. No gameplay/input state is changed here.
const WHITE := Color("f1f5fa")
const MUTED := Color("a9b8c9")
const ACCENT := Color("73e0d0")
const WARNING := Color("ffcf76")
const DANGER := Color("ff6979")
static var _font: FontVariation

static func font() -> Font:
	if _font == null:
		var face := preload("res://assets/fonts/InterVariable.ttf")
		face.allow_system_fallback = false
		_font = FontVariation.new()
		_font.base_font = face
		_font.variation_opentype = {"wght": 600.0}
		_font.opentype_features = {"tnum": 1}
		_font.fallbacks = [OpenSpadesLocalization.get_ui_font()]
	return _font

static func panel() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.045, 0.07, 0.62)
	style.border_color = Color(0.8, 0.9, 1.0, 0.13)
	style.set_border_width_all(1)
	style.set_corner_radius_all(18)
	style.shadow_color = Color(0, 0, 0, 0.14)
	style.shadow_size = 5
	return style

static func draw_icon(canvas: CanvasItem, kind: String, rectangle: Rect2, color: Color) -> void:
	var extent: float = minf(rectangle.size.x, rectangle.size.y)
	var origin: Vector2 = rectangle.get_center() - Vector2.ONE * extent * 0.5
	var paths: Array[PackedVector2Array] = []
	match kind:
		"health": paths = [PackedVector2Array([Vector2(.5,.15),Vector2(.5,.85)]),PackedVector2Array([Vector2(.15,.5),Vector2(.85,.5)])]
		"tool_weapon": paths = [PackedVector2Array([Vector2(.08,.4),Vector2(.32,.4),Vector2(.4,.28),Vector2(.8,.28),Vector2(.8,.48),Vector2(.32,.48),Vector2(.2,.7),Vector2(.08,.7),Vector2(.08,.4)]),PackedVector2Array([Vector2(.8,.36),Vector2(.98,.36)]),PackedVector2Array([Vector2(.5,.48),Vector2(.58,.7),Vector2(.7,.7),Vector2(.65,.48)])]
		"tool_spade": paths = [PackedVector2Array([Vector2(.32,.12),Vector2(.56,.12),Vector2(.56,.28),Vector2(.32,.28),Vector2(.32,.12)]),PackedVector2Array([Vector2(.44,.28),Vector2(.44,.6)]),PackedVector2Array([Vector2(.27,.6),Vector2(.62,.6),Vector2(.62,.78),Vector2(.44,.93),Vector2(.27,.78),Vector2(.27,.6)])]
		"tool_block": paths = [PackedVector2Array([Vector2(.18,.27),Vector2(.5,.1),Vector2(.82,.27),Vector2(.82,.73),Vector2(.5,.9),Vector2(.18,.73),Vector2(.18,.27),Vector2(.5,.45),Vector2(.82,.27)]),PackedVector2Array([Vector2(.5,.45),Vector2(.5,.9)])]
		"tool_grenade":
			canvas.draw_arc(origin+Vector2(.5,.6)*extent, extent*.27, 0, TAU, 28, color, 1.8, true)
			paths = [PackedVector2Array([Vector2(.39,.33),Vector2(.39,.16),Vector2(.58,.16),Vector2(.73,.32)]),PackedVector2Array([Vector2(.58,.16),Vector2(.65,.07),Vector2(.77,.1)])]
		"primary", "secondary":
			canvas.draw_arc(rectangle.get_center(), extent*.29, 0, TAU, 32, color, 1.8, true)
			if kind == "primary": canvas.draw_circle(rectangle.get_center(), extent*.07, color)
			paths = [PackedVector2Array([Vector2(.5,.04),Vector2(.5,.26)]),PackedVector2Array([Vector2(.5,.74),Vector2(.5,.96)]),PackedVector2Array([Vector2(.04,.5),Vector2(.26,.5)]),PackedVector2Array([Vector2(.74,.5),Vector2(.96,.5)])]
		"reload":
			canvas.draw_arc(rectangle.get_center(),extent*.32,.3,5.7,28,color,1.8,true)
			paths = [PackedVector2Array([Vector2(.72,.08),Vector2(.78,.32),Vector2(.54,.3)])]
		"jump": paths = [PackedVector2Array([Vector2(.22,.43),Vector2(.5,.14),Vector2(.78,.43)]),PackedVector2Array([Vector2(.5,.14),Vector2(.5,.75)]),PackedVector2Array([Vector2(.2,.88),Vector2(.8,.88)])]
		"crouch", "sprint":
			canvas.draw_circle(origin+Vector2(.58,.16)*extent,extent*.09,color)
			paths = [PackedVector2Array([Vector2(.52,.34),Vector2(.36,.54),Vector2(.61,.64),Vector2(.78,.84)]),PackedVector2Array([Vector2(.51,.35),Vector2(.7,.48),Vector2(.84,.42)]),PackedVector2Array([Vector2(.4,.53),Vector2(.28,.76),Vector2(.12,.76)])]
			if kind == "sprint": paths.append(PackedVector2Array([Vector2(.08,.3),Vector2(.3,.3)]))
		"map": paths = [PackedVector2Array([Vector2(.1,.22),Vector2(.36,.12),Vector2(.64,.22),Vector2(.9,.12),Vector2(.9,.78),Vector2(.64,.88),Vector2(.36,.78),Vector2(.1,.88),Vector2(.1,.22)]),PackedVector2Array([Vector2(.36,.12),Vector2(.36,.78)]),PackedVector2Array([Vector2(.64,.22),Vector2(.64,.88)])]
		"view_toggle":
			paths = [PackedVector2Array([Vector2(.07,.5),Vector2(.28,.28),Vector2(.72,.28),Vector2(.93,.5),Vector2(.72,.72),Vector2(.28,.72),Vector2(.07,.5)])]
			canvas.draw_arc(rectangle.get_center(),extent*.12,0,TAU,20,color,1.8,true)
		"menu": paths = [PackedVector2Array([Vector2(.17,.26),Vector2(.83,.26)]),PackedVector2Array([Vector2(.17,.5),Vector2(.83,.5)]),PackedVector2Array([Vector2(.17,.74),Vector2(.83,.74)])]
	for path: PackedVector2Array in paths:
		var transformed := PackedVector2Array()
		for point: Vector2 in path: transformed.append(origin + point * extent)
		canvas.draw_polyline(transformed, color, 1.8, true)
