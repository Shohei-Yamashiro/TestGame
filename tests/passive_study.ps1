param([int[]]$Seeds = @(1, 2, 3, 4, 5, 6), [string[]]$Policies = @("casual", "kite"), [int]$Parallel = 10)
$godot = "D:\Godot\lib\4.7.2\Godot_v4.7.2-stable_win64_console.exe"
$project = "D:\Godot\projects\TestGame"
$out = Join-Path $env:TEMP "passive_study"
New-Item -ItemType Directory -Force $out | Out-Null
Get-ChildItem $out | Remove-Item
$passives = @("none", "attack", "rate", "move", "magnet", "max_hp", "regen", "area", "armor", "growth", "knock")
$jobs = @()
foreach ($p in $passives) { foreach ($pol in $Policies) { foreach ($s in $Seeds) { $jobs += ,@($p, $pol, $s) } } }
$running = @()
foreach ($j in $jobs) {
    while (($running | Where-Object { -not $_.HasExited }).Count -ge $Parallel) { Start-Sleep -Milliseconds 300 }
    $name = "$($j[0])_$($j[1])_$($j[2])"
    $running += Start-Process $godot -ArgumentList @("--headless", "--fixed-fps", "60", "--path", $project, "-s", "res://tests/passive_study.gd", "--", $j[0], $j[1], "$($j[2])") `
        -PassThru -NoNewWindow -RedirectStandardOutput "$out\$name.txt" -RedirectStandardError "$out\$name.err.txt"
}
foreach ($r in $running) { if (-not $r.WaitForExit(400000)) { $r.Kill() } }
$rows = foreach ($f in Get-ChildItem "$out\*.txt" -Exclude *.err.txt) {
    $line = (Get-Content $f | Select-String '^STUDY').Line
    if ($line -match 'passive=(\S+) policy=(\S+) outcome=(\S+) t=([\d.]+) score=(\d+) kills=(\d+) level=(\d+) taken=(\d+) healed=(\d+)') {
        [pscustomobject]@{ P = $Matches[1]; Pol = $Matches[2]; Out = $Matches[3]; T = [double]$Matches[4]; Score = [int]$Matches[5]; Kills = [int]$Matches[6]; Level = [int]$Matches[7]; Taken = [int]$Matches[8]; Healed = [int]$Matches[9] }
    } else { Write-Host "missing: $($f.Name)" }
}
$rows | Export-Csv "$out\results.csv" -NoTypeInformation -Encoding utf8
foreach ($pol in $Policies) {
    Write-Host "== $pol"
    $rows | Where-Object Pol -eq $pol | Group-Object P | ForEach-Object {
        $g = $_.Group
        [pscustomobject]@{
            passive = $_.Name
            clears = "$(@($g | Where-Object Out -eq 'CLEARED').Count)/$($g.Count)"
            avg_t = [math]::Round(($g | Measure-Object T -Average).Average, 1)
            avg_score = [math]::Round(($g | Measure-Object Score -Average).Average)
            avg_kills = [math]::Round(($g | Measure-Object Kills -Average).Average)
            avg_level = [math]::Round(($g | Measure-Object Level -Average).Average, 1)
            taken_per_min = [math]::Round(($g | ForEach-Object { $_.Taken / [math]::Max(1, $_.T) * 60 } | Measure-Object -Average).Average, 1)
        }
    } | Sort-Object avg_t -Descending | Format-Table -AutoSize | Out-String | Write-Host
}
