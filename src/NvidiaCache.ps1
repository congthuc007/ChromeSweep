# NVIDIA App download-cache support. Only grd/crd package directories are eligible.
function Get-NvidiaFrameworkRoot {
    Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'NVIDIA Corporation\NVIDIA App\UpdateFramework'
}

function Assert-NvidiaPath([string]$Path) {
    $root = [IO.Path]::GetFullPath((Join-Path (Get-NvidiaFrameworkRoot) 'ota-artifacts')).TrimEnd('\')
    $full = [IO.Path]::GetFullPath($Path)
    if (!$full.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Đường dẫn ngoài vùng gói tải NVIDIA.'
    }
    $relative = $full.Substring($root.Length + 1)
    if ($relative -notmatch '^(grd|crd)\\(post-processing\\)?[a-fA-F0-9]{32}$') {
        throw 'Tên thư mục gói NVIDIA không hợp lệ.'
    }
    $item = Get-Item -LiteralPath $full -Force
    if (!$item.PSIsContainer) { throw 'Gói NVIDIA phải là thư mục.' }
    for ($parent = $item; $null -ne $parent; $parent = $parent.Parent) {
        Assert-RegularDirectory $parent
    }
    return $item
}

function Get-NvidiaInstalledVersion {
    $versions = @(
        Get-CimInstance Win32_VideoController -ErrorAction Stop |
        Where-Object { $_.Name -match 'NVIDIA' -and $_.DriverVersion -match '^\d+\.\d+\.\d+\.\d+$' } |
        ForEach-Object {
            $windowsVersion = [version]$_.DriverVersion
            $number = ($windowsVersion.Build % 10) * 10000 + $windowsVersion.Revision
            [version]('{0}.{1:00}' -f [math]::Floor($number / 100), ($number % 100))
        }
    )
    if (!$versions.Count) { return $null }
    # All NVIDIA adapters must be on this version or newer.
    return $versions | Sort-Object | Select-Object -First 1
}

function Get-NvidiaBusyReason {
    $processes = @(Get-CimInstance Win32_Process -ErrorAction Stop)
    foreach ($process in $processes) {
        if ($process.Name -match '^(NVIDIA App|NVIDIAApp|NvBackend|NVIDIA Installer|nvsetup|setup|NvidiaAppSetup.*)\.exe$') {
            return 'Đóng NVIDIA App và chờ trình cài đặt kết thúc rồi quét lại.'
        }
        if ($process.ExecutablePath -and $process.ExecutablePath -like '*\UpdateFramework\ota-artifacts\*') {
            return 'Một gói NVIDIA đang được sử dụng.'
        }
    }
    return ''
}

function Get-NvidiaPackages {
    $framework = Get-NvidiaFrameworkRoot
    $installed = Get-NvidiaInstalledVersion
    $busy = Get-NvidiaBusyReason
    foreach ($channel in 'grd', 'crd') {
        $channelRoot = Join-Path $framework "ota-artifacts\$channel"
        if (!(Test-Path -LiteralPath $channelRoot -PathType Container)) { continue }

        $downloadRows = @()
        $metadataReadable = $true
        try {
            $metadataPath = Join-Path $framework "status\$channel\download.json"
            $downloadRows = @([IO.File]::ReadAllText($metadataPath) | ConvertFrom-Json)
        } catch { $metadataReadable = $false }

        $ids = @(
            Get-ChildItem -LiteralPath $channelRoot -Directory -Force |
                Where-Object Name -Match '^[a-fA-F0-9]{32}$' | Select-Object -ExpandProperty Name
            $postRoot = Join-Path $channelRoot 'post-processing'
            if (Test-Path -LiteralPath $postRoot -PathType Container) {
                Get-ChildItem -LiteralPath $postRoot -Directory -Force |
                    Where-Object Name -Match '^[a-fA-F0-9]{32}$' | Select-Object -ExpandProperty Name
            }
        ) | Sort-Object -Unique

        foreach ($id in $ids) {
            $paths = @()
            $bytes = [long]0
            $versions = @()
            $reason = ''
            try {
                foreach ($relative in @($id, "post-processing\$id")) {
                    $path = Join-Path $channelRoot $relative
                    if (!(Test-Path -LiteralPath $path -PathType Container)) { continue }
                    $directory = Assert-NvidiaPath $path
                    $bytes += Measure-Cache $directory
                    $paths += $directory.FullName
                    foreach ($exe in Get-ChildItem -LiteralPath $path -File -Filter '*.exe') {
                        if ($exe.Name -match '^(\d{3}\.\d{2})-.*\.exe$') { $versions += $Matches[1] }
                    }
                    $config = Join-Path $path 'setup.cfg'
                    if (Test-Path -LiteralPath $config -PathType Leaf) {
                        $match = [regex]::Match([IO.File]::ReadAllText($config), '<setup\b[^>]*\bversion="(\d{3}\.\d{2})"')
                        if ($match.Success) { $versions += $match.Groups[1].Value }
                    }
                }
            } catch {
                $reason = 'Không đọc được gói hoặc có đường dẫn liên kết.'
            }

            $versions = @($versions | Sort-Object -Unique)
            $packageVersion = if ($versions.Count -eq 1) { [version]$versions[0] } else { $null }
            $download = @($downloadRows | Where-Object { $_.taskId -eq $id })
            if (!$reason) {
                if (!$installed) { $reason = 'Chưa xác định được driver NVIDIA đã cài.' }
                elseif (!$packageVersion) { $reason = 'Chưa xác định chắc phiên bản gói.' }
                elseif ($packageVersion -gt $installed) { $reason = "Gói mới hơn driver đã cài $installed." }
                elseif (!$metadataReadable -or $download.Count -ne 1 -or
                    $download[0].state -ne 8 -or $download[0].percentComplete -ne 100 -or
                    $null -eq $download[0].errorCode -or $download[0].errorCode -ne 0 -or
                    [string]$download[0].version -ne [string]$versions[0]) {
                    $reason = 'Trạng thái tải chưa xác nhận hoàn tất.'
                } elseif ($busy) { $reason = $busy }
                else { $reason = "Có thể dọn; driver đã cài $installed." }
            }
            $canClean = $reason.StartsWith('Có thể dọn;')
            $label = if ($channel -eq 'grd') { 'Game Ready' } else { 'Studio' }
            $versionLabel = if ($packageVersion) { $versions[0] } else { 'Không rõ phiên bản' }
            [pscustomobject]@{
                Profile = "$channel/$id"
                DisplayName = "$label $versionLabel"
                Bytes = $bytes
                CanClean = $canClean
                Reason = $reason
                Paths = $paths
            }
        }
    }
}

function Remove-NvidiaPackages([string[]]$SelectedIds) {
    if (!$SelectedIds) { throw 'Chọn gói NVIDIA cần dọn trước.' }
    $removed = [long]0
    $failed = 0
    foreach ($id in $SelectedIds) {
        if ($id -notmatch '^(grd|crd)/[a-fA-F0-9]{32}$') { throw 'Mã gói NVIDIA không hợp lệ.' }
        # Refresh installed version, updater processes and completion state for every package.
        $package = @(Get-NvidiaPackages | Where-Object Profile -EQ $id)
        if ($package.Count -ne 1 -or !$package[0].CanClean) {
            $failed++
            Write-Warning "Bỏ qua $id. Gói không còn đủ điều kiện dọn."
            continue
        }
        foreach ($path in $package[0].Paths) {
            try {
                $busy = Get-NvidiaBusyReason
                if ($busy) { throw $busy }
                $directory = Assert-NvidiaPath $path
                $size = Measure-Cache $directory
                if ($PSCmdlet.ShouldProcess($directory.FullName, 'Xóa gói tải NVIDIA')) {
                    Remove-Item -LiteralPath $directory.FullName -Recurse -Force
                    $removed += $size
                }
            } catch {
                $failed++
                Write-Warning "Không dọn được $path. $($_.Exception.Message)"
            }
        }
    }
    [pscustomobject]@{ RemovedBytes = $removed; Failed = $failed }
}
