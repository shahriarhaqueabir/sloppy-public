# src/Slop.ChatWindow.ps1 -- geometry, interaction state and XAML for the
# separate transparent chat window. Dot-sourcing this file constructs no WPF
# objects; callers parse the XAML when they actually open the window.
$ErrorActionPreference = 'Stop'

# Pure pane geometry is owned by Slop.PaneMovement.ps1. Dot-source it here so
# the chat window module resolves Full preset, pin-aware placement, tolerant
# clamp and drag-grip contracts when it is loaded on its own.
$paneMovementModule = Join-Path $PSScriptRoot 'Slop.PaneMovement.ps1'
if (Test-Path -LiteralPath $paneMovementModule) { . $paneMovementModule }

function Get-SlopChatDragGripGeometry {
    param([int]$Width = 760, [int]$Height = 540)
    # The grip occupies the top strip of the chat chrome; the pure helper owns
    # the size contract so shell handlers cannot invent a second geometry.
    return Get-SlopChatDragGripRect -Width $Width -Height $Height
}

function Test-SlopChatPaneClampNeeded {
    param([double]$Value, [double]$Minimum, [double]$Maximum, [int]$Tolerance = 4)
    return Test-SlopPaneClampNeeded -Value ([int][Math]::Round($Value)) `
        -Minimum ([int][Math]::Round($Minimum)) -Maximum ([int][Math]::Round($Maximum)) `
        -Tolerance $Tolerance
}

function Get-SlopWorkAreaClampedRect {
    param(
        [Parameter(Mandatory)][double]$Left,
        [Parameter(Mandatory)][double]$Top,
        [Parameter(Mandatory)][double]$Width,
        [Parameter(Mandatory)][double]$Height,
        [Parameter(Mandatory)]$WorkArea
    )
    $waX = [double]$WorkArea.X
    $waY = [double]$WorkArea.Y
    $waW = [double]$WorkArea.Width
    $waH = [double]$WorkArea.Height
    $w = [Math]::Min([Math]::Max(1.0, $Width), $waW)
    $h = [Math]::Min([Math]::Max(1.0, $Height), $waH)
    $x = [Math]::Max($waX, [Math]::Min($Left, $waX + $waW - $w))
    $y = [Math]::Max($waY, [Math]::Min($Top, $waY + $waH - $h))
    return @{ Left = $x; Top = $y; Width = $w; Height = $h }
}

function Get-SlopChatWindowRect {
    param(
        [Parameter(Mandatory)][double]$PetLeft,
        [Parameter(Mandatory)][double]$PetTop,
        [Parameter(Mandatory)][double]$PetWidth,
        [Parameter(Mandatory)][double]$PetHeight,
        [Parameter(Mandatory)]$WorkArea,
        [ValidateSet('Extended','Full')][string]$Mode = 'Extended',
        [double]$ExtendedWidth = 760.0,
        [double]$ExtendedHeight = 540.0
    )
    if ($Mode -eq 'Full') {
        # A large inset preset, never a work-area-filling pseudo-maximize.
        $full = Get-SlopFullPaneRect -WorkArea @{
            X = [int]$WorkArea.X; Y = [int]$WorkArea.Y
            Width = [int]$WorkArea.Width; Height = [int]$WorkArea.Height
        }
        return Get-SlopWorkAreaClampedRect -Left ([double]$full.Left) -Top ([double]$full.Top) `
            -Width ([double]$full.Width) -Height ([double]$full.Height) -WorkArea $WorkArea
    }
    $left = $PetLeft + $PetWidth + 24.0
    $top = $PetTop + ($PetHeight - $ExtendedHeight) / 2.0
    return Get-SlopWorkAreaClampedRect -Left $left -Top $top `
        -Width $ExtendedWidth -Height $ExtendedHeight -WorkArea $WorkArea
}

function Get-SlopPetInteractionState {
    param([bool]$ChatOpen)
    if ($ChatOpen) { return @{ IsHitTestVisible = $false; Topmost = $false; Cursor = 'Arrow' } }
    return @{ IsHitTestVisible = $true; Topmost = $true; Cursor = 'Hand' }
}

function Get-SlopChatWindowXaml {
    # The window stays transparent. Readability comes from the dark panel fills
    # inside it, never from a system backdrop such as Mica or Acrylic.
    return @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Sloppy chat" MinWidth="468" MinHeight="330" Width="760" Height="540"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="False" ResizeMode="CanResize" ShowInTaskbar="True"
        WindowStartupLocation="Manual" UseLayoutRounding="True">
  <Window.Resources>
    <Style x:Key="SlopChatComboBoxItem" TargetType="ComboBoxItem">
      <Setter Property="Background" Value="#1E293B"/>
      <Setter Property="Foreground" Value="#EAEAEA"/>
      <Setter Property="BorderBrush" Value="#44FFFFFF"/>
    </Style>
    <Style x:Key="SlopChatComboBox" TargetType="ComboBox">
      <Setter Property="Background" Value="#1E293B"/>
      <Setter Property="Foreground" Value="#EAEAEA"/>
      <Setter Property="BorderBrush" Value="#44FFFFFF"/>
      <Setter Property="ItemContainerStyle" Value="{StaticResource SlopChatComboBoxItem}"/>
    </Style>
  </Window.Resources>
  <Grid x:Name="ChatRoot">
    <Grid.RowDefinitions>
      <RowDefinition Height="34"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <!-- Readability comes from a dark backplate inside the transparent window,
         never from a system material that would replace the WPF surface. -->
    <Border x:Name="ChatBackplate" Grid.RowSpan="4" Margin="4" CornerRadius="12"
            Background="#F212141C" BorderBrush="#8893A4BD" BorderThickness="2"
            SnapsToDevicePixels="True" IsHitTestVisible="False"/>
    <Border x:Name="ChatDragGrip" Grid.Row="0" Margin="0,0,124,0" Background="Transparent"
            Cursor="SizeAll" ToolTip="Drag chat pane" AutomationProperties.Name="Drag chat pane"
            Panel.ZIndex="2"/>
    <Border x:Name="ChatChrome" Grid.Row="0" Background="#F21E293B"
            BorderBrush="#44FFFFFF" BorderThickness="1" CornerRadius="12,12,0,0">
      <Grid>
        <TextBlock Text="S.L.O.P. chat" Foreground="#EAEAEA" FontWeight="SemiBold"
                   FontSize="12" VerticalAlignment="Center" Margin="12,0,0,0"
                   IsHitTestVisible="False"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,0,8,0">
          <Button x:Name="ChatDeckButton" Width="22" Height="22" Content="☰"
                  ToolTip="Toggle control deck" Background="#F24F46E5" Foreground="#FFFFFF"
                  BorderBrush="#55FFFFFF" BorderThickness="1" Cursor="Hand" FontSize="11"
                  AutomationProperties.Name="Toggle control deck"/>
          <Button x:Name="ChatModeButton" Width="22" Height="22" Content="□"
                  ToolTip="Toggle chat size" Background="#F24F46E5" Foreground="#FFFFFF"
                  BorderBrush="#55FFFFFF" BorderThickness="1" Cursor="Hand" FontSize="11"
                  AutomationProperties.Name="Toggle chat size"/>
          <Button x:Name="ChatCloseButton" Width="22" Height="22" Content="X"
                  ToolTip="Close chat" Background="#F24F46E5" Foreground="#FFFFFF"
                  BorderBrush="#55FFFFFF" BorderThickness="1" Cursor="Hand" FontSize="11"
                  AutomationProperties.Name="Close chat"/>
        </StackPanel>
      </Grid>
    </Border>
    <Border x:Name="ChatDeckPanel" Grid.Row="1" Grid.RowSpan="3" Visibility="Visible" Margin="12,4,12,0" CornerRadius="10"
            Background="#F212141C" BorderBrush="#8893A4BD" BorderThickness="2"
            Padding="8" VerticalAlignment="Top" SnapsToDevicePixels="True">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <WrapPanel x:Name="DeckStrip" Grid.Row="0" Margin="0,0,0,4">
          <Button x:Name="DeckOverviewButton" Content="Overview" Tag="Overview" Width="76" Height="24"
                  Margin="0,0,4,0" FontSize="10" Background="#F24F46E5" Foreground="#FFFFFF"
                  BorderBrush="#55FFFFFF" BorderThickness="1" Cursor="Hand"
                  AutomationProperties.Name="Control deck overview"/>
          <Button x:Name="DeckSettingsButton" Content="Settings" Tag="Settings" Width="76" Height="24"
                  Margin="0,0,4,0" FontSize="10" Background="#F2263348" Foreground="#EAEAEA"
                  BorderBrush="#55FFFFFF" BorderThickness="1" Cursor="Hand"
                  AutomationProperties.Name="Control deck settings"/>
          <Button x:Name="DeckDataButton" Content="Data" Tag="Data" Width="76" Height="24"
                  Margin="0,0,4,0" FontSize="10" Background="#F2263348" Foreground="#EAEAEA"
                  BorderBrush="#55FFFFFF" BorderThickness="1" Cursor="Hand"
                  AutomationProperties.Name="Control deck data"/>
          <Button x:Name="DeckToolsButton" Content="Tools &amp; Skills" Tag="Tools" Width="100" Height="24"
                  Margin="0,0,4,0" FontSize="10" Background="#F2263348" Foreground="#EAEAEA"
                  BorderBrush="#55FFFFFF" BorderThickness="1" Cursor="Hand"
                  AutomationProperties.Name="Control deck tools and skills"/>
          <Button x:Name="DeckUnderHoodButton" Content="Under the hood" Tag="UnderTheHood" Width="104" Height="24"
                  Margin="0,0,4,0" FontSize="10" Background="#F2263348" Foreground="#EAEAEA"
                  BorderBrush="#55FFFFFF" BorderThickness="1" Cursor="Hand"
                  AutomationProperties.Name="Control deck under the hood"/>
          <Button x:Name="DeckExitButton" Content="Exit" Tag="Exit" Width="60" Height="24"
                  Margin="0,0,4,0" FontSize="10" Background="#F2263348" Foreground="#EAEAEA"
                  BorderBrush="#55FFFFFF" BorderThickness="1" Cursor="Hand"
                  AutomationProperties.Name="Control deck exit"/>
          <Button x:Name="DeckCollapseButton" Content="⌄" Width="24" Height="24"
                  ToolTip="Collapse or expand the deck body"
                  Background="#F2263348" Foreground="#EAEAEA" BorderBrush="#55FFFFFF"
                  BorderThickness="1" Cursor="Hand" FontSize="11"
                  AutomationProperties.Name="Collapse or expand the deck body"/>
        </WrapPanel>
        <Border x:Name="DeckBody" Grid.Row="1" CornerRadius="8"
                Background="#F212141C" BorderBrush="#44FFFFFF" BorderThickness="1" Padding="8">
          <Grid>
            <Grid.RowDefinitions>
              <RowDefinition Height="*"/>
              <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <StackPanel Grid.Row="0">
                <StackPanel x:Name="DeckOverviewSection">
                  <TextBlock Text="Overview" FontSize="13" FontWeight="SemiBold" Foreground="#EAEAEA" Margin="0,0,0,6"/>
                  <TextBlock x:Name="DeckOverviewText" Text="Route, brain, session and signal state appear here."
                             Foreground="#DADAE2" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,8"
                             IsHitTestVisible="False"/>
                  <TextBlock x:Name="DeckConversationLengthText" Text="Conversation length: 0 messages"
                             Foreground="#93A4BD" FontSize="11" Margin="0,0,0,8" IsHitTestVisible="False"/>
                </StackPanel>
                <StackPanel x:Name="DeckSettingsSection" Visibility="Collapsed">
                  <TextBlock Text="Settings" FontSize="13" FontWeight="SemiBold" Foreground="#EAEAEA" Margin="0,0,0,6"/>
                  <Border CornerRadius="6" Background="#F2263348" BorderBrush="#44FFFFFF" BorderThickness="1"
                          Padding="6" Margin="0,0,0,6">
                    <StackPanel>
                      <TextBlock Text="Voice" FontSize="11" FontWeight="SemiBold" Foreground="#A5B4FC" Margin="0,0,0,4"/>
                      <CheckBox x:Name="DeckVoiceEnabledCheck" Content="Voice input (local transcription)"
                                Foreground="#DADAE2" FontSize="11" Margin="0,0,0,4"/>
                      <TextBlock Text="Language" Foreground="#B8B8C0" FontSize="10" Margin="0,0,0,2"/>
                      <ComboBox x:Name="DeckVoiceLanguageCombo" Height="24" FontSize="11" Width="140"
                                HorizontalAlignment="Left" Margin="0,0,0,4"
                                ItemContainerStyle="{StaticResource SlopChatComboBoxItem}"/>
                      <TextBlock Text="Max seconds" Foreground="#B8B8C0" FontSize="10" Margin="0,0,0,2"/>
                      <TextBox x:Name="DeckVoiceMaxSecondsBox" Height="24" FontSize="11" Width="80"
                               HorizontalAlignment="Left" Padding="6,3" VerticalContentAlignment="Center"
                               Margin="0,0,0,4"/>
                      <TextBlock x:Name="DeckVoiceReadyText" Text="Whisper readiness: unknown"
                                 Foreground="#93A4BD" FontSize="10" TextWrapping="Wrap" Margin="0,0,0,4"
                                 IsHitTestVisible="False"/>
                      <Button x:Name="DeckVoiceSaveButton" Content="Save voice" Width="100" Height="24"
                              FontSize="10" Background="#F24F46E5" Foreground="#FFFFFF"
                              BorderBrush="#55FFFFFF" BorderThickness="1" Cursor="Hand"
                              AutomationProperties.Name="Save deck voice settings"/>
                    </StackPanel>
                  </Border>
                  <Border CornerRadius="6" Background="#F2263348" BorderBrush="#44FFFFFF" BorderThickness="1"
                          Padding="6" Margin="0,0,0,6">
                    <StackPanel>
                      <TextBlock Text="Model" FontSize="11" FontWeight="SemiBold" Foreground="#A5B4FC" Margin="0,0,0,4"/>
                      <TextBlock x:Name="DeckModelRouteText" Text="Route: unset" Foreground="#DADAE2"
                                 FontSize="10" TextWrapping="Wrap" Margin="0,0,0,4" IsHitTestVisible="False"/>
                      <TextBlock Text="Brain tier" Foreground="#B8B8C0" FontSize="10" Margin="0,0,0,2"/>
                      <ComboBox x:Name="DeckTierCombo" Height="24" FontSize="11" Width="200"
                                HorizontalAlignment="Left" Margin="0,0,0,4"
                                ItemContainerStyle="{StaticResource SlopChatComboBoxItem}"/>
                      <TextBlock Text="Model" Foreground="#B8B8C0" FontSize="10" Margin="0,0,0,2"/>
                      <ComboBox x:Name="DeckModelCombo" Height="24" FontSize="11" Width="220"
                                HorizontalAlignment="Left" Margin="0,0,0,4"
                                ItemContainerStyle="{StaticResource SlopChatComboBoxItem}"/>
                      <Button x:Name="DeckModelRefreshButton" Content="Refresh models" Width="120" Height="24"
                              FontSize="10" Background="#F2263348" Foreground="#EAEAEA"
                              BorderBrush="#55FFFFFF" BorderThickness="1" Cursor="Hand"
                              AutomationProperties.Name="Refresh model catalog" Margin="0,0,0,4"/>
                      <Button x:Name="DeckModelSaveButton" Content="Save model" Width="100" Height="24"
                              FontSize="10" Background="#F24F46E5" Foreground="#FFFFFF"
                              BorderBrush="#55FFFFFF" BorderThickness="1" Cursor="Hand"
                              AutomationProperties.Name="Save deck model settings"/>
                    </StackPanel>
                  </Border>
                  <Border CornerRadius="6" Background="#F2263348" BorderBrush="#44FFFFFF" BorderThickness="1"
                          Padding="6" Margin="0,0,0,6">
                    <StackPanel>
                      <TextBlock Text="Data" FontSize="11" FontWeight="SemiBold" Foreground="#A5B4FC" Margin="0,0,0,4"/>
                      <TextBlock Text="Config location (read-only)" Foreground="#B8B8C0" FontSize="10" Margin="0,0,0,2"/>
                      <TextBlock x:Name="DeckDataPathText" Text="unavailable" Foreground="#93A4BD"
                                 FontSize="10" TextWrapping="Wrap" IsHitTestVisible="False"/>
                    </StackPanel>
                  </Border>
                </StackPanel>
                <StackPanel x:Name="DeckDataSection" Visibility="Collapsed">
                  <TextBlock Text="Data" FontSize="13" FontWeight="SemiBold" Foreground="#EAEAEA" Margin="0,0,0,6"/>
                  <TextBlock Text="Deletion scopes are confirmed before anything is removed."
                             Foreground="#B8B8C0" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,8"
                             IsHitTestVisible="False"/>
                  <Button x:Name="DeckDeleteConversationButton" Content="Delete conversation" Width="180" Height="26"
                          Margin="0,0,0,6" FontSize="11" Background="#F24F46E5" Foreground="#FFFFFF"
                          BorderBrush="#55FFFFFF" BorderThickness="1" Cursor="Hand"
                          AutomationProperties.Name="Delete conversation"/>
                  <Button x:Name="DeckDeleteSessionButton" Content="Delete OpenCode session" Width="180" Height="26"
                          Margin="0,0,0,6" FontSize="11" Background="#F2263348" Foreground="#EAEAEA"
                          BorderBrush="#55FFFFFF" BorderThickness="1" Cursor="Hand"
                          AutomationProperties.Name="Delete OpenCode session"/>
                  <Button x:Name="DeckDeleteLocalDataButton" Content="Delete local data" Width="180" Height="26"
                          Margin="0,0,0,8" FontSize="11" Background="#F2263348" Foreground="#EAEAEA"
                          BorderBrush="#55FFFFFF" BorderThickness="1" Cursor="Hand"
                          AutomationProperties.Name="Delete local data"/>
                </StackPanel>
                <StackPanel x:Name="DeckToolsSection" Visibility="Collapsed">
                  <TextBlock Text="Tools &amp; Skills" FontSize="13" FontWeight="SemiBold" Foreground="#EAEAEA" Margin="0,0,0,6"/>
                  <CheckBox x:Name="WorkspaceFilesToggle" Content="Workspace files" Foreground="#DADAE2" FontSize="11" Margin="0,0,0,4"/>
                  <CheckBox x:Name="WebAccessToggle" Content="Web access" Foreground="#DADAE2" FontSize="11" Margin="0,0,0,2"/>
                  <TextBlock x:Name="WebAccessDisclosureText"
                             Text="Can fetch web content; requests can reach beyond this PC."
                             Foreground="#93A4BD" FontSize="10" TextWrapping="Wrap" Margin="18,0,0,6"
                             IsHitTestVisible="False"/>
                  <CheckBox x:Name="ShellCommandsToggle" Content="Shell commands" Foreground="#DADAE2" FontSize="11" Margin="0,0,0,2"/>
                  <TextBlock x:Name="ShellCommandsDisclosureText"
                             Text="Can run shell commands that may change files on this PC."
                             Foreground="#93A4BD" FontSize="10" TextWrapping="Wrap" Margin="18,0,0,6"
                             IsHitTestVisible="False"/>
                  <CheckBox x:Name="SkillsPluginsToggle" Content="Skills and plugins" Foreground="#DADAE2" FontSize="11" Margin="0,0,0,4"/>
                  <CheckBox x:Name="SubagentsTasksToggle" Content="Subagents and tasks" Foreground="#DADAE2" FontSize="11" Margin="0,0,0,4"/>
                  <CheckBox x:Name="ExternalFoldersToggle" Content="External folders" Foreground="#DADAE2" FontSize="11" Margin="0,0,0,8"/>
                </StackPanel>
                <StackPanel x:Name="DeckUnderHoodSection" Visibility="Collapsed">
                  <TextBlock Text="Under the hood" FontSize="13" FontWeight="SemiBold" Foreground="#EAEAEA" Margin="0,0,0,6"/>
                  <TextBox x:Name="DeckUnderHoodText" IsReadOnly="True" IsReadOnlyCaretVisible="True"
                           AcceptsReturn="True" TextWrapping="Wrap" Height="180" FontSize="10"
                           Background="#F2263348" Foreground="#B8B8C0" BorderBrush="#44FFFFFF"
                           Padding="6,4" Text="Effective route and state appear here."/>
                </StackPanel>
                <StackPanel x:Name="DeckExitSection" Visibility="Collapsed">
                  <TextBlock Text="Exit" FontSize="13" FontWeight="SemiBold" Foreground="#EAEAEA" Margin="0,0,0,6"/>
                  <TextBlock Text="Say or type 'Sloppy, shutdown' to confirm before leaving."
                             Foreground="#B8B8C0" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,8"
                             IsHitTestVisible="False"/>
                  <Button x:Name="DeckShutdownButton" Content="Sloppy, shutdown" Width="180" Height="26"
                          Margin="0,0,0,6" FontSize="11" Background="#F24F46E5" Foreground="#FFFFFF"
                          BorderBrush="#55FFFFFF" BorderThickness="1" Cursor="Hand"
                          AutomationProperties.Name="Sloppy shutdown"/>
                </StackPanel>
            </StackPanel>
            <TextBlock x:Name="DeckStatusText" Grid.Row="1" Text="" Foreground="#93A4BD" FontSize="10"
                       TextWrapping="Wrap" Margin="0,6,0,0" IsHitTestVisible="False"/>
          </Grid>
        </Border>
      </Grid>
    </Border>
    <Grid Grid.Row="2" Margin="12,6,12,6">
      <ScrollViewer x:Name="ChatScroll" VerticalScrollBarVisibility="Auto"
                    HorizontalScrollBarVisibility="Disabled">
        <StackPanel x:Name="ChatStack"/>
      </ScrollViewer>
    </Grid>
    <Border x:Name="ChatInputChrome" Grid.Row="3" Margin="12,0,12,12" Padding="8" CornerRadius="10"
            Background="#F21E293B" BorderBrush="#44FFFFFF" BorderThickness="1">
      <StackPanel>
        <WrapPanel x:Name="ShortcutsStrip" Margin="0,0,0,6"/>
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <TextBox x:Name="InputBox" Height="32" FontSize="13" Padding="7,4"
                   Background="#F2263348" Foreground="#EAEAEA" BorderBrush="#8893A4BD"
                   VerticalContentAlignment="Center"/>
          <TextBlock x:Name="InputPlaceholder" Grid.Column="0" Text="Say something..."
                     Foreground="#93A4BD" FontSize="13" Margin="11,0,0,0"
                     VerticalAlignment="Center" IsHitTestVisible="False"/>
          <Button x:Name="MicBtn" Grid.Column="1" Content="🎤" Width="34" Height="32"
                  Margin="6,0,0,0" Background="#F24F46E5" Foreground="#FFFFFF"
                  BorderBrush="#55FFFFFF" BorderThickness="1" Cursor="Hand"
                  AutomationProperties.Name="Voice input"/>
          <Button x:Name="SendBtn" Grid.Column="2" Content="Send" Width="54" Height="32"
                  Margin="6,0,0,0" Background="#F24F46E5" Foreground="#FFFFFF"
                  BorderBrush="#55FFFFFF" BorderThickness="1" Cursor="Hand"
                  AutomationProperties.Name="Send message"/>
          <Button x:Name="StopBtn" Grid.Column="3" Content="Stop" Width="54" Height="32"
                  Margin="6,0,0,0" Visibility="Collapsed" Background="#F24F46E5"
                  Foreground="#FFFFFF" BorderBrush="#55FFFFFF" BorderThickness="1"
                  Cursor="Hand" AutomationProperties.Name="Stop request"/>
        </Grid>
      </StackPanel>
    </Border>
  </Grid>
</Window>
'@
}
