# Windows PowerShell 5.1, STA
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
# Assign the hosted window its own taskbar identity before creating any UI.
if (-not ('KSweep.TaskbarIdentity' -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace KSweep
{
    public static class TaskbarIdentity
    {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        private static extern int SetCurrentProcessExplicitAppUserModelID(string appId);

        public static void Initialize()
        {
            Marshal.ThrowExceptionForHR(
                SetCurrentProcessExplicitAppUserModelID("congthuc007.KSweep"));
        }
    }
}
"@
}
[KSweep.TaskbarIdentity]::Initialize()
[Windows.Forms.Application]::EnableVisualStyles()
$backend = Join-Path $PSScriptRoot 'CacheCleaner.ps1'
if (!(Test-Path -LiteralPath $backend -PathType Leaf)) {
    [void][Windows.Forms.MessageBox]::Show('Thiếu CacheCleaner.ps1 trong cùng thư mục.', 'KSweep')
    exit 1
}

$form = New-Object Windows.Forms.Form -Property @{
    Text = 'KSweep v1.2.0'
    StartPosition = 'CenterScreen'
    MinimumSize = [Drawing.Size]::new(850, 500)
    ClientSize = [Drawing.Size]::new(980, 550)
    Font = [Drawing.Font]::new('Segoe UI', 10)
    AutoScaleMode = 'Dpi'
    KeyPreview = $true
}
$iconPath = Join-Path $PSScriptRoot 'KSweep.ico'
if (!(Test-Path -LiteralPath $iconPath -PathType Leaf)) {
    $iconPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\KSweep.ico'
}
if (Test-Path -LiteralPath $iconPath -PathType Leaf) {
    $form.Icon = [Drawing.Icon]::new($iconPath)
}

$layout = New-Object Windows.Forms.TableLayoutPanel -Property @{
    Dock = 'Fill'
    Padding = [Windows.Forms.Padding]::new(16)
    ColumnCount = 1
    RowCount = 5
}
[void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute', 74))
[void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute', 43))
[void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new('Percent', 100))
[void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute', 44))
[void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute', 45))
$form.Controls.Add($layout)

$header = New-Object Windows.Forms.Label -Property @{
    Dock = 'Fill'
    Text = @('Chọn profile cần dọn cache.', 'Cookie, đăng nhập và dữ liệu phiên được giữ nguyên.', 'Dọn file tạm: chỉ xóa file Windows Temp đã cũ hơn 7 ngày.') -join [Environment]::NewLine
}
$layout.Controls.Add($header, 0, 0)
$list = New-Object Windows.Forms.ListView -Property @{
    Dock = 'Fill'
    View = 'Details'
    CheckBoxes = $true
    FullRowSelect = $true
    GridLines = $true
}
[void]$list.Columns.Add('Tên profile', 275)
[void]$list.Columns.Add('Thư mục profile', 150)
[void]$list.Columns.Add('Cache có thể dọn', 155)
[void]$list.Columns.Add('Trạng thái', 350)
$layout.Controls.Add($list, 0, 2)

$status = New-Object Windows.Forms.Label -Property @{ Dock = 'Fill'; TextAlign = 'MiddleLeft'; AutoEllipsis = $true }
$layout.Controls.Add($status, 0, 3)
$actions = New-Object Windows.Forms.FlowLayoutPanel -Property @{ Dock = 'Fill'; WrapContents = $false; AutoScroll = $true }
$layout.Controls.Add($actions, 0, 4)
$selectAll = New-Object Windows.Forms.Button -Property @{ Text = 'Chọn tất cả (Ctrl+A)'; AutoSize = $true }
$clearSelection = New-Object Windows.Forms.Button -Property @{ Text = 'Bỏ chọn (Ctrl+Shift+A)'; AutoSize = $true }
$reload = New-Object Windows.Forms.Button -Property @{ Text = 'Quét lại'; AutoSize = $true }
$cleanButton = New-Object Windows.Forms.Button -Property @{ Text = 'Xóa cache đã chọn'; AutoSize = $true; Enabled = $false }
$tempButton = New-Object Windows.Forms.Button -Property @{ Text = 'Dọn file tạm'; AutoSize = $true }
$closeBrowserButton = New-Object Windows.Forms.Button -Property @{ Text = 'Tắt hết Chrome'; AutoSize = $true }
$quickSelect = New-Object Windows.Forms.FlowLayoutPanel -Property @{ Dock = 'Fill'; WrapContents = $false; AutoScroll = $true }
$layout.Controls.Add($quickSelect, 0, 1)
$browserPicker = New-Object Windows.Forms.ComboBox -Property @{
    DropDownStyle = 'DropDownList'
    Width = 125
    AccessibleName = 'Trình duyệt'
}
[void]$browserPicker.Items.AddRange(@('Chrome', 'Edge', 'NVIDIA'))
$browserPicker.SelectedIndex = 0
$quickSelect.Controls.AddRange(@($browserPicker, $selectAll, $clearSelection, $reload))
$actions.Controls.AddRange(@($closeBrowserButton, $cleanButton, $tempButton))
$buttons = @($selectAll, $clearSelection, $reload, $closeBrowserButton, $cleanButton, $tempButton)

$job = @{ Worker = $null; Pending = $null; Mode = ''; Note = '' }
$timer = New-Object Windows.Forms.Timer -Property @{ Interval = 180 }

function Format-CacheSize([long]$Bytes) {
    if ($Bytes -eq 0) { return '0 MiB' }
    if ($Bytes -lt 1MB) { return '< 1 MiB' }
    if ($Bytes -lt 1GB) { return ('{0:N1} MiB' -f ($Bytes / 1MB)) }
    return ('{0:N2} GiB' -f ($Bytes / 1GB))
}
function Update-Selection {
    if ($job.Worker) { return }
    $selected = @($list.CheckedItems | Where-Object { $_.Tag.Bytes -gt 0 -and (!$_.Tag.PSObject.Properties['CanClean'] -or $_.Tag.CanClean) })
    $total = ($selected | ForEach-Object { $_.Tag.Bytes } | Measure-Object -Sum).Sum
    $cleanButton.Enabled = $selected.Count -gt 0
    $status.Text = ('{0} Đã chọn {1} mục ({2}).' -f $job.Note, $selected.Count, (Format-CacheSize $total)).Trim()
}
function Start-CacheJob([string]$Mode, [string[]]$SelectedProfiles) {
    $worker = [PowerShell]::Create()
    try {
        [void]$worker.AddCommand($backend).AddParameter('MachineOutput', $true)
        if ($browserPicker.SelectedItem -eq 'NVIDIA' -and $Mode -in @('Scan','Clean')) {
            [void]$worker.AddParameter('Nvidia', $true)
        } else {
            $browser = if ($browserPicker.SelectedItem -eq 'Edge') { 'Edge' } else { 'Chrome' }
            [void]$worker.AddParameter('Browser', $browser)
        }
        if ($Mode -eq 'Clean') {
            [void]$worker.AddParameter('Clean', $true)
            if ($browserPicker.SelectedItem -eq 'NVIDIA') {
                [void]$worker.AddParameter('NvidiaPackage', $SelectedProfiles)
            } else {
                [void]$worker.AddParameter('ProfileName', $SelectedProfiles)
            }
        } elseif ($Mode -eq 'Temp') {
            [void]$worker.AddParameter('Temp', $true).AddParameter('Clean', $true)
        } elseif ($Mode -eq 'CloseBrowser') {
            [void]$worker.AddParameter('CloseBrowser', $true)
        }
        $job.Pending = $worker.BeginInvoke()
        $job.Worker = $worker
        $job.Mode = $Mode
        $browserPicker.Enabled = $false
        $list.Enabled = $false
        foreach ($button in $buttons) { $button.Enabled = $false }
        $status.Text = switch ($Mode) {
            'Clean' { 'Đang dọn cache…' }
            'Temp' { 'Đang dọn file tạm Windows…' }
            'CloseBrowser' { "Đang thoát $($browserPicker.SelectedItem)…" }
            default { "Đang quét $($browserPicker.SelectedItem)…" }
        }
        $timer.Start()
    } catch {
        $worker.Dispose()
        $job.Worker = $null
        $status.Text = $_.Exception.Message
    }
}
$timer.Add_Tick({
    if (!$job.Pending.IsCompleted) { return }
    $timer.Stop()
    $worker = $job.Worker
    $mode = $job.Mode
    $errorText = ''
    try {
        $result = @($worker.EndInvoke($job.Pending))
        if ($worker.HadErrors) {
            $errorText = ($worker.Streams.Error | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        }
    } catch {
        $errorText = $_.Exception.Message
    } finally {
        $warnings = ($worker.Streams.Warning | ForEach-Object { $_.Message }) -join [Environment]::NewLine
        $worker.Dispose()
        $job.Worker = $null
        $job.Pending = $null
    }

    if ($errorText -or $warnings) {
        $detail = (@($errorText, $warnings) | Where-Object { $_ }) -join [Environment]::NewLine
        [void][Windows.Forms.MessageBox]::Show($form, $detail, 'KSweep', 'OK', 'Warning')
    }
    if ($mode -eq 'Clean' -and !$errorText) {
        $job.Note = 'Đã dọn khoảng {0}.' -f (Format-CacheSize $result[0].RemovedBytes)
        if ($result[0].Failed -gt 0) { $job.Note += ' Một số mục chưa dọn được; xem cảnh báo.' }
        Start-CacheJob Scan
        return
    }
    if ($mode -eq 'Scan' -and !$errorText) {
        $list.BeginUpdate()
        try {
            $list.Items.Clear()
            foreach ($profileRow in ($result | Sort-Object Bytes -Descending)) {
                $item = [Windows.Forms.ListViewItem]::new([string]$profileRow.DisplayName)
                [void]$item.SubItems.Add([string]$profileRow.Profile)
                [void]$item.SubItems.Add((Format-CacheSize $profileRow.Bytes))
                [void]$item.SubItems.Add([string]$profileRow.Reason)
                if ($profileRow.PSObject.Properties['CanClean'] -and !$profileRow.CanClean) {
                    $item.ForeColor = [Drawing.Color]::DimGray
                }
                $item.Tag = $profileRow
                [void]$list.Items.Add($item)
            }
        } finally {
            $list.EndUpdate()
        }
    }
    if ($mode -eq 'CloseBrowser' -and !$errorText) {
        if ($result[0].Remaining -gt 0) {
            $job.Note = 'Còn {0} tiến trình {1} đang chạy.' -f $result[0].Remaining, $browserPicker.SelectedItem
        } else {
            $job.Note = "$($browserPicker.SelectedItem) đã thoát hoàn toàn."
        }
    }
    if ($mode -eq 'Temp' -and !$errorText) {
        $summary = $result[0]
        $job.Note = 'File tạm: đã xóa {0} file ({1}).' -f $summary.RemovedFiles, (Format-CacheSize $summary.RemovedBytes)
        if ($summary.Skipped -gt 0) {
            $job.Note += ' Bỏ qua {0} mục.' -f $summary.Skipped
        }
    }
    if ($errorText) {
        $job.Note = if ($mode -eq 'Clean') { 'Dọn cache chưa hoàn tất.' } elseif ($mode -eq 'Temp') { 'Dọn file tạm chưa hoàn tất.' } elseif ($mode -eq 'CloseBrowser') { "Chưa tắt hết $($browserPicker.SelectedItem)." } else { 'Quét chưa thành công.' }
    } elseif ($mode -eq 'Scan' -and $list.Items.Count -eq 0) {
        $job.Note = "Không tìm thấy mục $($browserPicker.SelectedItem) để quét."
    }
    $browserPicker.Enabled = $true
    $list.Enabled = $true
    foreach ($button in $buttons) { $button.Enabled = $true }
    $closeBrowserButton.Enabled = $browserPicker.SelectedItem -ne 'NVIDIA'
    Update-Selection
})
$list.Add_ItemCheck({
    param($sender, $eventArgs)
    $row = $list.Items[$eventArgs.Index].Tag
    if ($row -and $row.PSObject.Properties['CanClean'] -and !$row.CanClean) {
        $eventArgs.NewValue = [Windows.Forms.CheckState]::Unchecked
    }
})
$list.Add_ItemChecked({ Update-Selection })
$selectAll.Add_Click({ foreach ($item in $list.Items) { $item.Checked = $item.Tag.Bytes -gt 0 -and (!$item.Tag.PSObject.Properties['CanClean'] -or $item.Tag.CanClean) } })
$clearSelection.Add_Click({ foreach ($item in $list.Items) { $item.Checked = $false } })
$reload.Add_Click({ $job.Note = ''; Start-CacheJob Scan })
$browserPicker.Add_SelectedIndexChanged({
    if ($job.Worker) { return }
    $list.Items.Clear()
    $nvidiaMode = $browserPicker.SelectedItem -eq 'NVIDIA'
    $closeBrowserButton.Text = if ($nvidiaMode) { 'Tắt trình duyệt' } else { "Tắt hết $($browserPicker.SelectedItem)" }
    $closeBrowserButton.Enabled = !$nvidiaMode
    $list.Columns[0].Text = if ($nvidiaMode) { 'Gói cài NVIDIA' } else { 'Tên profile' }
    $list.Columns[1].Text = if ($nvidiaMode) { 'Mã gói' } else { 'Thư mục profile' }
    $cleanButton.Text = if ($nvidiaMode) { 'Xóa gói đã chọn' } else { 'Xóa cache đã chọn' }
    $header.Text = if ($nvidiaMode) {
        'Chọn gói NVIDIA đủ điều kiện để dọn. Đóng NVIDIA App và trình cài đặt trước khi quét.' + [Environment]::NewLine +
        'Bộ cài và thư mục giải nén được gom theo gói; gói chưa rõ trạng thái được khóa.' + [Environment]::NewLine +
        'Sau khi dọn, cài lại driver có thể cần tải lại bộ cài.'
    } else {
        'Chọn profile cần dọn cache.' + [Environment]::NewLine +
        'Cookie, đăng nhập và dữ liệu phiên được giữ nguyên.' + [Environment]::NewLine +
        'Dọn file tạm: chỉ xóa file Windows Temp đã cũ hơn 7 ngày.'
    }
    $job.Note = ''
    Start-CacheJob Scan
})
$cleanButton.Add_Click({
    $selected = @($list.CheckedItems | Where-Object { $_.Tag.Bytes -gt 0 -and (!$_.Tag.PSObject.Properties['CanClean'] -or $_.Tag.CanClean) } | ForEach-Object { $_.Tag.Profile })
    if ($selected.Count -eq 0) { return }
    if ($browserPicker.SelectedItem -eq 'NVIDIA') {
        $answer = [Windows.Forms.MessageBox]::Show(
            $form, 'Xóa bộ cài và dữ liệu giải nén của các gói NVIDIA đã chọn? Nếu cần cài lại driver, NVIDIA App có thể phải tải lại.',
            'Dọn gói tải NVIDIA', 'YesNo', 'Question', 'Button2')
        if ($answer -eq 'Yes') { $job.Note = ''; Start-CacheJob Clean $selected }
        return
    }
    $sessionId = [Diagnostics.Process]::GetCurrentProcess().SessionId
    $browser = [string]$browserPicker.SelectedItem
    $processName = if ($browser -eq 'Edge') { 'msedge' } else { 'chrome' }
    if (Get-Process -Name $processName -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $sessionId }) {
        [void][Windows.Forms.MessageBox]::Show(
            $form, "$browser có thể đang chạy nền. Dùng nút Tắt hết $browser rồi bấm Xóa cache đã chọn.",
            "$browser đang chạy", 'OK', 'Information'
        )
        return
    }
    $job.Note = ''
    Start-CacheJob Clean $selected
})
$form.Add_KeyDown({
    param($sender, $eventArgs)
    if (!$job.Worker -and $eventArgs.Control -and $eventArgs.KeyCode -eq 'A') {
        if ($eventArgs.Shift) { $clearSelection.PerformClick() } else { $selectAll.PerformClick() }
        $eventArgs.SuppressKeyPress = $true
    }
})
$closeBrowserButton.Add_Click({
    $browser = [string]$browserPicker.SelectedItem
    $answer = [Windows.Forms.MessageBox]::Show(
        $form,
        "Thoát mọi cửa sổ $browser trong phiên Windows này? Tiến trình còn chạy sau khi thoát sẽ bị buộc tắt. Hãy lưu nội dung đang nhập hoặc tải dở trước khi chọn Yes.",
        "Tắt hết $browser", 'YesNo', 'Warning', 'Button2'
    )
    if ($answer -eq 'Yes') { $job.Note = ''; Start-CacheJob CloseBrowser }
})
$tempButton.Add_Click({ $job.Note = ''; Start-CacheJob Temp })
$form.Add_Shown({ Start-CacheJob Scan })
$form.Add_FormClosing({ param($sender, $eventArgs) if ($job.Worker) { $eventArgs.Cancel = $true } })
try {
    [void]$form.ShowDialog()
} finally {
    $timer.Dispose()
    $form.Dispose()
}
