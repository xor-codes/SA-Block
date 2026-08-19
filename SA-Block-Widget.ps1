<#
================================================================
 SA-Block Widget — tiny corner stats for sa/x3 logins
================================================================
 Compact always-on-top widget (like MonPlus) that sits in the
 bottom-right corner and shows only the numbers:

     TOTAL LOGINS  |  INTERNAL  |  EXTERNAL  |  BLOCKED

 Polls SABlockAudit.dbo.LoginAudit. Beeps + flashes when the
 BLOCKED count goes up. Drag anywhere to move. ✕ to close.

 ONE-WINDOW LAUNCH (no console):
   double-click  SA-Block-Widget-Silent.vbs   (recommended)
 or:
   powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File .\SA-Block-Widget.ps1

 If you run it from an already-open terminal, that terminal
 stays open (normal) — use the .vbs for the clean look.
================================================================
#>

# ======================= CONFIG — EDIT ME =======================
$ServerInstance  = "localhost"        # e.g. "ECS-X3TRAINING-\SAGEX3DB"
$UseWindowsAuth  = $true              # $false = SQL auth below
$SqlUser         = "monitor_reader"
$SqlPassword     = ""
$PollSeconds     = 3
$BeepOnBlocked   = $true
# ================================================================

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Data

function New-ConnectionString {
    if ($UseWindowsAuth) {
        "Server=$ServerInstance;Database=SABlockAudit;Integrated Security=True;Connect Timeout=5"
    } else {
        "Server=$ServerInstance;Database=SABlockAudit;User ID=$SqlUser;Password=$SqlPassword;Connect Timeout=5"
    }
}

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="SA-Block Widget" Width="240" Height="332"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ResizeMode="NoResize" ShowInTaskbar="True" Topmost="True">
  <Border CornerRadius="12" Background="#1E1E2E" BorderBrush="#313244" BorderThickness="1">
    <DockPanel Margin="0">

      <!-- title bar -->
      <Border DockPanel.Dock="Top" Background="#11111B" CornerRadius="12,12,0,0" Padding="12,8">
        <DockPanel>
          <TextBlock Text="SA-BLOCK" Foreground="#89B4FA" FontFamily="Consolas"
                     FontSize="13" FontWeight="Bold" VerticalAlignment="Center"/>
          <Button x:Name="CloseBtn" DockPanel.Dock="Right" HorizontalAlignment="Right"
                  Content="✕" Width="22" Height="22" Foreground="#A6ADC8"
                  Background="Transparent" BorderThickness="0" Cursor="Hand" FontSize="11"/>
          <Button x:Name="MinBtn" DockPanel.Dock="Right" HorizontalAlignment="Right"
                  Content="—" Width="22" Height="22" Foreground="#A6ADC8"
                  Background="Transparent" BorderThickness="0" Cursor="Hand" FontSize="11"/>
        </DockPanel>
      </Border>

      <!-- status bar -->
      <Border DockPanel.Dock="Bottom" x:Name="StatusBar" Background="#11111B"
              CornerRadius="0,0,12,12" Padding="12,6">
        <TextBlock x:Name="StatusText" Text="connecting…" Foreground="#A6ADC8"
                   FontFamily="Consolas" FontSize="10"/>
      </Border>

      <!-- stat tiles -->
      <StackPanel Margin="10,8,10,8">

        <Border Background="#181825" CornerRadius="8" Padding="12,8" Margin="0,0,0,6">
          <DockPanel>
            <TextBlock Text="TOTAL LOGINS" Foreground="#A6ADC8" FontFamily="Consolas"
                       FontSize="10" VerticalAlignment="Center"/>
            <TextBlock x:Name="TotalVal" Text="—" DockPanel.Dock="Right" HorizontalAlignment="Right"
                       Foreground="#CDD6F4" FontFamily="Consolas" FontSize="22" FontWeight="Bold"/>
          </DockPanel>
        </Border>

        <Border Background="#181825" CornerRadius="8" Padding="12,8" Margin="0,0,0,6">
          <DockPanel>
            <TextBlock Text="INTERNAL" Foreground="#A6ADC8" FontFamily="Consolas"
                       FontSize="10" VerticalAlignment="Center"/>
            <TextBlock x:Name="InternalVal" Text="—" DockPanel.Dock="Right" HorizontalAlignment="Right"
                       Foreground="#A6E3A1" FontFamily="Consolas" FontSize="22" FontWeight="Bold"/>
          </DockPanel>
        </Border>

        <Border Background="#181825" CornerRadius="8" Padding="12,8" Margin="0,0,0,6">
          <DockPanel>
            <TextBlock Text="EXTERNAL" Foreground="#A6ADC8" FontFamily="Consolas"
                       FontSize="10" VerticalAlignment="Center"/>
            <TextBlock x:Name="ExternalVal" Text="—" DockPanel.Dock="Right" HorizontalAlignment="Right"
                       Foreground="#89B4FA" FontFamily="Consolas" FontSize="22" FontWeight="Bold"/>
          </DockPanel>
        </Border>

        <Border x:Name="BlockedTile" Background="#181825" CornerRadius="8" Padding="12,8">
          <DockPanel>
            <TextBlock Text="BLOCKED" Foreground="#A6ADC8" FontFamily="Consolas"
                       FontSize="10" VerticalAlignment="Center"/>
            <TextBlock x:Name="BlockedVal" Text="—" DockPanel.Dock="Right" HorizontalAlignment="Right"
                       Foreground="#F38BA8" FontFamily="Consolas" FontSize="22" FontWeight="Bold"/>
          </DockPanel>
        </Border>

      </StackPanel>
    </DockPanel>
  </Border>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$TotalVal    = $window.FindName("TotalVal")
$InternalVal = $window.FindName("InternalVal")
$ExternalVal = $window.FindName("ExternalVal")
$BlockedVal  = $window.FindName("BlockedVal")
$BlockedTile = $window.FindName("BlockedTile")
$StatusText  = $window.FindName("StatusText")
$StatusBar   = $window.FindName("StatusBar")

$window.FindName("CloseBtn").Add_Click({ $window.Close() })
$window.FindName("MinBtn").Add_Click({ $window.WindowState = "Minimized" })
$window.Add_MouseLeftButtonDown({ try { $window.DragMove() } catch {} })

# park it in the bottom-right corner of the working area
$wa = [System.Windows.SystemParameters]::WorkArea
$window.Left = $wa.Right  - $window.Width  - 12
$window.Top  = $wa.Bottom - $window.Height - 12

$script:LastBlocked = -1   # -1 = first load, don't alarm on startup

function Poll {
    $conn = New-Object System.Data.SqlClient.SqlConnection (New-ConnectionString)
    try {
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = @"
SELECT
    COUNT_BIG(*) AS Total,
    SUM(CASE WHEN ClientHost IS NULL
              OR ClientHost IN (N'<local machine>', N'127.0.0.1', N'::1')
             THEN 1 ELSE 0 END) AS InternalCount,
    SUM(CASE WHEN ClientHost IS NOT NULL
              AND ClientHost NOT IN (N'<local machine>', N'127.0.0.1', N'::1')
             THEN 1 ELSE 0 END) AS ExternalCount,
    SUM(CASE WHEN WasBlocked = 1 THEN 1 ELSE 0 END) AS BlockedCount
FROM dbo.LoginAudit;
"@
        $r = $cmd.ExecuteReader()
        if ($r.Read()) {
            $total    = [int64]$r["Total"]
            $internal = if ($r["InternalCount"] -is [DBNull]) { 0 } else { [int64]$r["InternalCount"] }
            $external = if ($r["ExternalCount"] -is [DBNull]) { 0 } else { [int64]$r["ExternalCount"] }
            $blocked  = if ($r["BlockedCount"]  -is [DBNull]) { 0 } else { [int64]$r["BlockedCount"] }

            $TotalVal.Text    = "{0:N0}" -f $total
            $InternalVal.Text = "{0:N0}" -f $internal
            $ExternalVal.Text = "{0:N0}" -f $external
            $BlockedVal.Text  = "{0:N0}" -f $blocked

            if ($script:LastBlocked -ge 0 -and $blocked -gt $script:LastBlocked) {
                $BlockedTile.Background = "#45222E"          # flash the tile
                $StatusBar.Background   = "#F38BA8"
                $StatusText.Foreground  = "#11111B"
                $StatusText.Text        = "!! BLOCKED ATTEMPT " + (Get-Date -Format "HH:mm:ss") + " !!"
                if ($BeepOnBlocked) { 1..3 | ForEach-Object { [console]::Beep(1200, 160) } }
            } else {
                $BlockedTile.Background = "#181825"
                $StatusBar.Background   = "#11111B"
                $StatusText.Foreground  = "#A6ADC8"
                $StatusText.Text        = "● live · " + (Get-Date -Format "HH:mm:ss")
                $StatusText.ToolTip     = $null
            }
            $script:LastBlocked = $blocked
        }
        $r.Close()
    }
    catch {
        $StatusBar.Background  = "#11111B"
        $StatusText.Foreground = "#F9E2AF"
        $StatusText.Text       = "o offline - retrying (hover for error)"
        $StatusText.ToolTip    = $_.Exception.Message
    }
    finally {
        $conn.Dispose()
    }
}

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds($PollSeconds)
$timer.Add_Tick({ Poll })

$window.Add_Loaded({ Poll; $timer.Start() })
$window.Add_Closed({ $timer.Stop() })

[void]$window.ShowDialog()
