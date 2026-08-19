<#
================================================================
 SA-Block Monitor — real-time desktop monitor for sa/x3 logins
================================================================
 Polls SABlockAudit.dbo.LoginAudit every few seconds and shows a
 live, color-coded feed:  green = allowed, red = BLOCKED.
 Blocked attempts also fire a beep + flash the status bar.

 HOW TO RUN (on your desktop, PowerShell 5.1+):
   powershell -ExecutionPolicy Bypass -File .\SA-Block-Monitor.ps1

 EDIT THE CONFIG BLOCK BELOW FIRST.
================================================================
#>

# ======================= CONFIG — EDIT ME =======================
$ServerInstance  = "localhost"        # e.g. "MYSERVER\SQL2019" or "192.168.1.10,1433"
$UseWindowsAuth  = $true              # $true = Windows auth; $false = SQL auth below
$SqlUser         = "monitor_reader"   # used only when $UseWindowsAuth = $false
$SqlPassword     = ""                 # used only when $UseWindowsAuth = $false
$PollSeconds     = 3                  # refresh interval
$MaxRows         = 500                # rows kept in the on-screen feed
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
        Title="SA-Block Monitor  —  sa / x3 login watch"
        Width="860" Height="520" WindowStartupLocation="CenterScreen"
        Background="#1E1E2E">
  <DockPanel>
    <Border DockPanel.Dock="Top" Background="#11111B" Padding="10,8">
      <DockPanel>
        <TextBlock x:Name="TitleText" Text="SA-BLOCK MONITOR" Foreground="#89B4FA"
                   FontFamily="Consolas" FontSize="16" FontWeight="Bold"/>
        <CheckBox x:Name="TopMostBox" Content="Always on top" Foreground="#CDD6F4"
                  DockPanel.Dock="Right" HorizontalAlignment="Right" VerticalAlignment="Center"/>
      </DockPanel>
    </Border>
    <Border DockPanel.Dock="Bottom" x:Name="StatusBar" Background="#11111B" Padding="10,6">
      <TextBlock x:Name="StatusText" Text="Connecting..." Foreground="#A6ADC8"
                 FontFamily="Consolas" FontSize="12"/>
    </Border>
    <ListView x:Name="Feed" Background="#1E1E2E" BorderThickness="0"
              Foreground="#CDD6F4" FontFamily="Consolas" FontSize="13">
      <ListView.View>
        <GridView>
          <GridViewColumn Header="Time (local)" Width="150" DisplayMemberBinding="{Binding Time}"/>
          <GridViewColumn Header="Login"        Width="80"  DisplayMemberBinding="{Binding Login}"/>
          <GridViewColumn Header="Client IP"    Width="150" DisplayMemberBinding="{Binding ClientHost}"/>
          <GridViewColumn Header="Workstation"  Width="130" DisplayMemberBinding="{Binding HostName}"/>
          <GridViewColumn Header="Application"  Width="180" DisplayMemberBinding="{Binding AppName}"/>
          <GridViewColumn Header="Result"       Width="110" DisplayMemberBinding="{Binding Result}"/>
        </GridView>
      </ListView.View>
      <ListView.ItemContainerStyle>
        <Style TargetType="ListViewItem">
          <Setter Property="Foreground" Value="{Binding RowColor}"/>
          <Setter Property="Background" Value="Transparent"/>
        </Style>
      </ListView.ItemContainerStyle>
    </ListView>
  </DockPanel>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$Feed       = $window.FindName("Feed")
$StatusText = $window.FindName("StatusText")
$StatusBar  = $window.FindName("StatusBar")
$TopMostBox = $window.FindName("TopMostBox")

$TopMostBox.Add_Checked(  { $window.Topmost = $true  })
$TopMostBox.Add_Unchecked({ $window.Topmost = $false })

$items = New-Object System.Collections.ObjectModel.ObservableCollection[object]
$Feed.ItemsSource = $items

$script:LastId    = 0
$script:FirstLoad = $true

function Add-Row($row) {
    $utc     = [DateTime]::SpecifyKind($row.EventTimeUtc, [DateTimeKind]::Utc)
    $blocked = [bool]$row.WasBlocked
    $items.Insert(0, [pscustomobject]@{
        Time       = $utc.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss")
        Login      = [string]$row.LoginName
        ClientHost = [string]$row.ClientHost
        HostName   = [string]$row.HostName
        AppName    = [string]$row.AppName
        Result     = if ($blocked) { "BLOCKED" } else { "allowed" }
        RowColor   = if ($blocked) { "#F38BA8" } else { "#A6E3A1" }
    })
    while ($items.Count -gt $MaxRows) { $items.RemoveAt($items.Count - 1) }
    return $blocked
}

function Poll {
    $conn = New-Object System.Data.SqlClient.SqlConnection (New-ConnectionString)
    try {
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = @"
SELECT TOP (200) Id, EventTimeUtc, LoginName, ClientHost, AppName, HostName, WasBlocked
FROM dbo.LoginAudit
WHERE Id > @lastId
ORDER BY Id ASC;
"@
        [void]$cmd.Parameters.AddWithValue("@lastId", $script:LastId)
        $da = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
        $dt = New-Object System.Data.DataTable
        [void]$da.Fill($dt)

        $sawBlocked = $false
        foreach ($row in $dt.Rows) {
            if (Add-Row $row) { $sawBlocked = $true }
            $script:LastId = [long]$row.Id
        }

        if ($sawBlocked -and -not $script:FirstLoad) {
            $StatusBar.Background = "#F38BA8"
            $StatusText.Foreground = "#11111B"
            $StatusText.Text = ("!! BLOCKED LOGIN ATTEMPT !!   " + (Get-Date -Format "HH:mm:ss"))
            if ($BeepOnBlocked) { 1..3 | ForEach-Object { [console]::Beep(1200, 180) } }
        } else {
            $StatusBar.Background = "#11111B"
            $StatusText.Foreground = "#A6ADC8"
            $StatusText.Text = ("Connected to {0}  |  {1} events shown  |  last check {2}" -f
                $ServerInstance, $items.Count, (Get-Date -Format "HH:mm:ss"))
        }
        $script:FirstLoad = $false
    }
    catch {
        $StatusBar.Background = "#F9E2AF"
        $StatusText.Foreground = "#11111B"
        $StatusText.Text = "Connection error: " + $_.Exception.Message
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
