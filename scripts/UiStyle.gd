extends RefCounted
## Shared look for the modal menus (inventory, pause, dialogue, class picker).

const BG := Color(0.08, 0.065, 0.05, 0.94)
const EDGE := Color(0.6, 0.48, 0.26)
const GOLD := Color(0.95, 0.82, 0.45)
const TEXT := Color(0.93, 0.9, 0.82)


const RARITY := {
	"common": Color(0.82, 0.8, 0.74),
	"uncommon": Color(0.45, 0.85, 0.5),
	"rare": Color(0.4, 0.65, 1.0),
	"legendary": Color(1.0, 0.65, 0.25),
}


static func rarity_color(rarity: String) -> Color:
	return RARITY.get(rarity, RARITY["common"])


static func box(bg: Color = BG, edge: Color = EDGE, radius: int = 8, margin: int = 14) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = edge
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin - 4
	sb.content_margin_bottom = margin - 4
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 8
	return sb


static func label(text: String, size: int = 14, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func style_button(b: Button, accent: Color = EDGE) -> void:
	var normal := box(Color(0.16, 0.13, 0.1), accent.darkened(0.3), 5, 10)
	normal.shadow_size = 0
	var hover := box(Color(0.26, 0.2, 0.13), accent, 5, 10)
	hover.shadow_size = 0
	var pressed := box(Color(0.34, 0.26, 0.15), GOLD, 5, 10)
	pressed.shadow_size = 0
	var disabled := box(Color(0.1, 0.09, 0.08), Color(0.25, 0.22, 0.18), 5, 10)
	disabled.shadow_size = 0
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.47, 0.42))
