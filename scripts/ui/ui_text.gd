extends RefCounted

# Text helpers shared by the UI screens.


static func format_time(t: float) -> String:
	var total := maxi(0, int(t))
	return "%d:%02d" % [total / 60, total % 60]
