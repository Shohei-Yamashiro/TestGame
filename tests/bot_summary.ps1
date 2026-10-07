# Summarises bot logs from run_tests.ps1 -LogDir <dir> per policy (clears, average survival, score, level).
param([Parameter(Mandatory)][string[]]$LogDirs)
foreach ($dir in $LogDirs) {
    $rows = Get-ChildItem (Join-Path $dir "bot_*.out.txt") | ForEach-Object {
        $line = (Get-Content $_ | Select-String '^RESULT').Line
        if ($line -match 'policy=(\S+) (\S+) at t=([\d.]+)s score=(\d+).*level=(\d+)') {
            $row = [pscustomobject]@{ Pol = $Matches[1]; Out = $Matches[2]; T = [double]$Matches[3]; S = [int]$Matches[4]; L = [int]$Matches[5]
                Hits = 0; Heals = 0; Cover = 0.0 }
            if ($line -match 'hits=(\d+) damage=(\d+) heals=(\d+) cover=([\d.]+)') {
                $row.Hits = [int]$Matches[1]; $row.Heals = [int]$Matches[3]; $row.Cover = [double]$Matches[4]
            }
            $row
        }
    }
    foreach ($group in $rows | Group-Object Pol) {
        $g = $group.Group
        $t = ($g | Measure-Object T -Average).Average
        "{0,-28} {1,-7} clears {2,2}/{3}  avg_t {4,6:N1}  avg_score {5,7:N0}  avg_lv {6,5:N1}  hits/min {7,5:N1}  heals {8,4:N1}  cover {9,4:N2}" -f (Split-Path $dir -Leaf), $group.Name,
            @($g | Where-Object Out -eq 'CLEARED').Count, $g.Count, $t,
            ($g | Measure-Object S -Average).Average, ($g | Measure-Object L -Average).Average,
            (($g | Measure-Object Hits -Sum).Sum / [math]::Max(1.0, ($g | Measure-Object T -Sum).Sum / 60.0)),
            ($g | Measure-Object Heals -Average).Average, ($g | Measure-Object Cover -Average).Average
    }
}
