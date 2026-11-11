# Windows PowerShell 5.1+
# Preview: .\ChromeCacheCleaner.ps1
# Clean:   .\ChromeCacheCleaner.ps1 -Clean
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Clean,
    [switch]$Temp,
    [Alias('CloseChrome')]
    [switch]$CloseBrowser,
    [ValidateSet('Chrome', 'Edge')]
    [string]$Browser = 'Chrome',
    [ValidatePattern('^(Default|Profile [0-9]+)$')]
    [string[]]$ProfileName,
    [switch]$MachineOutput
)

$ErrorActionPreference = 'Stop'

function Assert-RegularDirectory {
    param([System.IO.DirectoryInfo]$Directory)
    if ($Directory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        throw "Thư mục là liên kết: $($Directory.FullName)"
    }
}

function Measure-Cache {
    param([System.IO.DirectoryInfo]$Directory)

    $pending = New-Object 'System.Collections.Generic.Stack[System.IO.DirectoryInfo]'
    $pending.Push($Directory)
    $bytes = [long]0
    while ($pending.Count -gt 0) {
        $current = $pending.Pop()
        Assert-RegularDirectory $current
        foreach ($item in Get-ChildItem -LiteralPath $current.FullName -Force) {
            if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                throw "Có liên kết bên trong cache: $($item.FullName)"
            }
            if ($item.PSIsContainer) {
                $pending.Push($item)
            } else {
                $bytes += $item.Length
            }
        }
    }
    return $bytes
}

$browserInfo = if ($Browser -eq 'Edge') {
    @{ ProcessName = 'msedge'; DataPath = 'Microsoft\Edge\User Data' }
} else {
    @{ ProcessName = 'chrome'; DataPath = 'Google\Chrome\User Data' }
}

function Get-BrowserInSession {
    $sessionId = [Diagnostics.Process]::GetCurrentProcess().SessionId
    Get-Process -Name $browserInfo.ProcessName -ErrorAction SilentlyContinue |
        Where-Object { $_.SessionId -eq $sessionId }
}

function Assert-BrowserClosed {
    if (Get-BrowserInSession) {
        throw "$Browser vẫn còn chạy. Dùng nút Tắt hết $Browser rồi thử lại."
    }
}

if ($CloseBrowser) {
    $initial = @(Get-BrowserInSession)
    $remaining = $initial
    if ($initial.Count -and $PSCmdlet.ShouldProcess("$Browser trong phiên Windows hiện tại", 'Thoát trình duyệt; buộc tắt nếu cần')) {
        foreach ($process in $initial) {
            try { [void]$process.CloseMainWindow() } catch { }
        }
        $deadline = [DateTime]::UtcNow.AddSeconds(4)
        do {
            $remaining = @(Get-BrowserInSession)
            if (!$remaining.Count) { break }
            Start-Sleep -Milliseconds 200
        } while ([DateTime]::UtcNow -lt $deadline)

        foreach ($process in $remaining) {
            try {
                if (!$process.HasExited) { $process.Kill() }
            } catch {
                if (!$process.HasExited) {
                    Write-Warning "Không tắt được $Browser PID $($process.Id). $($_.Exception.Message)"
                }
            }
        }
        $deadline = [DateTime]::UtcNow.AddSeconds(2)
        do {
            $remaining = @(Get-BrowserInSession)
            if (!$remaining.Count) { break }
            Start-Sleep -Milliseconds 150
        } while ([DateTime]::UtcNow -lt $deadline)
    }

    if ($MachineOutput) {
        [pscustomobject]@{ InitialCount = $initial.Count; Remaining = $remaining.Count }
    } elseif ($remaining.Count -gt 0) {
        Write-Host "Còn $($remaining.Count) tiến trình $Browser."
    } else {
        Write-Host "$Browser đã thoát hoàn toàn trong phiên Windows hiện tại."
    }
    return
}

$localAppData = [Environment]::GetFolderPath('LocalApplicationData')
if ([string]::IsNullOrWhiteSpace($localAppData)) {
    throw 'Không tìm thấy LocalAppData của tài khoản Windows hiện tại.'
}

if ($Temp) {
    $windowsPath = [Environment]::GetFolderPath('Windows')
    $tempRoots = @(Join-Path $localAppData 'Temp')
    if ($windowsPath) {
        $tempRoots += Join-Path $windowsPath 'Temp'
    }
    $cutoff = [DateTime]::UtcNow.AddDays(-7)
    $eligibleBytes = [long]0
    $removedBytes = [long]0
    $removedFiles = 0
    $skipped = 0

    foreach ($tempRoot in $tempRoots) {
        try {
            if (!(Test-Path -LiteralPath $tempRoot -PathType Container)) { continue }
            $rootDirectory = Get-Item -LiteralPath $tempRoot -Force
            for ($ancestor = $rootDirectory; $null -ne $ancestor; $ancestor = $ancestor.Parent) {
                Assert-RegularDirectory $ancestor
            }
        } catch {
            $skipped++
            Write-Warning "Không đọc được $tempRoot. $($_.Exception.Message)"
            continue
        }

        $prefix = $rootDirectory.FullName.TrimEnd('\') + '\'
        $pending = New-Object 'System.Collections.Generic.Stack[System.IO.DirectoryInfo]'
        $pending.Push($rootDirectory)
        while ($pending.Count -gt 0) {
            $directory = $pending.Pop()
            try {
                $current = Get-Item -LiteralPath $directory.FullName -Force
                for ($ancestor = $current; $null -ne $ancestor; $ancestor = $ancestor.Parent) {
                    Assert-RegularDirectory $ancestor
                    if ($ancestor.FullName -eq $rootDirectory.FullName) { break }
                }
                $items = Get-ChildItem -LiteralPath $current.FullName -Force
            } catch {
                $skipped++
                continue
            }

            foreach ($item in $items) {
                if (!$item.FullName.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or
                    ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                    $skipped++
                    continue
                }
                if ($item.PSIsContainer) {
                    $pending.Push($item)
                    continue
                }
                if ($item.LastWriteTimeUtc -ge $cutoff -or $item.CreationTimeUtc -ge $cutoff) { continue }

                $size = [long]$item.Length
                $eligibleBytes += $size
                if ($Clean -and $PSCmdlet.ShouldProcess($item.FullName, 'Xóa file tạm')) {
                    try {
                        Remove-Item -LiteralPath $item.FullName -Force
                        $removedBytes += $size
                        $removedFiles++
                    } catch {
                        $skipped++
                    }
                }
            }
        }
    }

    if ($MachineOutput) {
        [pscustomobject]@{
            RemovedBytes = $removedBytes
            RemovedFiles = $removedFiles
            EligibleBytes = $eligibleBytes
            Skipped = $skipped
        }
    } elseif ($Clean) {
        Write-Host ('Đã xóa {0} file tạm ({1:N2} GiB). Số mục không xử lý được: {2}.' -f $removedFiles, ($removedBytes / 1GB), $skipped)
    } else {
        Write-Host ('File tạm đủ điều kiện: {0:N2} GiB. Dùng -Temp -Clean để dọn.' -f ($eligibleBytes / 1GB))
    }
    return
}
$userData = Join-Path $localAppData $browserInfo.DataPath
if (!(Test-Path -LiteralPath $userData -PathType Container)) {
    throw "Không tìm thấy dữ liệu $Browser ở đường dẫn mặc định: $userData"
}

$root = Get-Item -LiteralPath $userData -Force
for ($ancestor = $root; $null -ne $ancestor; $ancestor = $ancestor.Parent) {
    Assert-RegularDirectory $ancestor
}

if ($Clean) {
    Assert-BrowserClosed
}

$cacheNames = @('Cache', 'Code Cache', 'GPUCache')
$profiles = Get-ChildItem -LiteralPath $root.FullName -Directory -Force |
    Where-Object {
        $_.Name -cmatch '^(Default|Profile [0-9]+)$' -and
        (!$ProfileName -or $_.Name -cin $ProfileName)
    }

$entries = foreach ($profile in $profiles) {
    try {
        Assert-RegularDirectory $profile
    } catch {
        Write-Warning $_.Exception.Message
        continue
    }

    foreach ($name in $cacheNames) {
        $path = Join-Path $profile.FullName $name
        if (!(Test-Path -LiteralPath $path -PathType Container)) { continue }

        try {
            $directory = Get-Item -LiteralPath $path -Force
            $expectedPath = [System.IO.Path]::GetFullPath($path)
            if ($directory.FullName -ne $expectedPath -or
                $directory.Parent.FullName -ne $profile.FullName -or
                $profile.Parent.FullName -ne $root.FullName -or
                $directory.Name -cnotin $cacheNames) {
                throw "Đường dẫn ngoài phạm vi dọn: $path"
            }

            $bytes = Measure-Cache $directory
            [pscustomobject]@{
                Profile = $profile.Name
                Cache   = $name
                MiB     = [math]::Round($bytes / 1MB, 1)
                Bytes   = $bytes
                Path    = $directory.FullName
            }
        } catch {
            Write-Warning "Bỏ qua $path. $($_.Exception.Message)"
        }
    }
}

if ($MachineOutput -and !$Clean) {
    $infoCache = $null
    try {
        $statePath = Join-Path $root.FullName 'Local State'
        $infoCache = ([IO.File]::ReadAllText($statePath, [Text.Encoding]::UTF8) | ConvertFrom-Json).profile.info_cache
    } catch {
        # Fall back to the directory name.
    }
    $bytesByProfile = @{}
    foreach ($entry in $entries) {
        $bytesByProfile[$entry.Profile] += $entry.Bytes
    }
    foreach ($profileDirectory in $profiles) {
        if ($profileDirectory.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        $displayName = $profileDirectory.Name
        if ($infoCache) {
            $info = $infoCache.PSObject.Properties[$profileDirectory.Name]
            if ($info -and $info.Value.name) { $displayName = [string]$info.Value.name }
        }
        [pscustomobject]@{
            Profile = $profileDirectory.Name
            DisplayName = $displayName
            Bytes = [long]$bytesByProfile[$profileDirectory.Name]
        }
    }
    return
}

if (!$entries) {
    if ($MachineOutput) {
        [pscustomobject]@{ RemovedBytes = [long]0; Failed = 0 }
        return
    }
    Write-Host 'Không tìm thấy thư mục cache phù hợp.'
    return
}
if (!$MachineOutput) { $entries | Format-Table Profile, Cache, MiB -AutoSize }
$total = ($entries | Measure-Object -Property Bytes -Sum).Sum
if (!$MachineOutput) { Write-Host ('Tổng dung lượng file cache: {0:N2} GiB' -f ($total / 1GB)) }

if (!$Clean) {
    Write-Host "Đây là chế độ xem trước. Đóng $Browser rồi chạy lại với -Clean để dọn."
    return
}

$removedBytes = [long]0
$failed = 0
foreach ($entry in $entries) {
    Assert-BrowserClosed
    if (!$PSCmdlet.ShouldProcess($entry.Path, 'Xóa thư mục cache')) { continue }

    try {
        $directory = Get-Item -LiteralPath $entry.Path -Force
        for ($ancestor = $directory; $null -ne $ancestor; $ancestor = $ancestor.Parent) {
            Assert-RegularDirectory $ancestor
        }
        $bytes = Measure-Cache $directory
        Remove-Item -LiteralPath $entry.Path -Recurse -Force
        $removedBytes += $bytes
    } catch {
        $failed++
        Write-Warning "Dọn chưa xong ở $($entry.Path). $($_.Exception.Message)"
    }
}
if ($MachineOutput) {
    [pscustomobject]@{ RemovedBytes = $removedBytes; Failed = $failed }
    return
}
Write-Host ('Đã dọn khoảng {0:N2} GiB dung lượng file cache.' -f ($removedBytes / 1GB))
if ($failed -gt 0) {
    throw "$failed thư mục chưa dọn xong. Xem cảnh báo ở trên."
}
