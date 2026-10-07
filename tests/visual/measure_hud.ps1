# Prints the vertical extent of each HUD group in hud_only.png (from tests/visual/hud.gd), to check they share a centre line.
Add-Type -AssemblyName System.Drawing
$path = Join-Path $env:APPDATA 'Godot\app_userdata\TestGame\ui_shots\hud_only.png'
$img = [Drawing.Bitmap]::FromFile($path)
$groups = @(@('status', 18, 215), @('weapons', 236, 400), @('passives', 410, 572), @('time', 580, 700), @('score', 738, 900), @('kills', 918, 1060))
foreach ($g in $groups) {
	$min = 999; $max = -1
	for ($y = 0; $y -lt 76; $y++) {
		for ($x = $g[1]; $x -lt $g[2]; $x++) {
			$c = $img.GetPixel($x, $y)
			if ([Math]::Max($c.R, [Math]::Max($c.G, $c.B)) -gt 90) {
				if ($y -lt $min) { $min = $y }
				if ($y -gt $max) { $max = $y }
				break
			}
		}
	}
	'{0,-9} {1,2}-{2,2}  centre {3}' -f $g[0], $min, $max, (($min + $max) / 2)
}
$img.Dispose()
