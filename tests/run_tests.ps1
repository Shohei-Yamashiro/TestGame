<#
.SYNOPSIS
  Runs the project's automated tests. Used both locally and by CI.

.DESCRIPTION
  1. Import      - builds the .godot cache (needed on a fresh checkout)
  2. Check       - every script and scene loads             (fails the run)
  3. Unit        - logic regression tests                   (fails the run)
  4. Smoke       - all weapons at their special for 60 s    (fails the run)
  5. Bots        - fixed-seed bot runs, compared with tests/bot_baseline.txt
                   (differences are warnings only; script errors fail the run)
  6. Perf        - optional, runs the smoke test alone and enforces -MaxFrameMs

  Headless runs use --fixed-fps 60 so game time runs as fast as the CPU allows
  and the same seed always plays out the same way.

.EXAMPLE
  ./tests/run_tests.ps1                  # everything except perf
  ./tests/run_tests.ps1 -Quick           # skip the bots
  ./tests/run_tests.ps1 -UpdateBaseline  # accept the current bot results
  ./tests/run_tests.ps1 -Perf            # also check frame time (run with nothing else busy)
#>
param(
    [string]$Godot = $env:GODOT,
    [switch]$Quick,
    [switch]$UpdateBaseline,
    [switch]$Perf,
    [double]$MaxFrameMs = 8.0,
    [string[]]$Policies = @("casual", "kite", "idle"),
    [int[]]$Seeds = @(1, 2, 3),
    [int]$BotSeconds = 200,
    [int]$TimeoutSec = 300,
    [string]$LogDir = (Join-Path ([IO.Path]::GetTempPath()) "testgame_tests")
)

$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
$logDir = $LogDir
New-Item -ItemType Directory -Force $logDir | Out-Null
$baselinePath = Join-Path $PSScriptRoot "bot_baseline.txt"
$errorPattern = 'SCRIPT ERROR|Parse Error|^\s*ERROR:'

if (-not $Godot) {
    $Godot = "D:\Godot\lib\4.7.2\Godot_v4.7.2-stable_win64_console.exe"
}
if (-not (Test-Path $Godot)) {
    throw "Godot executable not found: $Godot (set -Godot or the GODOT environment variable)"
}

$failures = New-Object System.Collections.Generic.List[string]
$summary = New-Object System.Collections.Generic.List[string]

function Stop-Tree($proc) {
    try { $proc.Kill($true) } catch {
        # Windows PowerShell 5.1 has no tree kill; take down only this run's children.
        Get-CimInstance Win32_Process -Filter "ParentProcessId=$($proc.Id)" -ErrorAction SilentlyContinue |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
}

function Start-Godot([string]$name, [string[]]$arguments) {
    $out = Join-Path $logDir "$name.out.txt"
    $err = Join-Path $logDir "$name.err.txt"
    $proc = Start-Process -FilePath $Godot -ArgumentList $arguments -PassThru -NoNewWindow `
        -RedirectStandardOutput $out -RedirectStandardError $err
    # Touching the handle keeps ExitCode readable after exit on Windows PowerShell 5.1.
    $null = $proc.Handle
    return [pscustomobject]@{ Name = $name; Proc = $proc; Out = $out; Err = $err }
}

# Waits for a run and returns its combined log; records a failure on timeout, exit code or error lines.
function Complete-Godot($run, [switch]$AllowExitCode) {
    if (-not $run.Proc.WaitForExit($TimeoutSec * 1000)) {
        Stop-Tree $run.Proc
        $failures.Add("$($run.Name): timed out after ${TimeoutSec}s")
    }
    $run.Proc.WaitForExit()
    $log = @()
    foreach ($file in @($run.Out, $run.Err)) {
        if (Test-Path $file) { $log += Get-Content $file }
    }
    $errors = $log | Select-String -Pattern $errorPattern
    if ($errors) {
        $failures.Add("$($run.Name): script errors`n    " + (($errors | Select-Object -First 5) -join "`n    "))
    }
    if (-not $AllowExitCode -and $run.Proc.ExitCode -ne 0) {
        $detail = ($log | Select-String -Pattern 'FAIL' | Select-Object -First 5) -join "`n    "
        $failures.Add("$($run.Name): exit code $($run.Proc.ExitCode)`n    $detail")
    }
    return $log
}

function Invoke-Step([string]$name, [string[]]$arguments, [string]$resultPattern) {
    Write-Host "== $name"
    $log = Complete-Godot (Start-Godot $name $arguments)
    $line = $log | Select-String -Pattern $resultPattern | Select-Object -Last 1
    if ($line) {
        Write-Host "   $line"
        $summary.Add("| $name | ``$line`` |")
    }
    return $log
}

$headless = @("--headless", "--path", $project)
$fixed = @("--headless", "--fixed-fps", "60", "--path", $project)

Write-Host "== import"
Complete-Godot (Start-Godot "import" ($headless + @("--import"))) -AllowExitCode | Out-Null

Invoke-Step "check" ($headless + @("-s", "res://tests/check_scripts.gd")) '^CHECK ' | Out-Null
Invoke-Step "unit" ($headless + @("-s", "res://tests/unit_tests.gd")) '^UNIT ' | Out-Null
Invoke-Step "smoke" ($fixed + @("-s", "res://tests/smoke.gd", "--", "nosave")) '^SMOKE ' | Out-Null

if (-not $Quick) {
    Write-Host "== bots ($($Policies -join ', ') x seeds $($Seeds -join ', '), in parallel)"
    $runs = @()
    foreach ($policy in $Policies) {
        foreach ($seed in $Seeds) {
            $runs += Start-Godot "bot_${policy}_$seed" ($fixed + @("-s", "res://tests/bot.gd", "--", $policy, "$seed", "$BotSeconds", "nosave"))
        }
    }
    $results = @()
    foreach ($run in $runs) {
        $log = Complete-Godot $run
        $line = $log | Select-String -Pattern '^RESULT ' | Select-Object -Last 1
        $parts = $run.Name.Split("_")
        if ($line -and "$line" -match 'policy=(\S+) (\S+) at t=([\d.]+)s score=(\d+)') {
            $results += [pscustomobject]@{
                Policy = $parts[1]; Seed = [int]$parts[2]; Outcome = $Matches[2]; Time = [double]$Matches[3]; Score = [int]$Matches[4]
            }
        } else {
            $failures.Add("$($run.Name): no RESULT line")
        }
    }

    $baseline = @{}
    if (Test-Path $baselinePath) {
        foreach ($row in Get-Content $baselinePath) {
            if ($row -match '^\s*#' -or -not $row.Trim()) { continue }
            $f = $row -split '\s+'
            $baseline["$($f[0]) $($f[1])"] = [pscustomobject]@{ Outcome = $f[2]; Time = [double]$f[3]; Score = [int]$f[4] }
        }
    }

    $summary.Add("")
    $summary.Add("| bot | seed | result | time | score | baseline |")
    $summary.Add("|---|---|---|---|---|---|")
    $warnings = 0
    foreach ($r in $results | Sort-Object Policy, Seed) {
        $note = "-"
        $base = $baseline["$($r.Policy) $($r.Seed)"]
        if ($base) {
            $note = "$($base.Outcome) $($base.Score)"
            $drift = [math]::Abs($r.Score - $base.Score) / [math]::Max(1, $base.Score)
            if ($r.Outcome -ne $base.Outcome -or $drift -gt 0.25) {
                $note = "WARN (was $($base.Outcome) t=$($base.Time) score=$($base.Score))"
                $warnings++
            }
        }
        $row = "| $($r.Policy) | $($r.Seed) | $($r.Outcome) | $($r.Time)s | $($r.Score) | $note |"
        Write-Host "   $row"
        $summary.Add($row)
    }
    if ($warnings -gt 0) {
        Write-Host "   $warnings bot result(s) moved away from the baseline (warning only; rerun with -UpdateBaseline to accept)"
    }

    if ($UpdateBaseline) {
        $lines = @("# policy seed outcome time score  (regenerate with: ./tests/run_tests.ps1 -UpdateBaseline)")
        foreach ($r in $results | Sort-Object Policy, Seed) {
            $lines += "$($r.Policy) $($r.Seed) $($r.Outcome) $($r.Time) $($r.Score)"
        }
        Set-Content -Path $baselinePath -Value $lines -Encoding utf8
        Write-Host "   baseline updated: $baselinePath"
    }
}

if ($Perf) {
    $log = Invoke-Step "perf" ($fixed + @("-s", "res://tests/smoke.gd", "--", "nosave")) '^SMOKE '
    $line = $log | Select-String -Pattern 'avg_frame=([\d.]+)ms' | Select-Object -Last 1
    if ($line -and [double]$line.Matches[0].Groups[1].Value -gt $MaxFrameMs) {
        $failures.Add("perf: avg_frame $($line.Matches[0].Groups[1].Value)ms exceeds ${MaxFrameMs}ms")
    }
}

if ($env:GITHUB_STEP_SUMMARY) {
    $head = @("## Test results", "", "| step | result |", "|---|---|")
    ($head + $summary) | Add-Content -Path $env:GITHUB_STEP_SUMMARY -Encoding utf8
}

Write-Host ""
if ($failures.Count -gt 0) {
    Write-Host "FAILED ($($failures.Count))" -ForegroundColor Red
    foreach ($f in $failures) { Write-Host " - $f" -ForegroundColor Red }
    Write-Host "Logs: $logDir"
    exit 1
}
Write-Host "ALL PASSED  (logs: $logDir)" -ForegroundColor Green
exit 0
