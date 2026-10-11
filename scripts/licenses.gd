extends RefCounted

# Licence notices for everything the game ships: the engine, its third-party components and the fonts.
# The engine parts come from the running binary, so they stay right across engine upgrades.
# The same text feeds the in-game licences screen and THIRD-PARTY-NOTICES.txt (tools/licenses).

const NOTICE_PATH := "res://THIRD-PARTY-NOTICES.txt"
# name, licence file; the fonts' licence texts must be exported with the game (see the export filter).
const FONTS := [
	["M PLUS 1", "res://assets/fonts/MPLUS1-OFL.txt"],
	["Noto Sans Symbols 2", "res://assets/fonts/NotoSansSymbols2-OFL.txt"],
]


# [heading, body] pairs in display order.
static func sections() -> Array:
	var out := []
	out.append(["Godot Engine", "This game uses Godot Engine, available under the following license:\n\n" + Engine.get_license_text().strip_edges()])
	for font in FONTS:
		out.append(["%s (font)" % font[0], FileAccess.get_file_as_string(font[1]).strip_edges()])
	out.append(["Godot Engine third-party components", _components()])
	var texts: Dictionary = Engine.get_license_info()
	var names := texts.keys()
	names.sort()
	for name in names:
		out.append(["License: %s" % name, str(texts[name]).strip_edges()])
	return out


static func _components() -> String:
	var lines: PackedStringArray = []
	for component: Dictionary in Engine.get_copyright_info():
		lines.append(str(component["name"]))
		for part: Dictionary in component["parts"]:
			for holder in part["copyright"]:
				lines.append("  Copyright %s" % holder)
			lines.append("  License: %s" % part["license"])
		lines.append("")
	return "\n".join(lines).strip_edges()


static func notice_text() -> String:
	var blocks: PackedStringArray = []
	for section in sections():
		var heading: String = section[0]
		blocks.append("%s\n%s\n\n%s" % [heading, "=".repeat(heading.length()), section[1]])
	return "\n\n\n".join(blocks) + "\n"
