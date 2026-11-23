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
$backend = Join-Path $source 'CacheCleaner.ps1'
$gui = Join-Path $source 'CacheCleaner.GUI.ps1'
$nvidia = Join-Path $source 'NvidiaCache.ps1'
$exe = Join-Path $PSScriptRoot 'KSweep.exe'
$icon = Join-Path $PSScriptRoot 'assets\KSweep.ico'
& $compiler /nologo /target:winexe /platform:anycpu /optimize+ /codepage:65001 /reference:System.Windows.Forms.dll "/out:$exe" "/win32icon:$icon" "/resource:$icon,KSweep.ico" "/resource:$backend,CacheCleaner.ps1" "/resource:$gui,CacheCleaner.GUI.ps1" "/resource:$nvidia,NvidiaCache.ps1" $launcher
if ($LASTEXITCODE -ne 0) { throw "Build lỗi, csc.exe trả về mã $LASTEXITCODE." }
Write-Host "Đã build $exe"