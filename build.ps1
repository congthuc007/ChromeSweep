$ErrorActionPreference = 'Stop'
$framework = Join-Path $env:WINDIR 'Microsoft.NET'
$compiler = Join-Path $framework 'Framework64\v4.0.30319\csc.exe'
if (!(Test-Path -LiteralPath $compiler -PathType Leaf)) {
    $compiler = Join-Path $framework 'Framework\v4.0.30319\csc.exe'
}
if (!(Test-Path -LiteralPath $compiler -PathType Leaf)) {
    throw 'Không tìm thấy trình biên dịch csc.exe của .NET Framework 4.x.'
}
$source = Join-Path $PSScriptRoot 'src'
$launcher = Join-Path $source 'Launcher.cs'
$backend = Join-Path $source 'ChromeCacheCleaner.ps1'
$gui = Join-Path $source 'ChromeCacheCleaner.GUI.ps1'
$exe = Join-Path $PSScriptRoot 'Chrome Sweep.exe'
$icon = Join-Path $PSScriptRoot 'assets\ChromeSweep.ico'
& $compiler /nologo /target:winexe /platform:anycpu /optimize+ /codepage:65001 /reference:System.Windows.Forms.dll "/out:$exe" "/win32icon:$icon" "/resource:$icon,ChromeSweep.ico" "/resource:$backend,ChromeCacheCleaner.ps1" "/resource:$gui,ChromeCacheCleaner.GUI.ps1" $launcher
if ($LASTEXITCODE -ne 0) { throw "Build lỗi, csc.exe trả về mã $LASTEXITCODE." }
Write-Host "Đã build $exe"