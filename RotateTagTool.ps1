Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'

$script:AppDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ToolsDir = Join-Path $script:AppDir 'tools'
$script:FfmpegPath = Join-Path $script:ToolsDir 'ffmpeg.exe'
$script:FfprobePath = Join-Path $script:ToolsDir 'ffprobe.exe'
if (-not (Test-Path -LiteralPath $script:FfmpegPath)) { $script:FfmpegPath = 'ffmpeg.exe' }
if (-not (Test-Path -LiteralPath $script:FfprobePath)) { $script:FfprobePath = 'ffprobe.exe' }

$script:VideoExtensions = @(
    '.mp4', '.m4v', '.mov', '.mkv', '.avi', '.wmv', '.flv', '.webm', '.ts', '.mts', '.m2ts', '.mpg', '.mpeg', '.3gp'
)
$script:Jobs = New-Object System.Collections.Generic.List[object]
$script:Rows = @{}
$script:IsRunning = $false
$script:StopRequested = $false
$script:SelectedRotation = 90
$script:LastFfmpegError = ''
$script:LogPath = Join-Path $script:AppDir 'rotate_log.txt'
$script:Lang = 'KR'
$script:StatusKeys = @{
    '대기' = 'Waiting'
    '진행중' = 'Running'
    '완료' = 'Done'
    '실패' = 'Failed'
    '중지됨' = 'Stopped'
    '건너뜀' = 'Skipped'
}
$script:T = @{
    KR = @{
        WindowTitle = '영상 회전 태그 도구'
        HeaderTitle = '영상 회전 태그 도구'
        HeaderSub = '재인코딩 없이 회전 메타데이터를 빠르게 추가합니다'
        AddFiles = '파일 추가'
        AddFolder = '폴더 추가'
        RemoveSelected = '선택 삭제'
        Clear = '비우기'
        SelectToggle = '전체 선택/해제'
        LanguageLabel = '언어'
        LangButton = 'En/Kr'
        AddedFiles = '추가된 파일'
        FileName = '파일명'
        RotationColumn = '회전'
        Status = '상태'
        Rotation = '회전 작업'
        Output = '출력 위치'
        SaveOriginal = '원본 폴더에 저장'
        UseOutput = '출력 폴더 지정'
        Browse = '찾기'
        Progress = '작업 진행'
        Start = '시작'
        Stop = '중지'
        NeedOutputFolder = '출력 폴더를 지정해 주세요.'
        OutputFolderMissing = '출력 폴더가 존재하지 않습니다.'
        NeedFfmpeg = "ffmpeg.exe를 찾을 수 없습니다.`r`n`r`ntools 폴더에 ffmpeg.exe를 넣어 주세요."
    }
    EN = @{
        WindowTitle = 'Video Rotation Tag Tool'
        HeaderTitle = 'Video Rotation Tag Tool'
        HeaderSub = 'Quickly add rotation metadata without re-encoding'
        AddFiles = 'Add Files'
        AddFolder = 'Add Folder'
        RemoveSelected = 'Remove'
        Clear = 'Clear'
        SelectToggle = 'Select/Clear All'
        LanguageLabel = 'Language'
        LangButton = 'En/Kr'
        AddedFiles = 'Added Files'
        FileName = 'File'
        RotationColumn = 'Rotation'
        Status = 'Status'
        Rotation = 'Rotation'
        Output = 'Output'
        SaveOriginal = 'Save next to original'
        UseOutput = 'Use output folder'
        Browse = 'Browse'
        Progress = 'Progress'
        Start = 'Start'
        Stop = 'Stop'
        NeedOutputFolder = 'Please choose an output folder.'
        OutputFolderMissing = 'The output folder does not exist.'
        NeedFfmpeg = "ffmpeg.exe was not found.`r`n`r`nPlace ffmpeg.exe in the tools folder."
    }
}

function Tr {
    param([string]$Key)
    return $script:T[$script:Lang][$Key]
}

function Get-StatusText {
    param([string]$Status)
    if ($script:Lang -eq 'EN' -and $script:StatusKeys.ContainsKey($Status)) {
        return $script:StatusKeys[$Status]
    }
    return $Status
}

function Apply-Language {
    $form.Text = Tr 'WindowTitle'
    $headerTitle.Text = Tr 'HeaderTitle'
    $headerSub.Text = Tr 'HeaderSub'
    $addFileButton.Text = Tr 'AddFiles'
    $addFolderButton.Text = Tr 'AddFolder'
    $removeButton.Text = Tr 'RemoveSelected'
    $clearButton.Text = Tr 'Clear'
    $selectToggleButton.Text = Tr 'SelectToggle'
    $languageLabel.Text = Tr 'LanguageLabel'
    $langButton.Text = Tr 'LangButton'
    $fileLabel.Text = Tr 'AddedFiles'
    $fileGrid.Columns[0].HeaderText = Tr 'FileName'
    $fileGrid.Columns[1].HeaderText = Tr 'RotationColumn'
    $fileGrid.Columns[2].HeaderText = Tr 'Status'
    $rotationGroup.Text = Tr 'Rotation'
    $rotation90.Text = if ($script:Lang -eq 'EN') { '90°' } else { '90도' }
    $rotation270.Text = if ($script:Lang -eq 'EN') { '270°' } else { '270도' }
    $rotation180.Text = if ($script:Lang -eq 'EN') { '180°' } else { '180도' }
    $outputGroup.Text = Tr 'Output'
    $outputOriginal.Text = Tr 'SaveOriginal'
    $outputCustom.Text = Tr 'UseOutput'
    $browseOutput.Text = Tr 'Browse'
    $progressLabel.Text = Tr 'Progress'
    $startButton.Text = Tr 'Start'
    $stopButton.Text = Tr 'Stop'

    for ($i = 0; $i -lt $script:Jobs.Count; $i++) {
        $job = $script:Jobs[$i]
        if ($i -lt $fileGrid.Rows.Count) {
            $fileGrid.Rows[$i].Cells[1].Value = [string]$job.Rotation
            $fileGrid.Rows[$i].Cells[2].Value = Get-StatusText $job.Status
        }
        if ($script:Rows.ContainsKey($job.Path)) {
            $row = $script:Rows[$job.Path]
            $displayMessage = Normalize-ErrorMessage $job.Message ''
            if ($displayMessage) {
                $row.Status.Text = "$(Get-StatusText $job.Status): $displayMessage"
            } else {
                $row.Status.Text = Get-StatusText $job.Status
            }
        }
    }
}

function Set-SelectedRotation {
    param([int]$Rotation)
    if ($script:IsRunning) { return }
    $rows = @($fileGrid.SelectedRows)
    if ($rows.Count -eq 0) { return }
    foreach ($row in $rows) {
        $job = $row.Tag
        if ($null -eq $job) { continue }
        $job.Rotation = $Rotation
        $row.Cells[1].Value = [string]$Rotation
        if ($job.Status -eq '완료' -or $job.Status -eq '실패' -or $job.Status -eq '중지됨' -or $job.Status -eq '건너뜀') {
            $job.Message = ''
            Set-JobStatus $job '대기' 0 ''
        }
    }
}

function Toggle-SelectAllFiles {
    if ($fileGrid.Rows.Count -eq 0) { return }
    if ($fileGrid.SelectedRows.Count -eq $fileGrid.Rows.Count) {
        $fileGrid.ClearSelection()
    } else {
        $fileGrid.ClearSelection()
        foreach ($row in $fileGrid.Rows) {
            $row.Selected = $true
        }
    }
}

function Set-RotationButtonStyle {
    param([System.Windows.Forms.Button]$Button)
    Set-ButtonStyle $Button
    $Button.Width = 90
    $Button.Height = 30
}

function Set-ButtonStyle {
    param([System.Windows.Forms.Button]$Button)
    $Button.FlatStyle = 'Flat'
    $Button.BackColor = [System.Drawing.Color]::FromArgb(40, 48, 66)
    $Button.ForeColor = [System.Drawing.Color]::White
    $Button.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(84, 104, 138)
    $Button.Font = New-Object System.Drawing.Font('Malgun Gothic', 9, [System.Drawing.FontStyle]::Bold)
}

function Write-Log {
    param([string]$Message)
    try {
        $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
        Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8
    } catch {}
}

function Normalize-ErrorMessage {
    param([object]$Value, [string]$Fallback = '알 수 없는 오류')
    $text = ''
    if ($null -ne $Value) { $text = [string]$Value }
    $text = ($text -replace '\s+', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($text) -or $text -eq 'null' -or $text -eq 'System.Management.Automation.RuntimeException') {
        return $Fallback
    }
    return $text
}

function Quote-ProcessArg {
    param([string]$Value)
    if ($null -eq $Value) { return '""' }
    return '"' + ($Value -replace '"', '\"') + '"'
}

function Join-ProcessArgs {
    param([string[]]$Items)
    return (($Items | ForEach-Object { Quote-ProcessArg $_ }) -join ' ')
}

function Get-ShortPathText {
    param([string]$Path, [int]$Max = 80)
    if ($Path.Length -le $Max) { return $Path }
    $file = [System.IO.Path]::GetFileName($Path)
    $dir = [System.IO.Path]::GetDirectoryName($Path)
    if ($dir.Length -gt 36) { $dir = $dir.Substring(0, 18) + '...' + $dir.Substring($dir.Length - 15) }
    return "$dir\$file"
}

function Get-UniqueOutputPath {
    param(
        [string]$InputPath,
        [int]$Rotation,
        [string]$OutputDir
    )
    $base = [System.IO.Path]::GetFileNameWithoutExtension($InputPath)
    $ext = [System.IO.Path]::GetExtension($InputPath)
    $candidate = Join-Path $OutputDir ("{0}_{1}{2}" -f $base, $Rotation, $ext)
    $i = 1
    while (Test-Path -LiteralPath $candidate) {
        $candidate = Join-Path $OutputDir ("{0}_{1}_{2}{3}" -f $base, $Rotation, $i, $ext)
        $i++
    }
    return $candidate
}

function Invoke-Ui {
    param([scriptblock]$Script)
    if ($form.InvokeRequired) {
        [void]$form.BeginInvoke($Script)
    } else {
        & $Script
    }
}

function Set-JobStatus {
    param(
        [object]$Job,
        [string]$Status,
        [int]$Progress,
        [string]$Message = ''
    )
    $Job.Status = $Status
    $Job.Progress = [Math]::Max(0, [Math]::Min(100, $Progress))
    if ($Message) { $Job.Message = (Normalize-ErrorMessage $Message) }

    Invoke-Ui {
        $idx = $script:Jobs.IndexOf($Job)
        if ($idx -ge 0 -and $idx -lt $fileGrid.Rows.Count) {
            $fileGrid.Rows[$idx].Cells[1].Value = [string]$Job.Rotation
            $fileGrid.Rows[$idx].Cells[2].Value = Get-StatusText $Job.Status
            switch ($Job.Status) {
                '진행중' { $fileGrid.Rows[$idx].Cells[2].Style.ForeColor = [System.Drawing.Color]::DarkOrange }
                '완료' { $fileGrid.Rows[$idx].Cells[2].Style.ForeColor = [System.Drawing.Color]::ForestGreen }
                '실패' { $fileGrid.Rows[$idx].Cells[2].Style.ForeColor = [System.Drawing.Color]::Crimson }
                '건너뜀' { $fileGrid.Rows[$idx].Cells[2].Style.ForeColor = [System.Drawing.Color]::DimGray }
                default { $fileGrid.Rows[$idx].Cells[2].Style.ForeColor = [System.Drawing.Color]::DimGray }
            }
        }
        if ($script:Rows.ContainsKey($Job.Path)) {
            $row = $script:Rows[$Job.Path]
            $row.Progress.Value = $Job.Progress
            $row.Percent.Text = "$($Job.Progress)%"
            $row.Status.Text = Get-StatusText $Job.Status
            $displayMessage = Normalize-ErrorMessage $Job.Message ''
            if ($displayMessage) {
                $row.Status.Text = "$(Get-StatusText $Job.Status): $displayMessage"
            }
            switch ($Job.Status) {
                '진행중' {
                    $row.Progress.ForeColor = [System.Drawing.Color]::DarkOrange
                    $row.Status.ForeColor = [System.Drawing.Color]::DarkOrange
                }
                '완료' {
                    $row.Progress.ForeColor = [System.Drawing.Color]::ForestGreen
                    $row.Status.ForeColor = [System.Drawing.Color]::ForestGreen
                }
                '실패' {
                    $row.Progress.ForeColor = [System.Drawing.Color]::Crimson
                    $row.Status.ForeColor = [System.Drawing.Color]::Crimson
                }
                default {
                    $row.Progress.ForeColor = [System.Drawing.Color]::Gray
                    $row.Status.ForeColor = [System.Drawing.Color]::DimGray
                }
            }
        }
    }
}

function Add-ProgressRow {
    param([object]$Job)

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Width = 720
    $panel.Height = 34
    $panel.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 4)

    $name = New-Object System.Windows.Forms.Label
    $name.Text = [System.IO.Path]::GetFileName($Job.Path)
    $name.Left = 0
    $name.Top = 8
    $name.Width = 245
    $name.Height = 18
    $name.AutoEllipsis = $true
    $name.Font = New-Object System.Drawing.Font('Malgun Gothic', 9)

    $bar = New-Object System.Windows.Forms.ProgressBar
    $bar.Left = 255
    $bar.Top = 7
    $bar.Width = 300
    $bar.Height = 20
    $bar.Minimum = 0
    $bar.Maximum = 100
    $bar.Value = 0

    $percent = New-Object System.Windows.Forms.Label
    $percent.Text = '0%'
    $percent.Left = 565
    $percent.Top = 8
    $percent.Width = 45
    $percent.Height = 18
    $percent.TextAlign = 'MiddleRight'
    $percent.Font = New-Object System.Drawing.Font('Malgun Gothic', 9)

    $status = New-Object System.Windows.Forms.Label
    $status.Text = Get-StatusText '대기'
    $status.Left = 630
    $status.Top = 8
    $status.Width = 70
    $status.Height = 18
    $status.ForeColor = [System.Drawing.Color]::DimGray
    $status.Font = New-Object System.Drawing.Font('Malgun Gothic', 9, [System.Drawing.FontStyle]::Bold)

    $panel.Controls.AddRange(@($name, $bar, $percent, $status))
    $progressPanel.Controls.Add($panel)
    $script:Rows[$Job.Path] = @{
        Panel = $panel
        Name = $name
        Progress = $bar
        Percent = $percent
        Status = $status
    }
}

function Add-FileJob {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($script:VideoExtensions -notcontains $ext) { return }
    foreach ($job in $script:Jobs) {
        if ([string]::Equals($job.Path, $Path, [System.StringComparison]::OrdinalIgnoreCase)) { return }
    }

    $job = [pscustomobject]@{
        Path = $Path
        Status = '대기'
        Progress = 0
        Output = ''
        Message = ''
        Rotation = 0
    }
    $script:Jobs.Add($job)
    $rowIndex = $fileGrid.Rows.Add((Get-ShortPathText $Path), [string]$job.Rotation, (Get-StatusText '대기'))
    $fileGrid.Rows[$rowIndex].Tag = $job
    Add-ProgressRow $job
}

function Add-FolderJobs {
    param([string]$Folder)
    if (-not (Test-Path -LiteralPath $Folder -PathType Container)) { return }
    Get-ChildItem -LiteralPath $Folder -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $script:VideoExtensions -contains $_.Extension.ToLowerInvariant() } |
        ForEach-Object { Add-FileJob $_.FullName }
}

function Get-DurationSeconds {
    param([string]$Path)
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $script:FfprobePath
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $probeArgs = @('-v', 'error', '-show_entries', 'format=duration', '-of', 'default=noprint_wrappers=1:nokey=1', $Path)
        $psi.Arguments = Join-ProcessArgs -Items $probeArgs
        $p = [System.Diagnostics.Process]::Start($psi)
        $out = $p.StandardOutput.ReadToEnd().Trim()
        $p.WaitForExit()
        if ($p.ExitCode -eq 0 -and $out) {
            $value = 0.0
            if ([double]::TryParse($out, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$value)) {
                return $value
            }
        }
    } catch {}
    return 0.0
}

function Run-FfmpegRotation {
    param(
        [object]$Job,
        [int]$Rotation,
        [string]$OutputPath
    )

    $duration = Get-DurationSeconds $Job.Path
    Write-Log "START input=[$($Job.Path)] rotation=[$Rotation] output=[$OutputPath]"
    $errors = New-Object System.Collections.Generic.List[string]
    $result = Invoke-FfmpegRotationMode $Job $Rotation $OutputPath $duration 'display'
    if (-not $result) {
        if ($script:LastFfmpegError) { $errors.Add($script:LastFfmpegError) }
        if (Test-Path -LiteralPath $OutputPath) {
            Remove-Item -LiteralPath $OutputPath -Force -ErrorAction SilentlyContinue
        }
        $result = Invoke-FfmpegRotationMode $Job $Rotation $OutputPath $duration 'metadata'
        if (-not $result -and $script:LastFfmpegError) { $errors.Add($script:LastFfmpegError) }
    }
    if (-not $result) {
        $msg = ($errors | Where-Object { $_ } | Select-Object -Last 1)
        $msg = Normalize-ErrorMessage $msg 'ffmpeg 처리 실패'
        Write-Log "FAIL input=[$($Job.Path)] error=[$msg]"
        throw $msg
    }
    Write-Log "DONE input=[$($Job.Path)] output=[$OutputPath]"
}

function Invoke-FfmpegRotationMode {
    param(
        [object]$Job,
        [int]$Rotation,
        [string]$OutputPath,
        [double]$Duration,
        [string]$Mode
    )

    $script:LastFfmpegError = ''
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $script:FfmpegPath
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $args = @('-hide_banner', '-v', 'error', '-nostdin', '-y')
    if ($Mode -eq 'display') {
        $args += @('-display_rotation:v:0', ([string]$Rotation))
    }
    $args += @(
        '-i', $Job.Path,
        '-c:v', 'copy',
        '-c:a', 'copy',
        '-metadata:s:v:0', "rotate=$Rotation",
        '-sn',
        '-map_metadata', '-1',
        '-map_chapters', '-1',
        '-progress', 'pipe:1',
        '-nostats',
        $OutputPath
    )
    Write-Log "FFMPEG mode=[$Mode] args=[$($args -join ' | ')]"
    $psi.Arguments = Join-ProcessArgs -Items $args
    Write-Log "FFMPEG commandline=[$($psi.Arguments)]"

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()

    while (-not $proc.HasExited) {
        [System.Windows.Forms.Application]::DoEvents()
        if ($script:StopRequested) {
            try { $proc.Kill() } catch {}
            throw '사용자 중지'
        }
        $line = $proc.StandardOutput.ReadLine()
        if ($null -eq $line) {
            Start-Sleep -Milliseconds 80
            continue
        }
        if ($line -match '^out_time_ms=(\d+)') {
            if ($Duration -gt 0) {
                $pct = [int][Math]::Min(99, [Math]::Round((([double]$Matches[1] / 1000000.0) / $Duration) * 100))
                Set-JobStatus $Job '진행중' $pct
            } elseif ($Job.Progress -lt 50) {
                Set-JobStatus $Job '진행중' 50
            }
        } elseif ($line -eq 'progress=end') {
            Set-JobStatus $Job '진행중' 99
        }
        [System.Windows.Forms.Application]::DoEvents()
    }

    $proc.WaitForExit()
    $stderr = $proc.StandardError.ReadToEnd()
    if ($stderr) {
        $script:LastFfmpegError = Normalize-ErrorMessage $stderr "ffmpeg 종료 코드 $($proc.ExitCode)"
    } elseif ($proc.ExitCode -ne 0) {
        $script:LastFfmpegError = "ffmpeg 종료 코드 $($proc.ExitCode)"
    }
    if ($script:LastFfmpegError) { Write-Log "FFMPEG_ERROR mode=[$Mode] exit=[$($proc.ExitCode)] error=[$($script:LastFfmpegError)]" }
    return ($proc.ExitCode -eq 0 -and (Test-Path -LiteralPath $OutputPath))
}

function Start-Queue {
    if ($script:IsRunning -or $script:Jobs.Count -eq 0) { return }
    $ffmpegCommand = Get-Command $script:FfmpegPath -ErrorAction SilentlyContinue
    if (-not $ffmpegCommand) {
        [System.Windows.Forms.MessageBox]::Show((Tr 'NeedFfmpeg'), 'OK') | Out-Null
        return
    }
    if ($outputCustom.Checked -and [string]::IsNullOrWhiteSpace($outputText.Text)) {
        [System.Windows.Forms.MessageBox]::Show((Tr 'NeedOutputFolder'), 'OK') | Out-Null
        return
    }
    if ($outputCustom.Checked -and -not (Test-Path -LiteralPath $outputText.Text -PathType Container)) {
        [System.Windows.Forms.MessageBox]::Show((Tr 'OutputFolderMissing'), 'OK') | Out-Null
        return
    }

    $script:IsRunning = $true
    $script:StopRequested = $false
    $runUseOriginalFolder = $outputOriginal.Checked
    $runOutputDir = $outputText.Text
    $startButton.Enabled = $false
    $stopButton.Enabled = $true
    $rotation90.Enabled = $false
    $rotation270.Enabled = $false
    $rotation180.Enabled = $false
    $outputOriginal.Enabled = $false
    $outputCustom.Enabled = $false

    try {
        foreach ($job in $script:Jobs) {
            if ($script:StopRequested) { break }
            if ($job.Status -eq '완료') { continue }
            if ([int]$job.Rotation -eq 0) {
                Set-JobStatus $job '건너뜀' 0 ''
                continue
            }
            $job.Message = ''
            Set-JobStatus $job '진행중' 0 ''
            try {
                $outDir = if ($runUseOriginalFolder) { [System.IO.Path]::GetDirectoryName($job.Path) } else { $runOutputDir }
                $jobRotation = [int]$job.Rotation
                $outPath = Get-UniqueOutputPath $job.Path $jobRotation $outDir
                $job.Output = $outPath
                Run-FfmpegRotation $job $jobRotation $outPath
                Set-JobStatus $job '완료' 100 ''
            } catch {
                $job.Message = Normalize-ErrorMessage $_.Exception.Message 'ffmpeg 처리 실패'
                Write-Log "JOB_ERROR input=[$($job.Path)] error=[$($job.Message)]"
                if ($job.Message -eq '사용자 중지') {
                    Set-JobStatus $job '중지됨' $job.Progress ''
                } else {
                    $shortMessage = Normalize-ErrorMessage $job.Message '알 수 없는 오류'
                    if ($shortMessage.Length -gt 80) { $shortMessage = $shortMessage.Substring(0, 80) + '...' }
                    Set-JobStatus $job '실패' $job.Progress $shortMessage
                }
            }
            [System.Windows.Forms.Application]::DoEvents()
        }
    } finally {
        $script:IsRunning = $false
        $startButton.Enabled = $true
        $rotation90.Enabled = $true
        $rotation270.Enabled = $true
        $rotation180.Enabled = $true
        $outputOriginal.Enabled = $true
        $outputCustom.Enabled = $true
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = '영상 회전 태그 도구'
$form.Width = 820
$form.Height = 850
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Malgun Gothic', 9)
$form.AllowDrop = $true
$form.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 251)
$iconPath = Join-Path $script:AppDir 'RotateIcon.ico'
if (Test-Path -LiteralPath $iconPath) {
    $form.Icon = New-Object System.Drawing.Icon($iconPath)
}

$headerPanel = New-Object System.Windows.Forms.Panel
$headerPanel.Left = 0
$headerPanel.Top = 0
$headerPanel.Width = 820
$headerPanel.Height = 72
$headerPanel.BackColor = [System.Drawing.Color]::FromArgb(24, 28, 38)
$headerPanel.Anchor = 'Top,Left,Right'

$headerIcon = New-Object System.Windows.Forms.PictureBox
$headerIcon.Left = 22
$headerIcon.Top = 12
$headerIcon.Width = 48
$headerIcon.Height = 48
$headerIcon.SizeMode = 'Zoom'
$pngIconPath = Join-Path $script:AppDir 'RotateIcon.png'
if (Test-Path -LiteralPath $pngIconPath) {
    $headerIcon.Image = [System.Drawing.Image]::FromFile($pngIconPath)
}

$headerTitle = New-Object System.Windows.Forms.Label
$headerTitle.Text = '영상 회전 태그 도구'
$headerTitle.Left = 82
$headerTitle.Top = 13
$headerTitle.Width = 280
$headerTitle.Height = 24
$headerTitle.ForeColor = [System.Drawing.Color]::White
$headerTitle.Font = New-Object System.Drawing.Font('Malgun Gothic', 13, [System.Drawing.FontStyle]::Bold)

$headerSub = New-Object System.Windows.Forms.Label
$headerSub.Text = '재인코딩 없이 회전 메타데이터를 빠르게 추가합니다'
$headerSub.Left = 84
$headerSub.Top = 42
$headerSub.Width = 430
$headerSub.Height = 18
$headerSub.ForeColor = [System.Drawing.Color]::FromArgb(178, 209, 224)
$headerSub.Font = New-Object System.Drawing.Font('Malgun Gothic', 9)

$headerPanel.Controls.AddRange(@($headerIcon, $headerTitle, $headerSub))

$addFileButton = New-Object System.Windows.Forms.Button
$addFileButton.Text = '파일 추가'
$addFileButton.Left = 20
$addFileButton.Top = 268
$addFileButton.Width = 90

$addFolderButton = New-Object System.Windows.Forms.Button
$addFolderButton.Text = '폴더 추가'
$addFolderButton.Left = 118
$addFolderButton.Top = 268
$addFolderButton.Width = 90

$removeButton = New-Object System.Windows.Forms.Button
$removeButton.Text = '선택 삭제'
$removeButton.Left = 216
$removeButton.Top = 268
$removeButton.Width = 90

$clearButton = New-Object System.Windows.Forms.Button
$clearButton.Text = '비우기'
$clearButton.Left = 314
$clearButton.Top = 268
$clearButton.Width = 80

$selectToggleButton = New-Object System.Windows.Forms.Button
$selectToggleButton.Text = '전체 선택/해제'
$selectToggleButton.Left = 404
$selectToggleButton.Top = 268
$selectToggleButton.Width = 120

$languageLabel = New-Object System.Windows.Forms.Label
$languageLabel.Text = '언어'
$languageLabel.Left = 590
$languageLabel.Top = 274
$languageLabel.Width = 95
$languageLabel.Height = 24
$languageLabel.TextAlign = 'MiddleRight'
$languageLabel.ForeColor = [System.Drawing.Color]::FromArgb(40, 48, 66)
$languageLabel.Font = New-Object System.Drawing.Font('Malgun Gothic', 9, [System.Drawing.FontStyle]::Bold)

$langButton = New-Object System.Windows.Forms.Button
$langButton.Text = 'En/Kr'
$langButton.Left = 690
$langButton.Top = 268
$langButton.Width = 90

$fileLabel = New-Object System.Windows.Forms.Label
$fileLabel.Text = '추가된 파일'
$fileLabel.Left = 20
$fileLabel.Top = 58
$fileLabel.Width = 120
$fileLabel.Height = 20
$fileLabel.Font = New-Object System.Drawing.Font('Malgun Gothic', 9, [System.Drawing.FontStyle]::Bold)

$fileGrid = New-Object System.Windows.Forms.DataGridView
$fileGrid.Left = 20
$fileGrid.Top = 82
$fileGrid.Width = 760
$fileGrid.Height = 170
$fileGrid.AllowUserToAddRows = $false
$fileGrid.AllowUserToDeleteRows = $false
$fileGrid.AllowUserToResizeRows = $false
$fileGrid.RowHeadersVisible = $false
$fileGrid.SelectionMode = 'FullRowSelect'
$fileGrid.MultiSelect = $true
$fileGrid.ReadOnly = $false
$fileGrid.AutoSizeColumnsMode = 'Fill'
$fileGrid.BackgroundColor = [System.Drawing.Color]::White
$fileGrid.BorderStyle = 'FixedSingle'
$fileGrid.GridColor = [System.Drawing.Color]::FromArgb(225, 230, 238)
$fileGrid.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(40, 48, 66)
$fileGrid.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
$fileGrid.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font('Malgun Gothic', 9, [System.Drawing.FontStyle]::Bold)
$fileGrid.EnableHeadersVisualStyles = $false
$fileGrid.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(221, 238, 247)
$fileGrid.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::Black
$pathColumn = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$pathColumn.Name = 'Path'
$pathColumn.HeaderText = '파일명'
$pathColumn.ReadOnly = $true
$pathColumn.FillWeight = 78

$rotationColumn = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$rotationColumn.Name = 'Rotation'
$rotationColumn.HeaderText = '회전'
$rotationColumn.ReadOnly = $true
$rotationColumn.Width = 80
$rotationColumn.FillWeight = 10

$statusColumn = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$statusColumn.Name = 'Status'
$statusColumn.HeaderText = '상태'
$statusColumn.ReadOnly = $true
$statusColumn.Width = 90
$statusColumn.FillWeight = 12

[void]$fileGrid.Columns.Add($pathColumn)
[void]$fileGrid.Columns.Add($rotationColumn)
[void]$fileGrid.Columns.Add($statusColumn)

$rotationGroup = New-Object System.Windows.Forms.GroupBox
$rotationGroup.Text = '회전 작업'
$rotationGroup.Left = 20
$rotationGroup.Top = 314
$rotationGroup.Width = 760
$rotationGroup.Height = 82

$arrow90 = New-Object System.Windows.Forms.Label
$arrow90.Text = "MKV ←`r`nMP4 →"
$arrow90.Left = 18
$arrow90.Top = 18
$arrow90.Width = 92
$arrow90.Height = 34
$arrow90.TextAlign = 'MiddleCenter'
$arrow90.Font = New-Object System.Drawing.Font('Malgun Gothic', 9, [System.Drawing.FontStyle]::Bold)
$arrow90.ForeColor = [System.Drawing.Color]::FromArgb(72, 132, 154)

$arrow270 = New-Object System.Windows.Forms.Label
$arrow270.Text = "MKV →`r`nMP4 ←"
$arrow270.Left = 118
$arrow270.Top = 18
$arrow270.Width = 92
$arrow270.Height = 34
$arrow270.TextAlign = 'MiddleCenter'
$arrow270.Font = New-Object System.Drawing.Font('Malgun Gothic', 9, [System.Drawing.FontStyle]::Bold)
$arrow270.ForeColor = [System.Drawing.Color]::FromArgb(72, 132, 154)

$arrow180 = New-Object System.Windows.Forms.Label
$arrow180.Text = "MKV ↓`r`nMP4 ↓"
$arrow180.Left = 218
$arrow180.Top = 18
$arrow180.Width = 92
$arrow180.Height = 34
$arrow180.TextAlign = 'MiddleCenter'
$arrow180.Font = New-Object System.Drawing.Font('Malgun Gothic', 9, [System.Drawing.FontStyle]::Bold)
$arrow180.ForeColor = [System.Drawing.Color]::FromArgb(72, 132, 154)

$rotation90 = New-Object System.Windows.Forms.Button
$rotation90.Text = '90도'
$rotation90.Left = 18
$rotation90.Top = 56
$rotation90.Width = 90

$rotation270 = New-Object System.Windows.Forms.Button
$rotation270.Text = '270도'
$rotation270.Left = 118
$rotation270.Top = 56
$rotation270.Width = 90

$rotation180 = New-Object System.Windows.Forms.Button
$rotation180.Text = '180도'
$rotation180.Left = 218
$rotation180.Top = 56
$rotation180.Width = 90

$rotationGroup.Controls.AddRange(@($arrow90, $arrow270, $arrow180, $rotation90, $rotation270, $rotation180))

$outputGroup = New-Object System.Windows.Forms.GroupBox
$outputGroup.Text = '출력 위치'
$outputGroup.Left = 20
$outputGroup.Top = 430
$outputGroup.Width = 760
$outputGroup.Height = 88

$outputOriginal = New-Object System.Windows.Forms.RadioButton
$outputOriginal.Text = '원본 폴더에 저장'
$outputOriginal.Left = 18
$outputOriginal.Top = 26
$outputOriginal.Width = 140
$outputOriginal.Checked = $true

$outputCustom = New-Object System.Windows.Forms.RadioButton
$outputCustom.Text = '출력 폴더 지정'
$outputCustom.Left = 18
$outputCustom.Top = 55
$outputCustom.Width = 130

$outputText = New-Object System.Windows.Forms.TextBox
$outputText.Left = 150
$outputText.Top = 53
$outputText.Width = 500
$outputText.Enabled = $false

$browseOutput = New-Object System.Windows.Forms.Button
$browseOutput.Text = '찾기'
$browseOutput.Left = 660
$browseOutput.Top = 51
$browseOutput.Width = 70

$outputGroup.Controls.AddRange(@($outputOriginal, $outputCustom, $outputText, $browseOutput))

$progressLabel = New-Object System.Windows.Forms.Label
$progressLabel.Text = '작업 진행'
$progressLabel.Left = 20
$progressLabel.Top = 534
$progressLabel.Width = 120
$progressLabel.Height = 20
$progressLabel.Font = New-Object System.Drawing.Font('Malgun Gothic', 9, [System.Drawing.FontStyle]::Bold)

$progressPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$progressPanel.Left = 20
$progressPanel.Top = 558
$progressPanel.Width = 760
$progressPanel.Height = 150
$progressPanel.BorderStyle = 'FixedSingle'
$progressPanel.BackColor = [System.Drawing.Color]::White
$progressPanel.AutoScroll = $true
$progressPanel.FlowDirection = 'TopDown'
$progressPanel.WrapContents = $false
$progressPanel.Padding = New-Object System.Windows.Forms.Padding(8)

$startButton = New-Object System.Windows.Forms.Button
$startButton.Text = '시작'
$startButton.Left = 604
$startButton.Top = 724
$startButton.Width = 80
$startButton.Height = 30

$stopButton = New-Object System.Windows.Forms.Button
$stopButton.Text = '중지'
$stopButton.Left = 700
$stopButton.Top = 724
$stopButton.Width = 80
$stopButton.Height = 30

$form.Controls.AddRange(@(
    $addFileButton, $addFolderButton, $removeButton, $clearButton, $selectToggleButton, $languageLabel, $langButton,
    $fileLabel, $fileGrid, $rotationGroup, $outputGroup,
    $progressLabel, $progressPanel, $startButton, $stopButton
))

foreach ($control in @($addFileButton, $addFolderButton, $removeButton, $clearButton, $selectToggleButton, $languageLabel, $langButton, $fileLabel, $fileGrid, $rotationGroup, $outputGroup, $progressLabel, $progressPanel, $startButton, $stopButton)) {
    $control.Top += 72
}
foreach ($button in @($addFileButton, $addFolderButton, $removeButton, $clearButton, $selectToggleButton, $langButton, $browseOutput, $startButton, $stopButton)) {
    Set-ButtonStyle $button
}
foreach ($button in @($rotation90, $rotation270, $rotation180)) {
    Set-RotationButtonStyle $button
}
$startButton.BackColor = [System.Drawing.Color]::FromArgb(255, 161, 45)
$startButton.ForeColor = [System.Drawing.Color]::FromArgb(24, 28, 38)
$form.Controls.Add($headerPanel)
$headerPanel.BringToFront()

$addFileButton.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Multiselect = $true
    $dlg.Filter = 'Video files|*.mp4;*.m4v;*.mov;*.mkv;*.avi;*.wmv;*.flv;*.webm;*.ts;*.mts;*.m2ts;*.mpg;*.mpeg;*.3gp|All files|*.*'
    if ($dlg.ShowDialog() -eq 'OK') {
        foreach ($file in $dlg.FileNames) { Add-FileJob $file }
    }
})

$addFolderButton.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($dlg.ShowDialog() -eq 'OK') { Add-FolderJobs $dlg.SelectedPath }
})

$removeButton.Add_Click({
    if ($script:IsRunning) { return }
    $selected = @($fileGrid.SelectedRows)
    foreach ($row in $selected) {
        $job = $row.Tag
        if ($null -ne $job) {
            if ($script:Rows.ContainsKey($job.Path)) {
                $progressPanel.Controls.Remove($script:Rows[$job.Path].Panel)
                $script:Rows.Remove($job.Path)
            }
            [void]$script:Jobs.Remove($job)
            $fileGrid.Rows.Remove($row)
        }
    }
})

$clearButton.Add_Click({
    if ($script:IsRunning) { return }
    $script:Jobs.Clear()
    $script:Rows.Clear()
    $fileGrid.Rows.Clear()
    $progressPanel.Controls.Clear()
})

$langButton.Add_Click({
    if ($script:Lang -eq 'KR') { $script:Lang = 'EN' } else { $script:Lang = 'KR' }
    Apply-Language
})

$selectToggleButton.Add_Click({ Toggle-SelectAllFiles })

$rotation90.Add_Click({ Set-SelectedRotation 90 })
$rotation270.Add_Click({ Set-SelectedRotation 270 })
$rotation180.Add_Click({ Set-SelectedRotation 180 })

$outputCustom.Add_CheckedChanged({
    $outputText.Enabled = $outputCustom.Checked
})

$browseOutput.Add_Click({
    if (-not $outputCustom.Checked -or $script:IsRunning) { return }
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($dlg.ShowDialog() -eq 'OK') { $outputText.Text = $dlg.SelectedPath }
})

$startButton.Add_Click({ Start-Queue })
$stopButton.Add_Click({ if ($script:IsRunning) { $script:StopRequested = $true } })

$form.Add_DragEnter({
    if ($_.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
        $_.Effect = [System.Windows.Forms.DragDropEffects]::Copy
    }
})

$form.Add_DragDrop({
    $paths = $_.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)
    foreach ($path in $paths) {
        if (Test-Path -LiteralPath $path -PathType Container) {
            Add-FolderJobs $path
        } else {
            Add-FileJob $path
        }
    }
})

Apply-Language
[void]$form.ShowDialog()














