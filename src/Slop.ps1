#requires -Version 7.6
# S.L.O.P. — WPF desktop companion for the local OpenCode service.
# Launch: pwsh -STA -NoProfile -File src/Slop.ps1
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Windows.Forms
. (Join-Path $PSScriptRoot 'Slop.Motion.ps1')
. (Join-Path $PSScriptRoot 'Slop.Sense.ps1')
. (Join-Path $PSScriptRoot 'Slop.Frame.ps1')
. (Join-Path $PSScriptRoot 'Slop.Face.ps1')
. (Join-Path $PSScriptRoot 'Slop.ChatWindow.ps1')
. (Join-Path $PSScriptRoot 'Slop.Lifecycle.ps1')
. (Join-Path $PSScriptRoot 'Slop.OpenCode.ps1')
# Sloppy companion modules. Order matters: Provider/Onboarding/Route depend on
# Config; Route also needs OpenCodeProfile, LocalModel and the OpenCode bridge.
. (Join-Path $PSScriptRoot 'Slop.Config.ps1')
. (Join-Path $PSScriptRoot 'Slop.Audio.ps1')
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'tools/slop-preflight.ps1')
. (Join-Path $PSScriptRoot 'Slop.LocalModel.ps1')
. (Join-Path $PSScriptRoot 'Slop.OpenCodeProfile.ps1')
. (Join-Path $PSScriptRoot 'Slop.Provider.ps1')
. (Join-Path $PSScriptRoot 'Slop.Onboarding.ps1')
. (Join-Path $PSScriptRoot 'Slop.Route.ps1')
. (Join-Path $PSScriptRoot 'Slop.Disclosure.ps1')
. (Join-Path $PSScriptRoot 'Slop.Surfaces.ps1')
# Disclosure acceptance is per app lifetime; never persisted.
$script:SlopDisclosureAccepted = $false
$script:VoiceInstallRoot = Get-SlopVoiceInstallRoot -InstallRoot (Split-Path $PSScriptRoot -Parent)

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="S.L.O.P."
        MinWidth="484" MinHeight="330" Width="484" Height="330"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ResizeMode="CanResize" ShowInTaskbar="False"
        WindowStartupLocation="Manual" UseLayoutRounding="True">
  <Window.Resources>
    <!-- Flat buttons still need hover / pressed / keyboard-focus affordances. -->
    <Style x:Key="SlopButton" TargetType="Button">
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="BorderBrush" Value="Transparent"/>
      <Style.Triggers>
        <Trigger Property="IsKeyboardFocused" Value="True">
          <Setter Property="BorderBrush" Value="#3B82F6"/>
        </Trigger>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter Property="BorderBrush" Value="#77FFFFFF"/>
          <Setter Property="Opacity" Value="0.92"/>
        </Trigger>
        <Trigger Property="IsPressed" Value="True">
          <Setter Property="BorderBrush" Value="#DDFFFFFF"/>
          <Setter Property="Opacity" Value="0.72"/>
        </Trigger>
      </Style.Triggers>
    </Style>
  </Window.Resources>
  <Canvas x:Name="Stage">
    <!-- Expanded frame (hidden until click) -->
    <!-- Organic body: path coordinates are WINDOW space, so the Path sits at Canvas origin.
         Round line joins/caps keep the outline smooth; no Aliased EdgeMode on curves. -->
    <Path x:Name="BodyPath"
          Fill="#D81E293B" Stroke="Transparent" StrokeThickness="0"
          StrokeLineJoin="Round" StrokeStartLineCap="Round" StrokeEndLineCap="Round"
          IsHitTestVisible="False" Opacity="0" Visibility="Collapsed"/>
    <!-- Glossy rim highlight along the upper-left arc, inset from the outline -->
    <Path x:Name="HeadHighlight"
          Stroke="#553B82F6" StrokeThickness="2" StrokeLineJoin="Round"
          StrokeStartLineCap="Round" StrokeEndLineCap="Round" IsHitTestVisible="False"
          Opacity="0" Visibility="Collapsed"/>

    <!-- Stable content layer: rounded clip keeps rectangular rows off the curve -->
    <Grid x:Name="Frame" Width="448" Height="294" Canvas.Left="10" Canvas.Top="10"
          Opacity="0" Visibility="Collapsed">
      <Grid.Clip>
        <!-- Inset from the tightened frame; SizeChanged rebuilds this for resized windows. -->
        <RectangleGeometry Rect="4,4,440,286" RadiusX="27" RadiusY="27"/>
      </Grid.Clip>
      <Grid.RowDefinitions>
        <RowDefinition Height="36"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <Border x:Name="DragHandle" Grid.Row="0" Background="Transparent" Cursor="SizeAll"/>
      <Canvas x:Name="ShapeGlyph" Width="8" Height="8" HorizontalAlignment="Left"
              VerticalAlignment="Center" Margin="16,0,0,0" IsHitTestVisible="False">
        <Ellipse x:Name="GlyphCircle" Width="8" Height="8" Fill="#3B82F6" Stroke="#CCFFFFFF" StrokeThickness="0.75" Visibility="Visible"/>
        <Rectangle x:Name="GlyphSquare" Width="8" Height="8" Fill="#3B82F6" Stroke="#CCFFFFFF" StrokeThickness="0.75" Visibility="Collapsed"/>
        <Polygon x:Name="GlyphTri" Points="4,0 8,8 0,8" Fill="#3B82F6" Stroke="#CCFFFFFF" StrokeThickness="0.75" Visibility="Collapsed"/>
        <Rectangle x:Name="GlyphRect" Width="8" Height="6" Canvas.Top="1" Fill="#3B82F6" Stroke="#CCFFFFFF" StrokeThickness="0.75" Visibility="Collapsed"/>
      </Canvas>
      <Rectangle x:Name="StatusDot" Width="8" Height="8" Fill="#3B82F6"
                 HorizontalAlignment="Left" VerticalAlignment="Center" Margin="28,0,0,0"
                 IsHitTestVisible="False"/>
      <TextBlock Text="S.L.O.P." Foreground="#EAEAEA" FontWeight="Bold" FontSize="13"
                 VerticalAlignment="Center" Margin="98,0,0,0" IsHitTestVisible="False"/>
      <!-- Always-visible disclosure: the real route, never just a tier label. -->
      <TextBlock x:Name="RouteBadge" Grid.Row="0" HorizontalAlignment="Left"
                 VerticalAlignment="Center" Margin="162,0,0,0" MaxWidth="206"
                 TextTrimming="CharacterEllipsis" FontSize="9" Foreground="#B8B8C0"
                 Text="Local · bundled · Qwen3.5-2B Q4_K_M"
                 AutomationProperties.Name="Local · bundled · Qwen3.5-2B Q4_K_M" IsHitTestVisible="False"/>
      <!-- Three faint embedded dots near the wide head shelf; revealed on hover -->
      <Border x:Name="ControlDots" Grid.Row="0" HorizontalAlignment="Right"
              VerticalAlignment="Center" Margin="0,0,14,0" Padding="3"
              Background="#221E293B" BorderBrush="#44FFFFFF" BorderThickness="1"
              CornerRadius="10" Opacity="0.6" SnapsToDevicePixels="True">
        <StackPanel Orientation="Horizontal">
          <Button x:Name="SettingsDot" Width="18" Height="18" Margin="0,0,4,0"
                  Style="{StaticResource SlopButton}" Background="#33BFDBFE"
                  BorderThickness="1" BorderBrush="#55FFFFFF" Cursor="Hand" FontSize="9" FontWeight="Bold"
                  Content="□" ToolTip="Open chat window" AutomationProperties.Name="Open chat window"/>
          <Button x:Name="PinDot" Width="18" Height="18" Margin="0,0,4,0"
                  Style="{StaticResource SlopButton}" Background="#33BFDBFE"
                  BorderThickness="1" BorderBrush="#55FFFFFF" Cursor="Hand" FontSize="9" FontWeight="Bold"
                  Content="_" ToolTip="Minimize to blob" AutomationProperties.Name="Collapse Slop to pea"/>
          <Button x:Name="CloseDot" Width="18" Height="18"
                  Style="{StaticResource SlopButton}" Background="#33BFDBFE"
                  BorderThickness="1" BorderBrush="#55FFFFFF" Cursor="Hand" FontSize="9" FontWeight="Bold"
                  Content="X" ToolTip="Minimize to tray" AutomationProperties.Name="Minimize Slop to tray"/>
        </StackPanel>
      </Border>
      <Border Grid.Row="1" Margin="24,12,24,8" CornerRadius="14" Background="#1AFFFFFF" BorderBrush="#33FFFFFF" BorderThickness="1">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>
          <WrapPanel x:Name="ShortcutsStrip" Grid.Row="0" Margin="8,6,8,2"/>
          <!-- Chat and the four quiet destinations share one cell. Only one is visible. -->
          <Grid Grid.Row="1">
            <ScrollViewer x:Name="ChatScroll" VerticalScrollBarVisibility="Auto" Margin="12">
              <StackPanel x:Name="ChatStack"/>
            </ScrollViewer>

            <StackPanel x:Name="SettingsPanel" Visibility="Collapsed" Margin="12" Background="#1AFFFFFF">
              <ScrollViewer VerticalScrollBarVisibility="Auto" MaxHeight="560">
                <StackPanel Margin="0,0,4,0">
                  <TextBlock Text="Settings" FontSize="14" FontWeight="SemiBold" Foreground="#EAEAEA" Margin="6,6,6,10"/>

                  <TextBlock Text="Companion" Foreground="#A5B4FC" FontSize="11" FontWeight="SemiBold" Margin="6,0,6,4"/>
                  <TextBlock Text="Name, colour and personality are set in Customize." Foreground="#B8B8C0" FontSize="11"
                             TextWrapping="Wrap" Margin="6,0,6,8"/>

                  <TextBlock Text="Brain" Foreground="#A5B4FC" FontSize="11" FontWeight="SemiBold" Margin="6,4,6,4"/>
                  <TextBlock Text="Effective route" Foreground="#B8B8C0" FontSize="11" Margin="6,0,6,2"/>
                  <TextBlock x:Name="SettingsRouteText" Foreground="#DADAE2" FontSize="11"
                             TextWrapping="Wrap" Margin="6,0,6,8"/>
                  <Expander Header="Advanced" Foreground="#B8B8C0" FontSize="11" IsExpanded="False" Margin="6,0,6,8">
                    <StackPanel Margin="8,4,0,4">
                      <TextBlock Text="Raw values for people who need them." Foreground="#93A4BD" FontSize="11"
                                 TextWrapping="Wrap" Margin="0,0,0,6"/>
                      <TextBlock Text="Model (synced to model/modelName)" Foreground="#B8B8C0" FontSize="11" Margin="0,0,0,2"/>
                      <TextBox x:Name="SettingsModelBox" Height="28" FontSize="11" IsReadOnly="True"
                               Margin="0,0,0,8" Padding="6,4"/>
                      <TextBlock Text="OpenCode base URL" Foreground="#B8B8C0" FontSize="11" Margin="0,0,0,2"/>
                      <TextBox x:Name="SettingsBaseUrlBox" Height="28" FontSize="11" IsReadOnly="True"
                               Margin="0,0,0,8" Padding="6,4"/>
                      <TextBlock Text="OpenCode agent id" Foreground="#B8B8C0" FontSize="11" Margin="0,0,0,2"/>
                      <TextBox x:Name="SettingsAgentIdBox" Height="28" FontSize="11" IsReadOnly="True"
                               Margin="0,0,0,8" Padding="6,4"/>
                    </StackPanel>
                  </Expander>

                  <TextBlock Text="Voice" Foreground="#A5B4FC" FontSize="11" FontWeight="SemiBold" Margin="6,4,6,4"/>
                  <CheckBox x:Name="VoiceEnabledCheck" Content="Voice input (local transcription, off by default)"
                            Foreground="#B8B8C0" FontSize="11" Margin="6,0,6,6"/>
                  <TextBlock Text="Language" Foreground="#B8B8C0" FontSize="11" Margin="6,0,6,2"/>
                  <ComboBox x:Name="VoiceLanguageCombo" Height="26" FontSize="11" Margin="6,0,6,6" Width="140"
                            HorizontalAlignment="Left"/>
                  <TextBlock Text="Max seconds" Foreground="#B8B8C0" FontSize="11" Margin="6,0,6,2"/>
                  <TextBox x:Name="VoiceMaxSecondsBox" Height="26" FontSize="11" Width="80" Margin="6,0,6,6"
                           HorizontalAlignment="Left" Padding="6,3" VerticalContentAlignment="Center"/>
                  <Button x:Name="VoiceRepairButton" Content="Repair voice" HorizontalAlignment="Left"
                          Style="{StaticResource SlopButton}" FontSize="11" Margin="6,0,6,6"
                          Background="#22FFFFFF" Foreground="#EAEAEA" Padding="10,4"/>
                  <TextBlock x:Name="VoiceReadyText" Text="Whisper readiness: unknown" Foreground="#93A4BD"
                             FontSize="11" TextWrapping="Wrap" Margin="6,0,6,10"/>

                  <Button x:Name="SettingsSaveButton" Content="Save" HorizontalAlignment="Left"
                          Style="{StaticResource SlopButton}" FontSize="11" Margin="6,0,6,6"
                          Background="#4F46E5" Foreground="White" Padding="10,4"/>
                  <TextBlock x:Name="SettingsStatusText" Text="" Foreground="#93A4BD" FontSize="11"
                             TextWrapping="Wrap" Margin="6,0,6,10"/>

                  <TextBlock Text="Startup behaviour" Foreground="#B8B8C0" FontSize="11" Margin="6,0,6,2"/>
                  <Button x:Name="AutostartButton" Content="Autostart: Off" HorizontalAlignment="Left"
                          Style="{StaticResource SlopButton}" FontSize="11" Margin="6,0,6,8"/>
                  <TextBlock Text="Data location: {app}\data (inside the folder you chose during setup)" Foreground="#93A4BD" FontSize="11"
                             TextWrapping="Wrap" Margin="6,0,6,10"/>
                  <TextBlock x:Name="AboutText" Text="About and version - Sloppy companion v1" Foreground="#93A4BD"
                             FontSize="11" TextWrapping="Wrap" Margin="6,0,6,8"/>
                  <Expander Header="Advanced / developer" Foreground="#B8B8C0" FontSize="11" IsExpanded="False" Margin="6,0,6,8">
                    <StackPanel x:Name="AdvancedStack" Margin="6,4,6,8"/>
                  </Expander>
                  <Button x:Name="SettingsBack" Content="Back to chat" HorizontalAlignment="Left"
                          Style="{StaticResource SlopButton}" FontSize="11" Margin="6,2,6,6"/>
                </StackPanel>
              </ScrollViewer>
            </StackPanel>

            <StackPanel x:Name="CustomizePanel" Visibility="Collapsed" Margin="12" Background="#1AFFFFFF">
              <ScrollViewer VerticalScrollBarVisibility="Auto" MaxHeight="560">
                <StackPanel Margin="0,0,4,0">
                  <TextBlock Text="Customize" FontSize="14" FontWeight="SemiBold" Foreground="#EAEAEA" Margin="6,6,6,10"/>
                  <TextBlock Text="This is the only place your name, colour, personality and persona text are edited."
                             Foreground="#93A4BD" FontSize="11" TextWrapping="Wrap" Margin="6,0,6,8"/>
                  <TextBlock Text="Name" Foreground="#B8B8C0" FontSize="11" Margin="6,0,6,2"/>
                  <TextBox x:Name="CustomizeNameBox" Height="28" FontSize="11" Margin="6,0,6,8" Padding="6,4"/>
                  <TextBlock Text="Colour" Foreground="#B8B8C0" FontSize="10" Margin="6,0,6,2"/>
                  <ComboBox x:Name="CustomizeColourCombo" Height="26" FontSize="11" Width="180"
                            HorizontalAlignment="Left" Margin="6,0,6,8"/>
                  <TextBlock Text="Personality" Foreground="#B8B8C0" FontSize="10" Margin="6,0,6,2"/>
                  <ComboBox x:Name="CustomizePersonalityCombo" Height="26" FontSize="11" Width="180"
                            HorizontalAlignment="Left" Margin="6,0,6,8"/>
                  <TextBlock Text="Persona text" Foreground="#B8B8C0" FontSize="11" Margin="6,4,6,2"/>
                  <TextBox x:Name="CustomizePersonaBox" Height="110" FontSize="10" AcceptsReturn="True"
                           TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Margin="6,0,6,8" Padding="6,4"/>
                  <Button x:Name="CustomizeSaveButton" Content="Save" HorizontalAlignment="Left"
                          Style="{StaticResource SlopButton}" FontSize="11" Margin="6,0,6,6"
                          Background="#4F46E5" Foreground="White" Padding="10,4"/>
                  <TextBlock x:Name="CustomizeStatusText" Text="" Foreground="#93A4BD" FontSize="10"
                             TextWrapping="Wrap" Margin="6,0,6,10"/>
                  <Button x:Name="CustomizeBack" Content="Back to chat" HorizontalAlignment="Left"
                          Style="{StaticResource SlopButton}" FontSize="10" Margin="6,2,6,6"/>
                </StackPanel>
              </ScrollViewer>
            </StackPanel>

            <StackPanel x:Name="BrainPanel" Visibility="Collapsed" Margin="12" Background="#1AFFFFFF">
              <ScrollViewer VerticalScrollBarVisibility="Auto" MaxHeight="560">
                <StackPanel Margin="0,0,4,0">
                  <TextBlock Text="Brain" FontSize="14" FontWeight="SemiBold" Foreground="#EAEAEA" Margin="6,6,6,10"/>
                  <TextBlock Text="Where answers come from" Foreground="#A5B4FC" FontSize="11" FontWeight="SemiBold"
                             Margin="6,0,6,4"/>
                  <TextBlock x:Name="BrainRouteText" Foreground="#DADAE2" FontSize="11" TextWrapping="Wrap" Margin="6,0,6,6"/>
                  <TextBlock x:Name="BrainEffectiveText" Foreground="#93A4BD" FontSize="11" TextWrapping="Wrap" Margin="6,0,6,6"/>
                  <TextBlock Text="Brain tier" Foreground="#B8B8C0" FontSize="11" Margin="6,4,6,2"/>
                  <ComboBox x:Name="BrainTypeCombo" Height="26" FontSize="11" Width="180" HorizontalAlignment="Left" Margin="6,0,6,6"/>
                  <Expander Header="Advanced" Foreground="#B8B8C0" FontSize="11" IsExpanded="False" Margin="6,0,6,8">
                    <StackPanel Margin="8,4,0,4">
                      <TextBlock Text="Raw values for people who need them." Foreground="#93A4BD" FontSize="11"
                                 TextWrapping="Wrap" Margin="0,0,0,6"/>
                      <TextBlock Text="Provider" Foreground="#B8B8C0" FontSize="11" Margin="0,0,0,2"/>
                      <TextBox x:Name="BrainProviderBox" Height="26" FontSize="11" Margin="0,0,0,8" Padding="6,3"/>
                      <TextBlock Text="Endpoint URL (custom, loopback only)" Foreground="#B8B8C0" FontSize="11" Margin="0,0,0,2"/>
                      <TextBox x:Name="BrainEndpointBox" Height="26" FontSize="11" Margin="0,0,0,8" Padding="6,3"/>
                      <TextBlock Text="Model" Foreground="#B8B8C0" FontSize="11" Margin="0,0,0,2"/>
                      <ComboBox x:Name="BrainModelBox" Height="26" FontSize="11" IsEditable="True" Margin="0,0,0,8" Padding="6,3" Width="220" HorizontalAlignment="Left"/>
                      <TextBlock Text="Agent id" Foreground="#B8B8C0" FontSize="11" Margin="0,0,0,2"/>
                      <TextBox x:Name="BrainAgentIdBox" Height="26" FontSize="11" Margin="0,0,0,8" Padding="6,3"/>
                      <TextBlock Text="Capability profile" Foreground="#B8B8C0" FontSize="11" Margin="0,0,0,2"/>
                      <ComboBox x:Name="BrainProfileCombo" Height="26" FontSize="11" Width="180" HorizontalAlignment="Left" Margin="0,0,0,8"/>
                    </StackPanel>
                  </Expander>
                  <Button x:Name="BrainSaveButton" Content="Save" HorizontalAlignment="Left"
                          Style="{StaticResource SlopButton}" FontSize="11" Margin="6,0,6,6"
                          Background="#4F46E5" Foreground="White" Padding="10,4"/>
                  <TextBlock x:Name="BrainStatusText" Text="" Foreground="#93A4BD" FontSize="10"
                             TextWrapping="Wrap" Margin="6,0,6,10"/>
                  <Button x:Name="BrainBack" Content="Back to chat" HorizontalAlignment="Left"
                          Style="{StaticResource SlopButton}" FontSize="10" Margin="6,2,6,6"/>
                </StackPanel>
              </ScrollViewer>
            </StackPanel>

            <StackPanel x:Name="PrivacyPanel" Visibility="Collapsed" Margin="12" Background="#1AFFFFFF">
              <ScrollViewer VerticalScrollBarVisibility="Auto" MaxHeight="560">
                <StackPanel Margin="0,0,4,0">
                  <TextBlock Text="Privacy" FontSize="14" FontWeight="SemiBold" Foreground="#EAEAEA" Margin="6,6,6,10"/>
                  <TextBlock Text="Active data route" Foreground="#B8B8C0" FontSize="11" Margin="6,0,6,2"/>
                  <TextBlock x:Name="PrivacyRouteText" Foreground="#DADAE2" FontSize="11" TextWrapping="Wrap"
                             MaxHeight="110" Margin="6,0,6,8"/>
                  <TextBlock x:Name="PrivacyTermsLink" Foreground="#93C5FD" FontSize="11" TextWrapping="Wrap"
                             Visibility="Collapsed" Margin="6,0,6,8"/>
                  <TextBlock Text="Deletion scopes" Foreground="#B8B8C0" FontSize="11" Margin="6,4,6,2"/>
                  <TextBlock x:Name="PrivacyConversationCopy" Foreground="#93A4BD" FontSize="11" TextWrapping="Wrap" Margin="6,0,6,4"/>
                  <TextBlock x:Name="PrivacySessionCopy" Foreground="#93A4BD" FontSize="11" TextWrapping="Wrap" Margin="6,0,6,4"/>
                  <TextBlock x:Name="PrivacyLocalDataCopy" Foreground="#93A4BD" FontSize="11" TextWrapping="Wrap" Margin="6,0,6,8"/>
                  <TextBlock Text="Deletion actions" Foreground="#B8B8C0" FontSize="11" Margin="6,4,6,2"/>
                  <TextBlock Text="These actions cannot be undone." Foreground="#93A4BD" FontSize="11"
                             TextWrapping="Wrap" Margin="6,0,6,6"/>
                  <Button x:Name="DeleteConversationButton" Content="Clear conversation" HorizontalAlignment="Left"
                          Style="{StaticResource SlopButton}" FontSize="11" Margin="6,0,6,6"/>
                  <Button x:Name="DeleteSessionButton" Content="Delete OpenCode session" HorizontalAlignment="Left"
                          Style="{StaticResource SlopButton}" FontSize="11" Margin="6,0,6,6"/>
                  <Button x:Name="DeleteLocalDataButton" Content="Clear Sloppy local data" HorizontalAlignment="Left"
                          Style="{StaticResource SlopButton}" FontSize="11" Margin="6,0,6,8"/>
                  <TextBlock x:Name="PrivacyStatusText" Text="" Foreground="#93A4BD" FontSize="11"
                             TextWrapping="Wrap" Margin="6,0,6,10"/>
                  <Button x:Name="PrivacyBack" Content="Back to chat" HorizontalAlignment="Left"
                          Style="{StaticResource SlopButton}" FontSize="11" Margin="6,2,6,6"/>
                </StackPanel>
              </ScrollViewer>
            </StackPanel>
          </Grid>
        </Grid>
      </Border>
      <Border x:Name="InputTile" Grid.Row="2" Background="#1EFFFFFF"
              BorderBrush="#33FFFFFF" BorderThickness="1" Padding="12"
              Margin="24,8,24,20" CornerRadius="14" SnapsToDevicePixels="True">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <Grid Grid.Column="0">
            <TextBox x:Name="InputBox" Height="34" FontSize="12"
                     Background="#18FFFFFF" Foreground="#EAEAEA" BorderBrush="#33FFFFFF"
                     CaretBrush="#EAEAEA" Padding="6,4" AcceptsReturn="False"
                     VerticalContentAlignment="Center"
                     ToolTip="Type a message, then press Enter to send"/>
            <TextBlock x:Name="InputPlaceholder" Text="Ask something…" FontSize="12"
                       Foreground="#77EAEAEA" VerticalAlignment="Center" Margin="7,0,0,0"
                       IsHitTestVisible="False"/>
          </Grid>
          <Button x:Name="MicBtn" Grid.Column="1" Content="🎤" Style="{StaticResource SlopButton}"
                  Width="28" Height="34" Margin="6,0,0,0" Background="Transparent" Foreground="#AAA"
                  Cursor="Hand" FontSize="13" ToolTip="Record a short voice note (click to start/stop)"/>
          <Button x:Name="StopBtn" Grid.Column="2" Content="■" Style="{StaticResource SlopButton}"
                  Width="40" Height="34" Margin="6,0,0,0" Background="#7F1D1D" Foreground="White"
                  Cursor="Hand" FontSize="11" Visibility="Collapsed"/>
          <Button x:Name="SendBtn" Grid.Column="3" Content="Send" Style="{StaticResource SlopButton}"
                  Width="64" Height="34" Margin="6,0,0,0" Background="#3B82F6" Foreground="White"
                  Cursor="Hand" FontWeight="SemiBold" FontSize="12"/>
        </Grid>
      </Border>
    </Grid>

    <!-- Outline is the outermost layer: transparent fill, visible stroke. -->
    <Path x:Name="OutlinePath"
          Fill="Transparent" Stroke="#CC3B82F6" StrokeThickness="3"
          StrokeLineJoin="Round" StrokeStartLineCap="Round" StrokeEndLineCap="Round"
          IsHitTestVisible="False" Opacity="0" Visibility="Collapsed"/>

    <!-- Bottom-right resize grip for growing the conversation workspace -->
    <Border x:Name="ResizeGrip" Width="16" Height="16" Canvas.Right="0" Canvas.Bottom="0"
            Background="Transparent" Cursor="SizeNWSE" ToolTip="Resize"/>


    <!-- Idle pea shapes (only one visible) -->
    <Canvas x:Name="PeaCanvas" Width="26" Height="26" Canvas.Left="229" Canvas.Top="292" Cursor="Hand">
      <Rectangle x:Name="ShapeSquare" Width="26" Height="26" Fill="#3B82F6" Visibility="Visible" RenderTransformOrigin="0.5,0.5">
        <Rectangle.RenderTransform><ScaleTransform ScaleX="1" ScaleY="1"/></Rectangle.RenderTransform>
        <Rectangle.Effect><DropShadowEffect Color="#000" BlurRadius="4" ShadowDepth="2" Opacity="0.5"/></Rectangle.Effect>
      </Rectangle>
      <Ellipse x:Name="ShapeCircle" Width="26" Height="26" Fill="#3B82F6" Visibility="Collapsed" RenderTransformOrigin="0.5,0.5">
        <Ellipse.RenderTransform><ScaleTransform ScaleX="1" ScaleY="1"/></Ellipse.RenderTransform>
        <Ellipse.Effect><DropShadowEffect Color="#000" BlurRadius="4" ShadowDepth="2" Opacity="0.5"/></Ellipse.Effect>
      </Ellipse>
      <Polygon x:Name="ShapeTri" Points="13,0 26,26 0,26" Fill="#3B82F6" Visibility="Collapsed" RenderTransformOrigin="0.5,0.5">
        <Polygon.RenderTransform><ScaleTransform ScaleX="1" ScaleY="1"/></Polygon.RenderTransform>
        <Polygon.Effect><DropShadowEffect Color="#000" BlurRadius="4" ShadowDepth="2" Opacity="0.5"/></Polygon.Effect>
      </Polygon>
      <Rectangle x:Name="ShapeRect" Width="26" Height="18" Canvas.Left="0" Canvas.Top="4" Fill="#3B82F6" Visibility="Collapsed" RenderTransformOrigin="0.5,0.5">
        <Rectangle.RenderTransform><ScaleTransform ScaleX="1" ScaleY="1"/></Rectangle.RenderTransform>
        <Rectangle.Effect><DropShadowEffect Color="#000" BlurRadius="4" ShadowDepth="2" Opacity="0.5"/></Rectangle.Effect>
      </Rectangle>
      <Rectangle Width="5" Height="4" Canvas.Left="5" Canvas.Top="4" Fill="#BFDBFE" Opacity="0.7" IsHitTestVisible="False"/>
      <Rectangle Width="3" Height="2" Canvas.Left="18" Canvas.Top="18" Fill="#1E3A8A" Opacity="0.5" IsHitTestVisible="False"/>
    </Canvas>

    <Ellipse x:Name="GroundShadow" Width="30" Height="8" Canvas.Left="227" Canvas.Top="316" Fill="#000" Opacity="0.4" IsHitTestVisible="False">
      <Ellipse.Effect><BlurEffect Radius="4"/></Ellipse.Effect>
    </Ellipse>
  </Canvas>
</Window>
'@

$window = [System.Windows.Markup.XamlReader]::Parse($xaml)
$window.Dispatcher.Add_UnhandledException({ param($s,$e) Write-Warning $e.Exception.Message; $e.Handled = $true })

$Frame = $window.FindName('Frame')
$StatusDot = $window.FindName('StatusDot')
$RouteBadge = $window.FindName('RouteBadge')
$DragHandle = $window.FindName('DragHandle')
$BodyPath = $window.FindName('BodyPath')
$OutlinePath = $window.FindName('OutlinePath')
$HeadHighlight = $window.FindName('HeadHighlight')
$SettingsDot = $window.FindName('SettingsDot')
$PinDot = $window.FindName('PinDot')
$CloseDot = $window.FindName('CloseDot')
$ControlDots = $window.FindName('ControlDots')
$ResizeGrip = $window.FindName('ResizeGrip')
$ChatScroll = $window.FindName('ChatScroll')
$ChatStack = $window.FindName('ChatStack')
$ShortcutsStrip = $window.FindName('ShortcutsStrip')
# Four quiet destinations. All are collapsed except the active one (or chat).
$SettingsPanel = $window.FindName('SettingsPanel')
$CustomizePanel = $window.FindName('CustomizePanel')
$BrainPanel = $window.FindName('BrainPanel')
$PrivacyPanel = $window.FindName('PrivacyPanel')
$AdvancedStack = $window.FindName('AdvancedStack')
$AutostartButton = $window.FindName('AutostartButton')
$DeleteConversationButton = $window.FindName('DeleteConversationButton')
$DeleteSessionButton = $window.FindName('DeleteSessionButton')
$DeleteLocalDataButton = $window.FindName('DeleteLocalDataButton')
$SettingsRouteText = $window.FindName('SettingsRouteText')
$SettingsModelBox = $window.FindName('SettingsModelBox')
$SettingsBaseUrlBox = $window.FindName('SettingsBaseUrlBox')
$SettingsAgentIdBox = $window.FindName('SettingsAgentIdBox')
$VoiceEnabledCheck = $window.FindName('VoiceEnabledCheck')
$VoiceLanguageCombo = $window.FindName('VoiceLanguageCombo')
$VoiceMaxSecondsBox = $window.FindName('VoiceMaxSecondsBox')
$VoiceRepairButton = $window.FindName('VoiceRepairButton')
$VoiceReadyText = $window.FindName('VoiceReadyText')
foreach ($language in Get-SlopWhisperLanguages) { $VoiceLanguageCombo.Items.Add($language) | Out-Null }
$SettingsSaveButton = $window.FindName('SettingsSaveButton')
$CustomizeNameBox = $window.FindName('CustomizeNameBox')
$CustomizeColourCombo = $window.FindName('CustomizeColourCombo')
$CustomizePersonalityCombo = $window.FindName('CustomizePersonalityCombo')
$CustomizePersonaBox = $window.FindName('CustomizePersonaBox')
$CustomizeSaveButton = $window.FindName('CustomizeSaveButton')
$BrainTypeCombo = $window.FindName('BrainTypeCombo')
$BrainProviderBox = $window.FindName('BrainProviderBox')
# BrainLocalityCombo and BrainTierCombo removed; tier is encoded in the brain choice.
$BrainEndpointBox = $window.FindName('BrainEndpointBox')
$BrainModelBox = $window.FindName('BrainModelBox')
$BrainAgentIdBox = $window.FindName('BrainAgentIdBox')
$BrainProfileCombo = $window.FindName('BrainProfileCombo')
$BrainSaveButton = $window.FindName('BrainSaveButton')
$BrainRouteText = $window.FindName('BrainRouteText')
$BrainEffectiveText = $window.FindName('BrainEffectiveText')
$PrivacyRouteText = $window.FindName('PrivacyRouteText')
$PrivacyTermsLink = $window.FindName('PrivacyTermsLink')
$PrivacyConversationCopy = $window.FindName('PrivacyConversationCopy')
$PrivacySessionCopy = $window.FindName('PrivacySessionCopy')
$PrivacyLocalDataCopy = $window.FindName('PrivacyLocalDataCopy')
$InputBox = $window.FindName('InputBox')
$InputPlaceholder = $window.FindName('InputPlaceholder')
$MicBtn = $window.FindName('MicBtn')
$SendBtn = $window.FindName('SendBtn')
$StopBtn = $window.FindName('StopBtn')
$PeaCanvas = $window.FindName('PeaCanvas')
$GroundShadow = $window.FindName('GroundShadow')

$GlyphCircle = $window.FindName('GlyphCircle')
$GlyphSquare = $window.FindName('GlyphSquare')
$GlyphTri = $window.FindName('GlyphTri')
$GlyphRect = $window.FindName('GlyphRect')
$script:GlyphShapes = @($GlyphCircle, $GlyphSquare, $GlyphTri, $GlyphRect)

$ShapeSquare = $window.FindName('ShapeSquare')
$ShapeCircle = $window.FindName('ShapeCircle')
$ShapeTri = $window.FindName('ShapeTri')
$ShapeRect = $window.FindName('ShapeRect')

# park on the primary monitor, top-left area so it is always visible
$script:WorkArea = [System.Windows.SystemParameters]::WorkArea
$window.Left = 100
$window.Top = 100

function Set-SlopPetRectInWorkArea {
    $wa = [System.Windows.SystemParameters]::WorkArea
    $r = Get-SlopWorkAreaClampedRect -Left $window.Left -Top $window.Top `
        -Width $window.ActualWidth -Height $window.ActualHeight -WorkArea $wa
    if ([Math]::Abs($window.Left - $r.Left) -gt 0.5 -or [Math]::Abs($window.Top - $r.Top) -gt 0.5) {
        $window.Left = $r.Left
        $window.Top = $r.Top
    }
}
$window.Add_LocationChanged({ Set-SlopPetRectInWorkArea })

$DragHandle.Add_MouseLeftButtonDown({ $window.DragMove() })

$script:resizeOrigin = $null
$ResizeGrip.Add_MouseLeftButtonDown({
    param($s, $e)
    $p = $e.GetPosition($window)
    $script:resizeOrigin = @($p.X, $p.Y, $window.ActualWidth, $window.ActualHeight)
    $ResizeGrip.CaptureMouse()
    $e.Handled = $true
})
$ResizeGrip.Add_MouseMove({
    param($s, $e)
    if (-not $script:resizeOrigin) { return }
    $p = $e.GetPosition($window)
    $wa = [System.Windows.SystemParameters]::WorkArea
    $maxW = [Math]::Min(1280.0, [double]$wa.Width)
    $maxH = [Math]::Min(1840.0, [double]$wa.Height)
    $window.Width  = [Math]::Max(468.0, [Math]::Min($maxW, $script:resizeOrigin[2] + ($p.X - $script:resizeOrigin[0])))
    $window.Height = [Math]::Max(314.0, [Math]::Min($maxH, $script:resizeOrigin[3] + ($p.Y - $script:resizeOrigin[1])))
})
$ResizeGrip.Add_MouseLeftButtonUp({
    param($s, $e)
    $script:resizeOrigin = $null
    $ResizeGrip.ReleaseMouseCapture()
    Set-SlopPetRectInWorkArea
})

function Update-SlopFrameClip {
    $Frame.Width = [Math]::Max(300.0, $window.ActualWidth - 20)
    $Frame.Height = [Math]::Max(200.0, $window.ActualHeight - 20)
    # Keep rectangular content inside the organic rounded body. The body radius
    # tracks 0.11*min(W,H); asymmetry and dents can push the edge inward, so we
    # inset a bit more and shrink the clip radius to avoid top/bottom corner cuts.
    $clipInset = 8.0
    $clipRadius = [Math]::Max(24.0, 0.11 * [Math]::Min($Frame.Width, $Frame.Height) - 10.0)
    $clipRect = [System.Windows.Rect]::new($clipInset, $clipInset,
        [Math]::Max(10.0, $Frame.Width - 2*$clipInset), [Math]::Max(10.0, $Frame.Height - 2*$clipInset))
    $Frame.Clip = [System.Windows.Media.RectangleGeometry]::new($clipRect, $clipRadius, $clipRadius)
    if ($script:Membrane) { $script:Membrane.SetFrame([float]$Frame.Width, [float]$Frame.Height) }
}

# The idle pea and its shadow must stay inside the window at every size.
# Hardcoded coordinates were left behind when the window was shrunk, which
# clipped the only visible collapsed element entirely.
function Update-PeaAnchor {
    $w = [Math]::Max(26.0, $window.ActualWidth)
    $h = [Math]::Max(26.0, $window.ActualHeight)
    [System.Windows.Controls.Canvas]::SetLeft($PeaCanvas, ($w - 26.0) / 2.0)
    [System.Windows.Controls.Canvas]::SetTop($PeaCanvas, [Math]::Max(0.0, $h - 38.0))
    [System.Windows.Controls.Canvas]::SetLeft($GroundShadow, ($w - 30.0) / 2.0)
    [System.Windows.Controls.Canvas]::SetTop($GroundShadow, [Math]::Max(0.0, $h - 14.0))
}

# Growth origin used by the membrane: the pea's centre in window coordinates.
function Get-SlopPeaOrigin {
    $w = [Math]::Max(26.0, $window.ActualWidth)
    $h = [Math]::Max(26.0, $window.ActualHeight)
    return @(([float](($w - 26.0) / 2.0 + 13.0)), ([float]([Math]::Max(0.0, $h - 38.0) + 13.0)))
}

# The particle layer follows whichever region is visible: a small rounded
# square around the compact pea, or the membrane's own window-space path when
# expanded. Called from mode/size hooks and once per tick so the clip follows
# the body as it grows.
function Update-SlopFaceRegion {
    if (-not $script:FaceLayer) { return }
    $layer = $script:FaceLayer
    if (-not $layer.Parent) {
        $idx = $Stage.Children.IndexOf($Frame)
        if ($idx -lt 0) { $idx = 0 }
        $Stage.Children.Insert($idx, $layer)
    }
    # The pea is the pet's only face surface now; chat has its own window, so
    # the particle field always uses the compact aura around the pea.
    $w = 72.0
    $h = 72.0
    $px = [System.Windows.Controls.Canvas]::GetLeft($PeaCanvas)
    $py = [System.Windows.Controls.Canvas]::GetTop($PeaCanvas)
    if ([double]::IsNaN($px)) { $px = ([Math]::Max(26.0, $window.ActualWidth) - 26.0) / 2.0 }
    if ([double]::IsNaN($py)) { $py = [Math]::Max(0.0, [Math]::Max(26.0, $window.ActualHeight) - 38.0) }
    $layer.Width = $w
    $layer.Height = $h
    [System.Windows.Controls.Canvas]::SetLeft($layer, $px + 13.0 - $w / 2.0)
    [System.Windows.Controls.Canvas]::SetTop($layer, $py + 13.0 - $h / 2.0)
    $layer.Clip = [System.Windows.Media.RectangleGeometry]::new(
        [System.Windows.Rect]::new(0.0, 0.0, $w, $h), 12.0, 12.0)
    $script:FaceRegion = @{ Width = $w; Height = $h }
}

$window.Add_SizeChanged({
    param($s, $e)
    $script:WorkArea = [System.Windows.SystemParameters]::WorkArea
    # 10 px of goo room on every side, matching the frame engine's margin.
    Update-SlopFrameClip
    Update-PeaAnchor
    Update-SlopFaceRegion
})
# Chat lives in its own transparent window. The pet keeps its compact surface
# and position; these variables are the only owners of chat-window state.
$script:ChatWindow = $null
$script:ChatMode = 'Extended'
$script:PetControls = @{}

function Set-SlopPetChatInteraction {
    param([bool]$ChatOpen)
    $state = Get-SlopPetInteractionState -ChatOpen $ChatOpen
    $PeaCanvas.IsHitTestVisible = [bool]$state.IsHitTestVisible
    $window.Topmost = [bool]$state.Topmost
    $DragHandle.Cursor = $state.Cursor
    $ControlDots.IsHitTestVisible = [bool]$state.IsHitTestVisible
}

function Save-SlopMainChatControls {
    $script:PetControls = @{
        ChatScroll = $ChatScroll; ChatStack = $ChatStack
        ShortcutsStrip = $ShortcutsStrip; InputBox = $InputBox
        InputPlaceholder = $InputPlaceholder; MicBtn = $MicBtn
        SendBtn = $SendBtn; StopBtn = $StopBtn
    }
}
Save-SlopMainChatControls

function Move-SlopChatBubbles {
    param([Parameter(Mandatory)]$From, [Parameter(Mandatory)]$To)
    if ($From -eq $To) { return }
    foreach ($child in @($From.Children)) {
        $From.Children.Remove($child) | Out-Null
        $To.Children.Add($child) | Out-Null
    }
}

function Use-SlopChatControls {
    param([Parameter(Mandatory)]$Target)
    $script:ChatScroll = $Target.FindName('ChatScroll')
    $script:ChatStack = $Target.FindName('ChatStack')
    $script:ShortcutsStrip = $Target.FindName('ShortcutsStrip')
    $script:InputBox = $Target.FindName('InputBox')
    $script:InputPlaceholder = $Target.FindName('InputPlaceholder')
    $script:MicBtn = $Target.FindName('MicBtn')
    $script:SendBtn = $Target.FindName('SendBtn')
    $script:StopBtn = $Target.FindName('StopBtn')
    Move-SlopChatBubbles -From $script:PetControls.ChatStack -To $script:ChatStack
}

function Restore-SlopMainChatControls {
    $previousStack = $script:ChatStack
    $script:ChatScroll = $script:PetControls.ChatScroll
    $script:ChatStack = $script:PetControls.ChatStack
    $script:ShortcutsStrip = $script:PetControls.ShortcutsStrip
    $script:InputBox = $script:PetControls.InputBox
    $script:InputPlaceholder = $script:PetControls.InputPlaceholder
    $script:MicBtn = $script:PetControls.MicBtn
    $script:SendBtn = $script:PetControls.SendBtn
    $script:StopBtn = $script:PetControls.StopBtn
    Move-SlopChatBubbles -From $previousStack -To $script:ChatStack
}

$SettingsDot.Add_Click({ Open-SlopChatWindow })
$PinDot.Add_Click({ Collapse-Chat })
$CloseDot.Add_Click({ Minimize-ToTray })
$ControlDots.Add_MouseEnter({ $ControlDots.Opacity = 0.95 })
$ControlDots.Add_MouseLeave({ $ControlDots.Opacity = 0.6 })

# --- State ---
$script:IsStreaming = $false
$script:Failed = $false
$script:CurrentAssistantText = ''
$script:CurrentAssistantBlock = $null
$script:Timer = $null
$script:CurrentJob = $null
$script:Cts = $null
$script:RequestState = New-SlopRequestState
$script:RequestTimeoutSeconds = 300
if ($env:SLOP_REQUEST_TIMEOUT_SECONDS) {
    [int]$parsedTimeout = 0
    if ([int]::TryParse($env:SLOP_REQUEST_TIMEOUT_SECONDS, [ref]$parsedTimeout) -and $parsedTimeout -gt 0) {
        $script:RequestTimeoutSeconds = $parsedTimeout
    }
}
$script:Pinned = $false
# canonical order matches $SlopShapeIndex: circle, square, triangle, rect
$script:Shapes = @($ShapeCircle,$ShapeSquare,$ShapeTri,$ShapeRect)

# OpenCode bridge state. The password is read from the environment only when a
# request starts; it is never stored in a URL, a job argument string, or a log.
$script:OpenCodeSessionId = $null
$script:OpenCodePending = @{}          # requestID -> generation, for the in-chat approval cards
$script:OpenCodeBaseUrl = $(if ($env:OPENCODE_BASE_URL) { $env:OPENCODE_BASE_URL } else { 'http://127.0.0.1:28894' })
$script:OpenCodeSideJobs = [Collections.Generic.List[object]]::new()

function Remove-SlopCompletedSideJobs {
    foreach ($j in @($script:OpenCodeSideJobs)) {
        if ($j.State -eq 'Completed' -or $j.State -eq 'Failed') {
            Remove-Job $j -Force -ErrorAction SilentlyContinue
            $script:OpenCodeSideJobs.Remove($j) | Out-Null
        }
    }
}

function Animate-BrushTo {
    param(
        [Parameter(Mandatory)][System.Windows.Media.SolidColorBrush]$Brush,
        [Parameter(Mandatory)][System.Windows.Media.Color]$Color
    )
    $anim = [System.Windows.Media.Animation.ColorAnimation]::new($Color, [TimeSpan]::FromMilliseconds(160))
    $anim.EasingFunction = [System.Windows.Media.Animation.CubicEase]::new()
    $Brush.BeginAnimation([System.Windows.Media.SolidColorBrush]::ColorProperty, $anim)
}

function Set-SlopVisualFromSignal {
    param([Parameter(Mandatory)][hashtable]$Signal)
    $new = [System.Windows.Media.BrushConverter]::new().ConvertFromString($SlopColors[$Signal.Color]).Color
    foreach ($b in $script:ColorBrushes) { Animate-BrushTo -Brush $b -Color $new }
    if ($script:HighlightBrush) {
        $highlightColor = [System.Windows.Media.Color]::FromArgb(0x55, $new.R, $new.G, $new.B)
        Animate-BrushTo -Brush $script:HighlightBrush -Color $highlightColor
    }
    $StatusDot.ToolTip = $Signal.Status
    $idx = $SlopShapeIndex[$Signal.Shape]
    for ($i = 0; $i -lt 4; $i++) {
        $script:GlyphShapes[$i].Visibility = if ($i -eq $idx) { 'Visible' } else { 'Collapsed' }
    }
    # keep the existing success/error motion pulse, now driven by the signal color.
    # 'working' reuses the thinking motion feel.
    $mood = if ($Signal.Color -eq 'working') { 'thinking' } else { $Signal.Color }
    Set-SlopMotionMood -State $script:Motion -Mood $mood
}

function Get-ShapeTransform {
    param($shape)
    $g = $shape.RenderTransform -as [System.Windows.Media.TransformGroup]
    if (-not $g) {
        $g = [System.Windows.Media.TransformGroup]::new()
        $g.Children.Add([System.Windows.Media.ScaleTransform]::new(1,1)) | Out-Null
        $g.Children.Add([System.Windows.Media.RotateTransform]::new(0)) | Out-Null
        $shape.RenderTransform = $g
        $shape.RenderTransformOrigin = [System.Windows.Point]::new(0.5,0.5)
    }
    return $g
}

function Initialize-MotionVisuals {
    $GroundShadow.RenderTransformOrigin = [System.Windows.Point]::new(0.5,0.5)
    $GroundShadow.RenderTransform = [System.Windows.Media.ScaleTransform]::new(1,1)
    $PeaCanvas.RenderTransform = [System.Windows.Media.TranslateTransform]::new(0,0)
    $script:PeaTranslate = $PeaCanvas.RenderTransform -as [System.Windows.Media.TranslateTransform]
    $script:ShadowScaleTransform = $GroundShadow.RenderTransform -as [System.Windows.Media.ScaleTransform]
    if (-not $script:PeaTranslate -or -not $script:ShadowScaleTransform) {
        throw 'motion transforms were not initialized'
    }

    $initial = [System.Windows.Media.BrushConverter]::new().ConvertFromString($SlopColors['idle']).Color
    $script:ColorBrushes = @()
    foreach ($shape in $script:Shapes) {
        $shape.Fill = [System.Windows.Media.SolidColorBrush]::new($initial)
        $script:ColorBrushes += $shape.Fill
    }
    $StatusDot.Fill = [System.Windows.Media.SolidColorBrush]::new($initial)
    $script:ColorBrushes += $StatusDot.Fill
    $BodyPath.Stroke = [System.Windows.Media.SolidColorBrush]::new($initial)
    $script:ColorBrushes += $BodyPath.Stroke
    # Keep the translucent rim highlight in the same palette without putting a
    # 0x55-alpha brush into the full-opacity animation group.
    $highlightColor = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#553B82F6').Color
    $script:HighlightBrush = [System.Windows.Media.SolidColorBrush]::new($highlightColor)
    $HeadHighlight.Stroke = $script:HighlightBrush
    foreach ($g in $script:GlyphShapes) {
        $g.Fill = [System.Windows.Media.SolidColorBrush]::new($initial)
        $script:ColorBrushes += $g.Fill
    }
}

function Apply-SlopMotion {
    param([double]$Dt = 0.033)
    $m = $script:Motion
    $changed = Sync-SlopSignal -State $script:Motion
    if ($changed) { Set-SlopVisualFromSignal -Signal $changed }
    $sx = 1.0 / [Math]::Max(0.4, $m.Squash.Value)
    $sy = $m.Squash.Value + $m.Wobble.Value
    $angle = $m.Lean.Value

    for ($i = 0; $i -lt 4; $i++) {
        $shape = $script:Shapes[$i]
        $w = [Math]::Min(1.0, [Math]::Max(0.0, $m.Weights[$i].Value))
        $shape.Opacity = $w
        $shape.Visibility = if ($w -gt 0.01) { 'Visible' } else { 'Collapsed' }
        $g = Get-ShapeTransform $shape
        # fade and shrink together: outgoing shape collapses as it disappears
        $g.Children[0].ScaleX = $sx * $m.Puff.Value * $w
        $g.Children[0].ScaleY = $sy * $m.Puff.Value * $w
        $g.Children[1].Angle = $angle
    }

    $x = if ($script:ReducedMotion) { 0.0 } else { 1.6 * [Math]::Sin([DateTime]::UtcNow.Ticks / 10000000.0 * 0.9) }
    $script:PeaTranslate.X = $x
    $script:PeaTranslate.Y = $m.Y

    $script:ShadowScaleTransform.ScaleX = $m.ShadowScale.Value
    $script:ShadowScaleTransform.ScaleY = 1.0
    $GroundShadow.Opacity = $m.ShadowAlpha.Value

    # OpenPulse is already stepped in Update-SlopMotionState; render it here
    # instead of adding a new membrane/C# pulse API.
    $BodyPath.StrokeThickness = 0.0
    $OutlinePath.StrokeThickness = 3.0 + 6.0 * $m.OpenPulse.Value

    # The membrane owns its physics and emits window-space path data. The signal
    # stack only selects a mood; it never transforms the content layer.
    # While fully collapsed the outline is invisible, so neither the C# physics
    # nor the WPF Geometry.Parse round trip needs to run.
    $bodyClosed = $script:Membrane.IsClosed
    $script:Membrane.Move([float]$window.Left, [float]$window.Top)
    if (-not $bodyClosed) { $script:Membrane.Update([float]$Dt) }
    $frameMood = [SlopFrame]::Idle
    if     ($m.Mood -eq 'thinking') { $frameMood = [SlopFrame]::Thinking }
    elseif ($m.Mood -eq 'success')  { $frameMood = [SlopFrame]::Happy }
    elseif ($m.Mood -eq 'error')    { $frameMood = [SlopFrame]::Alert }
    $script:Membrane.SetMood($frameMood)

    if ($bodyClosed -and $script:Frame.Opacity -lt 0.02) {
        $BodyPath.Visibility = 'Collapsed'
        $OutlinePath.Visibility = 'Collapsed'
        $HeadHighlight.Visibility = 'Collapsed'
        $Frame.Visibility = 'Collapsed'
        $PeaCanvas.Visibility = 'Visible'
    }
    else {
        if (-not $bodyClosed) {
            $BodyPath.Data = [System.Windows.Media.Geometry]::Parse($script:Membrane.Path)
            $BodyPath.Opacity = 1.0
            $BodyPath.Visibility = 'Visible'
            $OutlinePath.Data = $BodyPath.Data
            # BodyPath is fill-only, so the outline keeps its own XAML stroke brush.
            $OutlinePath.Opacity = 1.0
            $OutlinePath.Visibility = 'Visible'
            $hl = $script:Membrane.Highlight
            if ($hl) {
                $HeadHighlight.Data = [System.Windows.Media.Geometry]::Parse($hl)
                $HeadHighlight.Opacity = [Math]::Min(1.0, 0.55 + 0.10 * $m.OpenPulse.Value)
                $HeadHighlight.Visibility = 'Visible'
            }
            else { $HeadHighlight.Visibility = 'Collapsed' }
        }
        # Clip is rebuilt on resize (see SizeChanged); opacity follows the opening.
        $Frame.Opacity = [double]$script:Membrane.ContentOpacity
        $Frame.Visibility = 'Visible'
        $PeaCanvas.Visibility = 'Collapsed'
    }

    foreach ($child in $ChatStack.Children) {
        $tag = $child.Tag
        if ($tag -is [hashtable] -and $tag.ContainsKey('SlopEntrance')) {
            $child.Opacity = [Math]::Min(1.0, [Math]::Max(0.0, $tag.SlopEntrance.Value))
            $tag.SlopTransform.Y = $tag.SlopLift.Value
        }
    }
    if ($script:StreamTextSpring) {
        $script:CurrentAssistantBlock.Child.Opacity = [Math]::Min(1.0, [Math]::Max(0.0, $script:StreamTextSpring.Value))
    }
}

function Set-SlopChatWindowRect {
    param([ValidateSet('Extended','Full')][string]$Mode)
    if (-not $script:ChatWindow) { return }
    $r = Get-SlopChatWindowRect -PetLeft $window.Left -PetTop $window.Top `
        -WorkArea ([System.Windows.SystemParameters]::WorkArea) -Mode $Mode
    $script:ChatWindow.Left = $r.Left
    $script:ChatWindow.Top = $r.Top
    $script:ChatWindow.Width = $r.Width
    $script:ChatWindow.Height = $r.Height
    $script:ChatMode = $Mode
    $script:ChatWindow.FindName('ChatModeButton').Content = if ($Mode -eq 'Full') { '_' } else { '□' }
}

function Open-SlopChatWindow {
    if ($script:ChatWindow -and $script:ChatWindow.IsLoaded) {
        $script:ChatWindow.Activate()
        return
    }
    try {
        $chat = [System.Windows.Markup.XamlReader]::Parse((Get-SlopChatWindowXaml))
    } catch {
        Add-Bubble -Text "[error: chat window could not open: $($_.Exception.Message)]" -IsUser $false
        return
    }
    $script:ChatWindow = $chat
    $script:ChatMode = 'Extended'
    Use-SlopChatControls -Target $chat
    Initialize-SlopChatControlHandlers -Target $chat
    $chatRoot = $chat.FindName('ChatRoot')
    $chatScroll = $chat.FindName('ChatScroll')
    $chatRoot.Add_PreviewMouseWheel({
        param($s,$e)
        if ($s -ne $chatScroll) {
            $chatScroll.ScrollToVerticalOffset($chatScroll.VerticalOffset - [Math]::Sign($e.Delta) * 48.0)
            $e.Handled = $true
        }
    })
    Set-SlopChatWindowRect -Mode 'Extended'
    $chat.FindName('ChatModeButton').Add_Click({
        $newMode = if ($script:ChatMode -eq 'Full') { 'Extended' } else { 'Full' }
        Set-SlopChatWindowRect -Mode $newMode
    })
    $chat.FindName('ChatCloseButton').Add_Click({ Collapse-Chat })
    $script:ChatWindow.Add_Closed({
        $script:ChatWindow = $null
        Restore-SlopMainChatControls
        Set-SlopPetChatInteraction -ChatOpen $false
        Set-SlopBaseCondition -State $script:Motion -Streaming $false -ChatOpen $false -Stalled $false
    })
    Set-SlopPetChatInteraction -ChatOpen $true
    Set-SlopBaseCondition -State $script:Motion -Streaming $script:IsStreaming -ChatOpen $true -Stalled $false
    $chat.Show()
    $chat.FindName('InputBox').Focus() | Out-Null
}

function Expand-Chat { Open-SlopChatWindow }

function Request-StopStream {
    $gen = $script:RequestState.Generation
    if (-not $script:Cts -or $script:RequestState.Phase -in @('completed', 'finalized')) { return }
    $script:Cts.Cancel()
    Reject-SlopPendingApprovals -Generation $gen
    if ($script:OpenCodeSessionId) {
        $session = [uri]::EscapeDataString($script:OpenCodeSessionId)
        $url = "$($script:OpenCodeBaseUrl)/api/session/$session/interrupt"
        $job = Start-ThreadJob -ScriptBlock {
            param($Url, $Auth)
            try {
                $client = New-Object System.Net.Http.HttpClient
                $req = [Net.Http.HttpRequestMessage]::new('POST', $Url)
                foreach ($h in $Auth.GetEnumerator()) { $req.Headers.TryAddWithoutValidation($h.Key, $h.Value) | Out-Null }
                $client.SendAsync($req).GetAwaiter().GetResult() | Out-Null
            } catch { } finally { if ($client) { $client.Dispose() } }
        } -ArgumentList $url, (New-SlopOpenCodeAuthHeader)
        $script:OpenCodeSideJobs.Add($job)
    }
    # Drive the UI to a stable state on the next dispatcher tick instead of
    # waiting for the worker to notice cancellation. Late worker events are
    # ignored by the terminal-phase guard once Finish-Stream runs.
    if ($script:StreamQueue) {
        $script:StreamQueue.Enqueue('__ERR__Cancelled')
        $script:StreamQueue.Enqueue('__DONE__')
    }
}

function Collapse-Chat {
    Request-StopStream
    if ($script:ChatWindow) {
        $chat = $script:ChatWindow
        $script:ChatWindow = $null
        $chat.Close()
    }
    Restore-SlopMainChatControls
    Set-SlopPetChatInteraction -ChatOpen $false
    Set-SlopFrameTarget -State $script:Motion -Target 'closed'
    Set-SlopBaseCondition -State $script:Motion -Streaming $false -ChatOpen $false -Stalled $false
}

function Minimize-ToTray {
    if ($script:TrayIcon) { return }
    $script:TrayIcon = New-Object System.Windows.Forms.NotifyIcon
    $script:TrayIcon.Text = 'S.L.O.P.'
    $iconPath = Join-Path $PSScriptRoot 'assets\sloppy.ico'
    if (-not (Test-Path -LiteralPath $iconPath)) { $iconPath = Join-Path $PSScriptRoot '..\assets\sloppy.ico' }
    try {
        if (Test-Path -LiteralPath $iconPath) {
            $script:TrayIcon.Icon = [System.Drawing.Icon]::new($iconPath)
        } else {
            $script:TrayIcon.Icon = [System.Drawing.SystemIcons]::Application
        }
    } catch { $script:TrayIcon.Icon = [System.Drawing.SystemIcons]::Application }
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $restore = $menu.Items.Add('Restore')
    $restore.Add_Click({ $window.Show(); $window.WindowState = 'Normal'; $window.Activate(); Update-SlopFaceRegion })
    $senseLabel = if ($script:SenseEnabled) { 'System Sense: On' } else { 'System Sense: Off' }
    $script:TraySenseItem = $menu.Items.Add($senseLabel)
    $script:TraySenseItem.Add_Click({
        # Publish to script scope first: a WinForms Add_Click scriptblock does
        # not close over function locals in PowerShell.
        $script:SenseEnabled = -not $script:SenseEnabled
        Set-SlopSenseEnabled -Enabled $script:SenseEnabled
        $script:SenseAccumulator = 0.0
        if ($script:SenseEnabled) {
            $script:TraySenseItem.Text = 'System Sense: On'
            Add-SlopThoughtBubble -Text 'System Sense online — watching thresholds and listeners.'
        } else {
            $script:TraySenseItem.Text = 'System Sense: Off'
        }
    })
    $editItem = $menu.Items.Add('Edit personality')
    $editItem.Add_Click({ Show-SlopOnboarding -Config $script:SlopConfigResult.Config -StartScreen 3 | Out-Null })

    $brainItem = $menu.Items.Add('Change brain')
    $brainItem.Add_Click({ Show-SlopOnboarding -Config $script:SlopConfigResult.Config -StartScreen 4 | Out-Null })

    $script:TrayAutostartItem = $menu.Items.Add("Autostart: $(if ($script:SlopConfigResult.Config.autostart) { 'On' } else { 'Off' })")
    $script:TrayAutostartItem.Add_Click({
        $script:SlopConfigResult.Config.autostart = -not $script:SlopConfigResult.Config.autostart
        Write-SlopConfig -Config $script:SlopConfigResult.Config
        Sync-SlopAutostart -Enabled ([bool]$script:SlopConfigResult.Config.autostart)
        $script:TrayAutostartItem.Text = "Autostart: $(if ($script:SlopConfigResult.Config.autostart) { 'On' } else { 'Off' })"
    })

    $script:TrayModelItem = $menu.Items.Add('Sleep model')
    $script:TrayModelItem.Add_Click({
        if ($script:LocalModelProcess) {
            Stop-SlopLocalModel -Process $script:LocalModelProcess
            $script:LocalModelProcess = $null
            $script:TrayModelItem.Text = 'Wake model'
            Add-SlopThoughtBubble -Text 'The built-in brain is asleep. Send a message to wake it.'
        }
        else {
            $script:TrayModelItem.Text = 'Sleep model'
        }
    })

    $exit = $menu.Items.Add('Exit')
    $exit.Add_Click({ if ($script:TrayIcon) { $script:TrayIcon.Visible = $false; $script:TrayIcon.Dispose() }; Stop-Process -Id $PID -Force })
    $script:TrayIcon.ContextMenuStrip = $menu
    $script:TrayIcon.Visible = $true
    $script:TrayIcon.Add_DoubleClick({ $window.Show(); $window.WindowState = 'Normal'; $window.Activate(); Update-SlopFaceRegion })
    $window.Hide()
    Update-SlopFaceRegion
}

function Finish-Stream {
    param([Parameter(Mandatory)][int]$Generation)
    Clear-SlopSignalEvent -State $script:Motion -Id "request:${Generation}:phase" | Out-Null
    if ($script:Failed) { Reject-SlopPendingApprovals -Generation $Generation }
    else { Clear-SlopPendingApprovalCards -Generation $Generation }
    Remove-SlopCompletedSideJobs
    Set-SlopRequestFinalized -State $script:RequestState -Generation $Generation | Out-Null
    if ($script:Timer) { $script:Timer.Stop(); $script:Timer = $null }
    if ($script:CurrentJob) { Remove-Job $script:CurrentJob -Force -ErrorAction SilentlyContinue; $script:CurrentJob = $null }
    if ($script:Cts) { $script:Cts.Dispose(); $script:Cts = $null }
    $script:IsStreaming = $false
    $script:StreamTextSpring = $null
    Set-SlopBaseCondition -State $script:Motion -Streaming $false -ChatOpen ([bool]$script:ChatWindow) -Stalled $false
    $SendBtn.Visibility = 'Visible'
    $StopBtn.Visibility = 'Collapsed'
    $SendBtn.IsEnabled = $true
    Set-SlopMicUiState -State idle
    $InputBox.IsEnabled = $true
    # Do not pull focus back into a chat the user has already collapsed.
    if ($script:ChatWindow) { $InputBox.Focus() | Out-Null }
}

# Minimize to tray: hide the window and keep a NotifyIcon for restore.

$window.Add_KeyDown({ param($s,$e) if ($e.Key -eq [System.Windows.Input.Key]::Escape) { Collapse-Chat } })

# blob drag vs click
$script:blobPressPos = $null
$script:blobDragged = $false
$PeaCanvas.Add_MouseLeftButtonDown({
    $script:blobPressPos = [System.Windows.Input.Mouse]::GetPosition($window)
    $script:blobDragged = $false
    $PeaCanvas.CaptureMouse() | Out-Null
})
$PeaCanvas.Add_MouseMove({
    if ($PeaCanvas.IsMouseCaptured -and $script:blobPressPos -and -not $script:blobDragged) {
        $pos = [System.Windows.Input.Mouse]::GetPosition($window)
        if ([Math]::Abs($pos.X - $script:blobPressPos.X) -gt 4 -or [Math]::Abs($pos.Y - $script:blobPressPos.Y) -gt 4) {
            $script:blobDragged = $true
            $PeaCanvas.ReleaseMouseCapture()
            $window.DragMove()
        }
    }
})
$PeaCanvas.Add_MouseLeftButtonUp({
    $PeaCanvas.ReleaseMouseCapture()
    if (-not $script:blobDragged) { Expand-Chat }
    $script:blobPressPos = $null
})

# The badge is the honest route disclosure in the header. It follows the plan
# even when a remote send is cancelled, so the user always sees what was chosen.
function Set-SlopRouteBadge {
    param([Parameter(Mandatory)][hashtable]$StreamPlan)
    if (-not $StreamPlan.Badge) { return }
    $RouteBadge.Text = [string]$StreamPlan.Badge
    # UIA name follows the visible text, so screen readers and live probes read
    # the same honest route instead of a stale generic label.
    [System.Windows.Automation.AutomationProperties]::SetName($RouteBadge, $RouteBadge.Text)
    $RouteBadge.ToolTip = if ($StreamPlan.RequiresDisclosure) {
        'This route sends data to a remote model provider. Open Privacy for the exact path.'
    } else {
        'Model requests stay on this PC.'
    }
}

# Thought bubbles are reserved for System Sense alerts only. No canned trivia.
function Add-SlopThoughtBubble {
    param([Parameter(Mandatory)][string]$Text)
    $maxWidth = 190.0
    $fontSize = 8

    $b = New-Object System.Windows.Controls.Border
    $b.CornerRadius = [System.Windows.CornerRadius]::new(10)
    $b.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#2A1E293B')
    $b.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#55F59E0B')
    $b.BorderThickness = [System.Windows.Thickness]::new(1)
    $b.Padding = [System.Windows.Thickness]::new(12,8,12,8)
    $b.IsHitTestVisible = $false
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = "⚠️ $Text"
    $tb.Foreground = [System.Windows.Media.Brushes]::White
    $tb.FontSize = $fontSize
    $tb.FontStyle = 'Italic'
    $tb.TextWrapping = 'Wrap'
    $tb.MaxWidth = $maxWidth
    $b.Child = $tb
    $b.Opacity = 0
    $Stage.Children.Add($b) | Out-Null

    $b.Measure([System.Windows.Size]::new($maxWidth, 400.0))
    $bw = $b.DesiredSize.Width
    $bh = $b.DesiredSize.Height
    $pea = Get-SlopPeaOrigin
    $x = $pea[0] - ($bw / 2.0)
    $y = $pea[1] - $bh - 18.0
    $x = [Math]::Max(8.0, [Math]::Min($x, $window.ActualWidth - $bw - 8.0))
    $y = [Math]::Max(8.0, $y)
    [System.Windows.Controls.Canvas]::SetLeft($b, $x)
    [System.Windows.Controls.Canvas]::SetTop($b, $y)
    $b.Tag = @{ Born = [DateTime]::UtcNow }
}

# --- Four quiet destinations -------------------------------------------------
# Fill every panel from the live config so the views cannot drift from the route.
function Get-SlopEffectiveOpenCodeBaseUrl {
    param([hashtable]$Config)
    $url = if ($env:OPENCODE_BASE_URL) { [string]$env:OPENCODE_BASE_URL } else { 'http://127.0.0.1:28894' }
    if ($Config -and -not [string]::IsNullOrWhiteSpace([string]$Config.openCodeBaseUrl)) {
        $url = [string]$Config.openCodeBaseUrl
    }
    return $url.Trim().TrimEnd('/')
}

function Update-SlopVoiceReadinessUi {
    $cfg = $script:SlopConfigResult.Config
    if ($null -eq $cfg) { return }
    $VoiceEnabledCheck.IsChecked = [bool]$cfg.voiceEnabled
    $VoiceLanguageCombo.Text = [string]$cfg.whisperLanguage
    $VoiceMaxSecondsBox.Text = [string]$cfg.voiceMaxSeconds
    $VoiceReadyText.Text = 'Whisper readiness: ' + (Get-SlopVoiceReadinessText -Config $cfg -InstallRoot $script:VoiceInstallRoot)
    Set-SlopMicUiState -State idle
}

function Load-SlopSettings {
    $cfg = $script:SlopConfigResult.Config
    if ($null -eq $cfg) { return }
    $defaults = New-SlopDefaultConfig
    $kind = Resolve-SlopRouteKind -Config $cfg
    $SettingsRouteText.Text = if ($kind -like 'opencode*') { Get-SlopCopy -Key 'route.opencode' } else { Get-SlopCopy -Key 'route.local' }
    $model = [string]$cfg.model
    if ([string]::IsNullOrWhiteSpace($model)) { $model = [string]$cfg.modelName }
    if ([string]::IsNullOrWhiteSpace($model)) { $model = [string]$defaults.model }
    $SettingsModelBox.Text = $model
    $SettingsBaseUrlBox.Text = Get-SlopEffectiveOpenCodeBaseUrl -Config $cfg
    if ([string]::IsNullOrWhiteSpace([string]$cfg.agentId)) { $cfg.agentId = 'sloppy' }
    $SettingsAgentIdBox.Text = [string]$cfg.agentId
    Update-SlopVoiceReadinessUi
}

function Save-SlopSettings {
    $cfg = @{}
    foreach ($key in $script:SlopConfigResult.Config.Keys) { $cfg[$key] = $script:SlopConfigResult.Config[$key] }

    # Tier, provider, endpoint, model and agent belong to Brain. Settings owns
    # only the voice opt-in and its local transcription settings.
    $cfg.voiceEnabled = [bool]$VoiceEnabledCheck.IsChecked
    $cfg.whisperLanguage = ([string]$VoiceLanguageCombo.Text).Trim().ToLowerInvariant()
    $seconds = 0
    if (-not [int]::TryParse([string]$VoiceMaxSecondsBox.Text, [ref]$seconds)) {
        Set-SlopDestinationStatus -Name Settings -Text 'Max seconds must be an integer between 10 and 120.' -Tone 'error'
        return $false
    }
    $cfg.voiceMaxSeconds = $seconds

    $check = Test-SlopConfig -Config $cfg
    if (-not $check.Ok) {
        Set-SlopDestinationStatus -Name Settings -Text ("Settings invalid: " + ($check.Errors -join '; ')) -Tone 'error'
        return $false
    }

    try { Write-SlopConfig -Config $cfg }
    catch {
        Set-SlopDestinationStatus -Name Settings -Text "Settings could not be saved: $($_.Exception.Message)" -Tone 'error'
        return $false
    }

    $script:SlopConfigResult.Config = $cfg
    $script:SlopConfigResult.Ok = $true
    $script:SlopConfigResult.Exists = $true
    $script:OpenCodeBaseUrl = Get-SlopEffectiveOpenCodeBaseUrl -Config $cfg
    Initialize-SlopDestinationPanels
    Update-SlopRouteBadgeFromConfig
    Set-SlopDestinationStatus -Name Settings -Text 'Settings saved.' -Tone 'success'
    return $true
}

function Save-SlopCustomize {
    $result = Set-SlopConfigIdentity `
        -Config $script:SlopConfigResult.Config `
        -Name ([string]$CustomizeNameBox.Text) `
        -Color ([string]$CustomizeColourCombo.Text) `
        -Personality ([string]$CustomizePersonalityCombo.Text)
    if (-not $result.Ok) {
        Set-SlopDestinationStatus -Name Customize -Text ("Customize invalid: " + ($result.Errors -join '; ')) -Tone 'error'
        return $false
    }

    $personaText = [string]$CustomizePersonaBox.Text
    try {
        Write-SlopPersona -Text $personaText
        Write-SlopConfig -Config $result.Config
    }
    catch {
        Set-SlopDestinationStatus -Name Customize -Text "Customize could not be saved: $($_.Exception.Message)" -Tone 'error'
        return $false
    }

    $script:SlopConfigResult.Config = $result.Config
    $script:SlopConfigResult.Ok = $true
    $script:SlopConfigResult.Exists = $true
    Update-SlopIdentityFromConfig
    Initialize-SlopDestinationPanels
    Update-SlopRouteBadgeFromConfig
    Set-SlopDestinationStatus -Name Customize -Text 'Customize saved.' -Tone 'success'
    return $true
}

function Save-SlopBrain {
    $result = Set-SlopConfigBrain `
        -Config $script:SlopConfigResult.Config `
        -Brain ([string]$BrainTypeCombo.Text) `
        -Provider ([string]$BrainProviderBox.Text) `
        -ProviderLocality 'remote' `
        -EndpointUrl ([string]$BrainEndpointBox.Text) `
        -Model ([string]$BrainModelBox.Text) `
        -AgentId ([string]$BrainAgentIdBox.Text) `
        -CapabilityProfile ([string]$BrainProfileCombo.Text)
    if (-not $result.Ok) {
        Set-SlopDestinationStatus -Name Brain -Text ("Brain invalid: " + ($result.Errors -join '; ')) -Tone 'error'
        return $false
    }

    try { Write-SlopConfig -Config $result.Config }
    catch {
        Set-SlopDestinationStatus -Name Brain -Text "Brain could not be saved: $($_.Exception.Message)" -Tone 'error'
        return $false
    }

    $script:SlopConfigResult.Config = $result.Config
    $script:SlopConfigResult.Ok = $true
    $script:SlopConfigResult.Exists = $true
    Initialize-SlopDestinationPanels
    Update-SlopRouteBadgeFromConfig
    Set-SlopDestinationStatus -Name Brain -Text 'Brain saved.' -Tone 'success'
    return $true
}

function Update-SlopRouteBadgeFromConfig {
    $cfg = $script:SlopConfigResult.Config
    $kind = Resolve-SlopRouteKind -Config $cfg
    $agent = if ($cfg.agent) { $cfg.agent } else { @{} }
    $effective = Resolve-SlopEffectiveModel -Agent $agent -Config $cfg
    if ([string]::IsNullOrWhiteSpace($effective)) {
        $bundled = if (Get-Command Get-SlopBundledModelName -ErrorAction SilentlyContinue) { Get-SlopBundledModelName } else { 'Qwen3.5-2B Q4_K_M' }
        $effective = if ($kind -eq 'local-bundled') { $bundled } else { 'unknown' }
    }
    $provider = if ($cfg.provider) { [string]$cfg.provider } else { 'bundled' }
    $catalog = Get-SlopRouteCatalog
    $badgePlan = @{
        Badge=(Get-SlopRouteBadge -Kind $kind -Provider $provider -Model $effective)
        RequiresDisclosure=[bool]$catalog[$kind].TermsRequired
    }
    Set-SlopRouteBadge -StreamPlan $badgePlan
}

function Update-SlopIdentityFromConfig {
    $cfg = $script:SlopConfigResult.Config
    if (-not $cfg) { return }
    $script:IdentityBrush = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.BrushConverter]::new().ConvertFromString(
            (Get-SlopIdentityColor -ColorKey ([string]$cfg.color))).Color)
}

function Set-SlopComboItems {
    param(
        [Parameter(Mandatory)][System.Windows.Controls.ComboBox]$Combo,
        [Parameter(Mandatory)][object[]]$Items,
        [AllowEmptyString()][string]$Selected
    )
    $Combo.Items.Clear()
    foreach ($item in $Items) { $Combo.Items.Add($item) | Out-Null }
    $Combo.SelectedItem = $Selected
}

function Set-SlopDestinationStatus {
    param(
        [Parameter(Mandatory)][ValidateSet('Settings','Customize','Brain','Privacy')][string]$Name,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [ValidateSet('info','success','error')][string]$Tone = 'info'
    )
    $contract = Get-SlopDestinationContract -Name $Name
    $status = $window.FindName($contract.Status)
    if (-not $status) { return }
    $color = switch ($Tone) {
        'success' { '#86EFAC' }
        'error'   { '#FCA5A5' }
        default   { '#93A4BD' }
    }
    $status.Text = $Text
    $status.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($color)
}

function Initialize-SlopDestinationPanels {
    $cfg = $script:SlopConfigResult.Config
    $kind = Resolve-SlopRouteKind -Config $cfg
    $agent = if ($cfg.agent) { $cfg.agent } else { @{} }
    $effective = Resolve-SlopEffectiveModel -Agent $agent -Config $cfg
    $locality = if ($cfg.providerLocality) { [string]$cfg.providerLocality } else { '' }
    $provider = if ($cfg.provider) { [string]$cfg.provider } else { 'bundled' }

    Load-SlopSettings

    Set-SlopComboItems -Combo $CustomizeColourCombo -Items @( (Get-SlopIdentityColors).Keys | Sort-Object ) -Selected ([string]$cfg.color)
    Set-SlopComboItems -Combo $CustomizePersonalityCombo -Items @( Get-SlopPersonalities ) -Selected ([string]$cfg.personality)
    $CustomizeNameBox.Text = [string]$cfg.name
    $personaPath = Get-SlopPersonaPath
    $persona = if (Test-Path -LiteralPath $personaPath) { Get-Content -LiteralPath $personaPath -Raw } else { '' }
    $CustomizePersonaBox.Text = $persona

    Set-SlopComboItems -Combo $BrainTypeCombo -Items @( Get-SlopBrainOrder ) -Selected ([string]$cfg.brain)
    Set-SlopComboItems -Combo $BrainProfileCombo -Items @( Get-SlopCapabilityProfiles ) -Selected ([string]$cfg.capabilityProfile)
    # Populate model choices for the selected tier.
    $BrainModelBox.Items.Clear()
    foreach ($m in @( Get-SlopBrainModelOptions -Brain ([string]$cfg.brain) )) {
        [void]$BrainModelBox.Items.Add($m)
    }
    $BrainProviderBox.Text = [string]$cfg.provider
    $BrainEndpointBox.Text = [string]$cfg.endpointUrl
    $modelItems = @($BrainModelBox.Items)
    $selectedModel = [string]$cfg.model
    if ($modelItems -notcontains $selectedModel) { $selectedModel = [string]$cfg.modelName }
    if ($modelItems -contains $selectedModel) { $BrainModelBox.Text = $selectedModel }
    elseif ($modelItems.Count -gt 0) { $BrainModelBox.SelectedIndex = 0 }
    $BrainAgentIdBox.Text = [string]$cfg.agentId
    $BrainRouteText.Text = "Local vs remote: $kind / $(if ($locality) { $locality } else { 'n/a' })"
    $BrainEffectiveText.Text = "Effective model: $effective"

    $terms = if ($cfg.termsUrl) { [string]$cfg.termsUrl } else { '' }
    $PrivacyRouteText.Text = New-SlopDisclosureText -Route @{
        Kind = $kind; Provider = $provider; Model = $effective
    } -TermsUrl $terms
    $PrivacyTermsLink.Text = $terms
    $PrivacyTermsLink.Visibility = if ($terms) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    $PrivacyConversationCopy.Text = Get-SlopDeletionCopy -Action 'conversation'
    $PrivacySessionCopy.Text = Get-SlopDeletionCopy -Action 'session'
    $PrivacyLocalDataCopy.Text = Get-SlopDeletionCopy -Action 'local-data'
    $AutostartButton.Content = "Autostart: $(if ($cfg.autostart) { 'On' } else { 'Off' })"
}

# Show one destination, or '__chat__' to return to the conversation. Chat and
# panels are mutually exclusive so a panel never floats over live messages.
function Show-SlopDestination {
    param([Parameter(Mandatory)][string]$Name)
    $map = Get-SlopDestinationMap
    if ($Name -ne '__chat__' -and -not $map.ContainsKey($Name)) { throw "unknown destination: $Name" }
    foreach ($other in $map.Keys) {
        $panel = $window.FindName(($other + 'Panel'))
        if ($null -ne $panel) { $panel.Visibility = 'Collapsed' }
    }
    $ChatScroll.Visibility = if ($Name -eq '__chat__') { 'Visible' } else { 'Collapsed' }
    if ($Name -eq '__chat__') { return }
    Set-SlopDestinationStatus -Name $Name -Text '' -Tone 'info'
    Initialize-SlopDestinationPanels
    $panel = $window.FindName(($Name + 'Panel'))
    if ($null -ne $panel) { $panel.Visibility = 'Visible' }
}

# The strip carries only the four destinations. Developer commands are one
# level down, under Settings -> Advanced / developer.
$script:SlopDestinations = @('Settings','Customize','Brain','Privacy')
foreach ($name in $script:SlopDestinations) {
    $btn = New-Object System.Windows.Controls.Button
    $btn.Content = $name
    $btn.Style = $window.Resources['SlopButton']
    $btn.FontSize = 9
    $btn.Padding = [System.Windows.Thickness]::new(6,2,6,2)
    $btn.Margin = [System.Windows.Thickness]::new(0,0,5,4)
    $btn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#22FFFFFF')
    $btn.Foreground = [System.Windows.Media.Brushes]::White
    $btn.Tag = $name
    $btn.Add_Click({ param($s,$e) Show-SlopDestination -Name $s.Tag })
    $ShortcutsStrip.Children.Add($btn) | Out-Null
}

function Insert-SlopShortcut {
    param([Parameter(Mandatory)][string]$Command)
    $InputBox.Text = if ($InputBox.Text) { $InputBox.Text.TrimEnd() + ' ' + $Command } else { $Command }
    $InputBox.CaretIndex = $InputBox.Text.Length
    $InputPlaceholder.Visibility = 'Collapsed'
    $InputBox.Focus() | Out-Null
}

# Legacy developer commands now live only under Settings -> Advanced / developer.
# They still insert text; none of them executes a command on the user's behalf.
$script:ShortcutCommands = @('startslop','stopslop','slopstatus','verify','review','kickoff','sign out')
foreach ($cmd in $script:ShortcutCommands) {
    $chip = New-Object System.Windows.Controls.Button
    $chip.Content = $cmd
    $chip.Style = $window.Resources['SlopButton']
    $chip.FontSize = 9
    $chip.Padding = [System.Windows.Thickness]::new(6,2,6,2)
    $chip.Margin = [System.Windows.Thickness]::new(0,0,5,4)
    $chip.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#22FFFFFF')
    $chip.Foreground = [System.Windows.Media.Brushes]::White
    $chip.Tag = $cmd
    $chip.Add_Click({ param($s,$e) Insert-SlopShortcut -Command $s.Tag })
    $AdvancedStack.Children.Add($chip) | Out-Null
}

# --- Deletion scopes ---------------------------------------------------------
# Each destructive action requires an explicit Yes; copy is owned by the
# disclosure module so the UI can never soften what the deletion actually does.
function Show-SlopConfirm {
    param([Parameter(Mandatory)][string]$Text)
    $result = [System.Windows.MessageBox]::Show($Text, 'Confirm deletion', 'YesNo', 'Warning', 'NoButton')
    return ($result -eq 'Yes')
}

function Remove-SlopOpenCodeSession {
    param([Parameter(Mandatory)][string]$SessionId)
    $auth = New-SlopOpenCodeAuthHeader
    $escaped = [uri]::EscapeDataString($SessionId)
    $url = "$($script:OpenCodeBaseUrl)/api/session/$escaped"
    $client = [System.Net.Http.HttpClient]::new()
    try {
        $req = [Net.Http.HttpRequestMessage]::new('DELETE', $url)
        foreach ($h in $auth.GetEnumerator()) { $req.Headers.TryAddWithoutValidation($h.Key, $h.Value) | Out-Null }
        $resp = $client.SendAsync($req).GetAwaiter().GetResult()
        if (-not $resp.IsSuccessStatusCode) {
            Set-SlopDestinationStatus -Name Privacy -Text "OpenCode session could not be deleted: $($resp.StatusCode)" -Tone 'error'
            return $false
        }
        $script:OpenCodeSessionId = $null
        $script:SlopConfigResult.Config.openCodeSessionId = $null
        Set-SlopDestinationStatus -Name Privacy -Text 'OpenCode session and its child sessions deleted. Any copy held by a model provider is not affected.' -Tone 'success'
        return $true
    }
    catch {
        Set-SlopDestinationStatus -Name Privacy -Text "OpenCode session could not be deleted: $($_.Exception.Message)" -Tone 'error'
        return $false
    }
    finally { if ($client) { $client.Dispose() } }
}

function Remove-SlopLocalData {
    $dir = Get-SlopUserDataPath
    foreach ($name in @('config.json','persona.md')) {
        $path = Join-Path $dir $name
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
    # Show-SlopOnboarding -Config <hashtable> -StartScreen 1..4 (Task 4 contract).
    Show-SlopOnboarding -Config @{} -StartScreen 1 | Out-Null
}

function Invoke-SlopDeletion {
    param([Parameter(Mandatory)][ValidateSet('conversation','session','local-data')][string]$Action)
    $scope = Get-SlopDeletionScope -Action $Action
    if (-not (Show-SlopConfirm -Text $scope.Copy)) {
        Set-SlopDestinationStatus -Name Privacy -Text 'Deletion cancelled.' -Tone 'info'
        return
    }
    switch ($Action) {
        'conversation' {
            $ChatStack.Children.Clear()
            Set-SlopDestinationStatus -Name Privacy -Text 'Conversation cleared on this device.' -Tone 'success'
        }
        'session' {
            if ($script:OpenCodeSessionId) {
                Remove-SlopOpenCodeSession -SessionId $script:OpenCodeSessionId
            }
            else {
                Set-SlopDestinationStatus -Name Privacy -Text 'No OpenCode session id is stored.' -Tone 'info'
            }
        }
        'local-data' {
            Remove-SlopLocalData
            Set-SlopDestinationStatus -Name Privacy -Text 'Local config and persona removed. Onboarding reopened.' -Tone 'success'
        }
    }
}

# Wire the back buttons and the three deletion buttons.
foreach ($name in $script:SlopDestinations) {
    $back = $window.FindName(($name + 'Back'))
    if ($null -ne $back) { $back.Add_Click({ param($s,$e) Show-SlopDestination -Name '__chat__' }) }
}
$AutostartButton.Add_Click({
    param($s,$e)
    $script:SlopConfigResult.Config.autostart = -not $script:SlopConfigResult.Config.autostart
    Write-SlopConfig -Config $script:SlopConfigResult.Config
    Sync-SlopAutostart -Enabled ([bool]$script:SlopConfigResult.Config.autostart)
    $AutostartButton.Content = "Autostart: $(if ($script:SlopConfigResult.Config.autostart) { 'On' } else { 'Off' })"
})
$SettingsSaveButton.Add_Click({ param($s,$e) Save-SlopSettings | Out-Null })
$CustomizeSaveButton.Add_Click({ param($s,$e) Save-SlopCustomize | Out-Null })
$BrainSaveButton.Add_Click({ param($s,$e) Save-SlopBrain | Out-Null })
$BrainTypeCombo.Add_SelectionChanged({
    param($s,$e)
    $BrainModelBox.Items.Clear()
    foreach ($m in @( Get-SlopBrainModelOptions -Brain ([string]$BrainTypeCombo.SelectedItem) )) {
        [void]$BrainModelBox.Items.Add($m)
    }
    if ($BrainModelBox.Items.Count -gt 0) { $BrainModelBox.SelectedIndex = 0 }
})
$VoiceRepairButton.Add_Click({
    try {
        $report = Invoke-SlopPreflight -InstallRoot $script:VoiceInstallRoot -ConfigPath (Get-SlopConfigPath)
        Add-SlopThoughtBubble -Text ($report.Lines -join "`n")
        Update-SlopVoiceReadinessUi
    }
    catch { Add-SlopThoughtBubble -Text "Voice repair failed: $($_.Exception.Message)" }
})
$DeleteConversationButton.Add_Click({ param($s,$e) Invoke-SlopDeletion -Action 'conversation' })
$DeleteSessionButton.Add_Click({ param($s,$e) Invoke-SlopDeletion -Action 'session' })
$DeleteLocalDataButton.Add_Click({ param($s,$e) Invoke-SlopDeletion -Action 'local-data' })

function Add-Bubble {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [bool]$IsUser,
        [string]$Emoji
    )
    if (-not $Emoji) { $Emoji = if ($IsUser) { '👤 ' } else { '🧠 ' } }
    $border = New-Object System.Windows.Controls.Border
    $border.CornerRadius = [System.Windows.CornerRadius]::new(10)
    $border.Padding = [System.Windows.Thickness]::new(12)
    $border.Margin = [System.Windows.Thickness]::new(0,0,0,10)
    if ($IsUser) {
        $border.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#3B82F6')
        $border.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#93C5FD')
        $border.HorizontalAlignment = 'Right'
        $border.Margin = [System.Windows.Thickness]::new(48,0,0,10)
    } else {
        $border.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#2AFFFFFF')
        $border.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#44FFFFFF')
        $border.HorizontalAlignment = 'Left'
        $border.Margin = [System.Windows.Thickness]::new(0,0,48,10)
    }
    $border.BorderThickness = [System.Windows.Thickness]::new(1)

    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = "$Emoji$Text"
    $tb.Foreground = [System.Windows.Media.Brushes]::White
    $tb.TextWrapping = 'Wrap'
    $tb.FontSize = 12
    if ($Text -match '^(>|&|\$)\s|^(startslop|stopslop|slopstatus|verify|review|kickoff|sign out)\b') {
        $tb.FontFamily = [System.Windows.Media.FontFamily]::new('Consolas')
    }
    $border.Child = $tb
    $ChatStack.Children.Add($border) | Out-Null
    if (-not $script:ReducedMotion) {
        $tt = [System.Windows.Media.TranslateTransform]::new(0,6)
        $border.Opacity = 0
        $border.RenderTransform = $tt
        $alpha = New-SlopSpring 0.0 220 22
        $lift = New-SlopSpring 6.0 200 22
        $alpha.Target = 1.0
        $lift.Target = 0.0
        $border.Tag = @{ SlopEntrance = $alpha; SlopLift = $lift; SlopTransform = $tt }
    }
    $ChatScroll.ScrollToEnd()
    return $border
}

# Approval cards are the actionable detail for a persistent attention signal.
# Only `once` and `reject` are reachable from the UI.
function Add-SlopApprovalCard {
    param([string]$RequestId, [string]$Action, [string]$Resources, [int]$Generation)
    $border = New-Object System.Windows.Controls.Border
    $border.CornerRadius = [System.Windows.CornerRadius]::new(8)
    $border.Padding = [System.Windows.Thickness]::new(8)
    $border.Margin = [System.Windows.Thickness]::new(0,0,40,6)
    $border.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#2AFFFFFF')
    $border.HorizontalAlignment = 'Left'

    $stack = New-Object System.Windows.Controls.StackPanel
    $label = New-Object System.Windows.Controls.TextBlock
    $label.Text = "Approve $Action : $Resources"
    $label.Foreground = [System.Windows.Media.Brushes]::White
    $label.TextWrapping = 'Wrap'
    $label.FontSize = 12
    $stack.Children.Add($label) | Out-Null
    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'
    $row.Margin = [System.Windows.Thickness]::new(0,6,0,0)
    foreach ($spec in @(@('Allow once','once'), @('Reject','reject'))) {
        $btn = New-Object System.Windows.Controls.Button
        $btn.Content = $spec[0]
        $btn.Style = $window.Resources['SlopButton']
        $btn.Margin = [System.Windows.Thickness]::new(0,0,8,0)
        $btn.Padding = [System.Windows.Thickness]::new(8,4,8,4)
        $btn.Add_Click({
            # Add_Click handlers do not close over function locals — read everything
            # from $this.Tag, which is owned by the control that fired the event.
            $tag = $this.Tag
            # Ignore a rapid second click before the card is removed from the tree.
            $this.IsEnabled = $false
            if ($script:RequestState.Generation -ne $tag.Generation) { return }
            $script:OpenCodePending.Remove($tag.RequestId) | Out-Null
            $ChatStack.Children.Remove($tag.Element) | Out-Null
            $ChatScroll.ScrollToEnd()
            Send-SlopPermissionReply -RequestId $tag.RequestId -Decision $tag.Decision -Generation $tag.Generation
            Clear-SlopSignalEvent -State $script:Motion -Id $tag.SignalId | Out-Null
        })
        # Tag carries the decision, not the raw OpenCode event payload.
        $signalId = "approval:$RequestId"
        $btn.Tag = @{ Decision = $spec[1]; RequestId = $RequestId; Generation = $Generation; Element = $border; SignalId = $signalId }
        $row.Children.Add($btn) | Out-Null
    }
    $stack.Children.Add($row) | Out-Null
    $border.Child = $stack
    $ChatStack.Children.Add($border) | Out-Null
    $ChatScroll.ScrollToEnd()
    $script:OpenCodePending[$RequestId] = @{ Generation = $Generation; Element = $border; SignalId = "approval:$RequestId" }
}

function Send-SlopPermissionReply {
    param([string]$RequestId, [string]$Decision, [int]$Generation)
    if (-not $script:OpenCodeSessionId) { return }
    $body = New-SlopPermissionReply -Decision $Decision
    $session = [uri]::EscapeDataString($script:OpenCodeSessionId)
    $reqId = [uri]::EscapeDataString($RequestId)
    $url = "$($script:OpenCodeBaseUrl)/api/session/$session/permission/$reqId/reply"
    $job = Start-ThreadJob -ScriptBlock {
        param($Url, $Body, $Auth)
        try {
            $client = New-Object System.Net.Http.HttpClient
            $content = New-Object System.Net.Http.StringContent($Body, [Text.Encoding]::UTF8, 'application/json')
            $req = [Net.Http.HttpRequestMessage]::new('POST', $Url)
            $req.Content = $content
            foreach ($h in $Auth.GetEnumerator()) { $req.Headers.TryAddWithoutValidation($h.Key, $h.Value) | Out-Null }
            $client.SendAsync($req).GetAwaiter().GetResult() | Out-Null
        } catch { } finally { if ($client) { $client.Dispose() } }
    } -ArgumentList $url, $body, (New-SlopOpenCodeAuthHeader)
    $script:OpenCodeSideJobs.Add($job)
}

function Clear-SlopPendingApprovalCards {
    param([int]$Generation)
    foreach ($entry in @($script:OpenCodePending.GetEnumerator())) {
        if ($entry.Value.Generation -ne $Generation) { continue }
        $script:OpenCodePending.Remove($entry.Key) | Out-Null
        if ($entry.Value.SignalId) { Clear-SlopSignalEvent -State $script:Motion -Id $entry.Value.SignalId | Out-Null }
        if ($entry.Value.Element) { $ChatStack.Children.Remove($entry.Value.Element) | Out-Null }
    }
}

function Reject-SlopPendingApprovals {
    param([int]$Generation)
    foreach ($entry in @($script:OpenCodePending.GetEnumerator())) {
        if ($entry.Value.Generation -ne $Generation) { continue }
        $script:OpenCodePending.Remove($entry.Key) | Out-Null
        if ($entry.Value.SignalId) { Clear-SlopSignalEvent -State $script:Motion -Id $entry.Value.SignalId | Out-Null }
        if ($entry.Value.Element) { $ChatStack.Children.Remove($entry.Value.Element) | Out-Null }
        Send-SlopPermissionReply -RequestId $entry.Key -Decision 'reject' -Generation $Generation
    }
}

# A separate modal is the consent gate for remote routes. No "allow always"
# option exists, and closing the window leaves DialogResult null (= cancel).
function Show-SlopDisclosure {
    param(
        [Parameter(Mandatory)][hashtable]$Route,
        [string]$TermsUrl = ''
    )
    $script:SlopDisclosureDialog = [System.Windows.Window]::new()
    $dlg = $script:SlopDisclosureDialog
    $dlg.Title = 'Where your message goes'
    if ($window -and $window.IsVisible) {
        $dlg.Owner = $window
        $dlg.WindowStartupLocation = 'CenterOwner'
    } else {
        $dlg.WindowStartupLocation = 'CenterScreen'
    }
    $dlg.SizeToContent = 'WidthAndHeight'
    $dlg.MinWidth = 480
    $dlg.MaxWidth = 640
    $dlg.Padding = [System.Windows.Thickness]::new(18)

    $stack = [System.Windows.Controls.StackPanel]::new()
    $body = [System.Windows.Controls.TextBlock]::new()
    $body.Text = New-SlopDisclosureText -Route $Route -TermsUrl $TermsUrl
    $body.TextWrapping = 'Wrap'
    $body.Margin = [System.Windows.Thickness]::new(0,0,0,12)
    $stack.Children.Add($body) | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($TermsUrl)) {
        $link = [System.Windows.Controls.TextBlock]::new()
        $link.Text = $TermsUrl
        $link.TextWrapping = 'Wrap'
        $link.Foreground = [System.Windows.Media.Brushes]::CornflowerBlue
        $link.Margin = [System.Windows.Thickness]::new(0,0,0,12)
        $stack.Children.Add($link) | Out-Null
    }
    $buttons = [System.Windows.Controls.StackPanel]::new()
    $buttons.Orientation = 'Horizontal'
    $buttons.HorizontalAlignment = 'Right'
    $continueBtn = [System.Windows.Controls.Button]::new()
    $continueBtn.Content = 'Continue'
    $continueBtn.MinWidth = 90
    $continueBtn.Margin = [System.Windows.Thickness]::new(0,0,8,0)
    $continueBtn.Add_Click({ param($s,$e) $script:SlopDisclosureDialog.DialogResult = $true })
    $cancelBtn = [System.Windows.Controls.Button]::new()
    $cancelBtn.Content = 'Cancel'
    $cancelBtn.MinWidth = 90
    $cancelBtn.Add_Click({ param($s,$e) $script:SlopDisclosureDialog.DialogResult = $false })
    $buttons.Children.Add($cancelBtn) | Out-Null
    $buttons.Children.Add($continueBtn) | Out-Null
    $stack.Children.Add($buttons) | Out-Null
    $dlg.Content = $stack
    return [bool]$dlg.ShowDialog()
}

function Start-Stream {
    param(
        [string]$UserText,
        [object[]]$Attachments = @()
    )

    if ($script:IsStreaming) { return }
    # Fail closed before any streaming state or timer exists - otherwise the
    # error bubble would be enqueued with nothing left to drain the queue.
    # The amber reaction is set before any blocking health probe so a cold model
    # wake still feels like the companion thinking. Failures clear it below.
    Set-SlopSignalEvent -State $script:Motion -Id 'request:preflight' -Kind thinking `
        -Status 'Getting ready' -Sticky
    $config = @{} + $script:SlopConfigResult.Config
    $config.openCodeSessionId = [string]$script:OpenCodeSessionId
    # Validate config before using it: tampered or UI-invalid config must not start a request.
    $configCheck = Test-SlopConfig -Config $config
    if (-not $configCheck.Ok) {
        Clear-SlopSignalEvent -State $script:Motion -Id 'request:preflight' | Out-Null
        Add-Bubble -Text "[error: invalid config: $($configCheck.Errors -join '; ')]" -IsUser $false
        return
    }
    # Keep personal-opencode compatibility, but be explicit and fail closed for unsupported brains.
    if ([string]$config.brain -notin @('builtin','custom','opencode')) {
        Clear-SlopSignalEvent -State $script:Motion -Id 'request:preflight' | Out-Null
        Add-Bubble -Text "[error: unsupported brain '$($config.brain)']" -IsUser $false
        return
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$config.openCodeBaseUrl) -and
        -not (Test-SlopLoopbackHttpUrl -Url ([string]$config.openCodeBaseUrl))) {
        Clear-SlopSignalEvent -State $script:Motion -Id 'request:preflight' | Out-Null
        Add-Bubble -Text "[error: openCodeBaseUrl must be a loopback http URL]" -IsUser $false
        return
    }
    $streamPlan = Get-SlopStreamPlan `
        -Config $config -UserText $UserText -PersonaText (Read-SlopPersona) `
        -Attachments $Attachments `
        -LocalModelProcess $script:LocalModelProcess `
        -ScriptRootPath $PSScriptRoot -RepoRootPath (Split-Path $PSScriptRoot -Parent)
    if (-not $streamPlan.Ok) {
        Clear-SlopSignalEvent -State $script:Motion -Id 'request:preflight' | Out-Null
        Add-Bubble -Text "[error: $(Format-SlopLocalModelFailure -Reason $streamPlan.Reason)]" -IsUser $false
        return
    }
    if ($streamPlan.Kind -eq 'builtin' -and $null -ne $streamPlan.Process) {
        $script:LocalModelProcess = $streamPlan.Process
    }
    # Badge first: the user sees the real route even if they cancel consent.
    Set-SlopRouteBadge -StreamPlan $streamPlan
    if ($streamPlan.RequiresDisclosure -and -not $script:SlopDisclosureAccepted) {
        $accepted = Show-SlopDisclosure -Route @{
            Kind=$streamPlan.RouteKind; Provider=[string]$config.provider
            Model=([string]$config.model)
        }
        Clear-SlopSignalEvent -State $script:Motion -Id 'request:preflight' | Out-Null
        if (-not $accepted) { return }
        $script:SlopDisclosureAccepted = $true
    }
    if (-not (Start-SlopRequest -State $script:RequestState)) { return }
    $generation = $script:RequestState.Generation
    $script:IsStreaming = $true
    $script:Failed = $false
    $script:CurrentAssistantText = ''
    $script:StreamTextSpring = $null
    $SendBtn.IsEnabled = $false
    $SendBtn.Visibility = 'Collapsed'
    $StopBtn.Visibility = 'Visible'
    Clear-SlopSignalEvents -State $script:Motion -Prefix 'request:'
    Clear-SlopSignalEvents -State $script:Motion -Prefix 'completion:'
    Set-SlopBaseCondition -State $script:Motion -Streaming $true -ChatOpen ([bool]$script:ChatWindow) -Stalled $false
    Set-SlopSignalEvent -State $script:Motion -Id "request:${generation}:phase" -Kind thinking `
        -Status $streamPlan.StatusText -Sticky
    Clear-SlopSignalEvent -State $script:Motion -Id 'request:preflight' | Out-Null
    $script:LastTokenAt = [DateTime]::UtcNow

    Expand-Chat
    Add-Bubble -Text $UserText -IsUser $true

    $assistantBorder = Add-Bubble -Text '' -IsUser $false
    $script:CurrentAssistantBlock = $assistantBorder

    $queue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
    # DispatcherTimer tick scriptblocks do not capture function-local variables.
    # Publish these to script scope so the handler can read the active request.
    $script:StreamGeneration = $generation
    $script:StreamQueue = $queue

    $script:Cts = New-Object System.Threading.CancellationTokenSource
    $adapterArgs = @{} + $streamPlan.AdapterArgs
    # Preserve the existing verifier override instead of hard-coding 300 here.
    $adapterArgs.TimeoutSeconds = $script:RequestTimeoutSeconds
    # The bundled brain is started in the worker, never on the WPF dispatcher:
    # Start-SlopLocalModel can wait up to 90 seconds for the model to become ready.
    $jobPlan = @{
        AdapterPath = $streamPlan.AdapterPath
        AdapterArgs = $adapterArgs
        LocalModelModule = (Join-Path $PSScriptRoot 'Slop.LocalModel.ps1')
        LocalModelPaths = $streamPlan.LocalModelPaths
        NeedsLocalModelStart = [bool]$streamPlan.NeedsLocalModelStart
    }
    $job = Start-ThreadJob -ScriptBlock {
        param($Plan, $Queue, $Cts)
        . $Plan.AdapterPath
        try {
            if ($Plan.NeedsLocalModelStart) {
                . $Plan.LocalModelModule
                $start = Start-SlopLocalModel -Paths $Plan.LocalModelPaths -ContextSize ([int]$Plan.LocalModelContextSize)
                if (-not $start.Ok) { $Queue.Enqueue("__ERR__$($start.Reason)"); return }
                # Hand the owned process back to the UI thread for clean shutdown.
                $Queue.Enqueue("__SLOPMODEL__$($start.Process.Id)")
            }
            $invokeArgs = @{} + $Plan.AdapterArgs
            $invokeArgs.Queue = $Queue
            $invokeArgs.Token = $Cts.Token
            Invoke-SlopAdapter @invokeArgs
        }
        catch [System.OperationCanceledException] { $Queue.Enqueue('__ERR__Cancelled') }
        catch { $Queue.Enqueue("__ERR__$($_.Exception.Message)") }
        finally { $Queue.Enqueue('__DONE__') }
    } -ArgumentList $jobPlan, $queue, $script:Cts

    $script:CurrentJob = $job

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(40)
    $timer.Add_Tick({
        $gen = $script:StreamGeneration
        $q = $script:StreamQueue
        # Late events from a cancelled/finalized request must never overwrite the
        # new request's UI state.
        if ($script:RequestState.Generation -ne $gen -or
            $script:RequestState.Phase -in @('completed', 'finalized')) { return }
        $script:StalledNow = $script:IsStreaming -and `
            ((([DateTime]::UtcNow) - $script:LastTokenAt).TotalSeconds -gt 3)
        Set-SlopBaseCondition -State $script:Motion -Streaming $script:IsStreaming `
            -ChatOpen ([bool]$script:ChatWindow) -Stalled $script:StalledNow
        $tok = $null
        while ($q.TryDequeue([ref]$tok)) {
            if ($script:RequestState.Generation -ne $gen -or
                $script:RequestState.Phase -in @('completed', 'finalized')) { return }
            # Bridge markers must be intercepted before Resolve-SlopStreamToken,
            # which would otherwise treat them as plain assistant text.
            if ($tok.StartsWith('__SLOPMODEL__')) {
                $pidText = $tok.Substring(13)
                $modelProc = Get-Process -Id ([int]$pidText) -ErrorAction SilentlyContinue
                if ($modelProc) { $script:LocalModelProcess = $modelProc }
                continue
            }
            if ($tok.StartsWith('__OC')) {
                if ($tok.StartsWith('__OCSESSION__')) {
                    $script:OpenCodeSessionId = $tok.Substring(13)
                    $script:SlopConfigResult.Config.openCodeSessionId = $script:OpenCodeSessionId
                }
                elseif ($tok.StartsWith('__OCASK__')) {
                    $parts = $tok.Substring(9) -split '\|', 3
                    if ($parts.Count -eq 3) {
                        Add-SlopApprovalCard -RequestId $parts[0] -Action $parts[1] -Resources $parts[2] -Generation $gen
                        Set-SlopSignalEvent -State $script:Motion -Id "approval:$($parts[0])" `
                            -Kind approval -Status 'Approval needed'
                    }
                }
                elseif ($tok -eq '__OCSUCCESS__') {
                    Set-SlopSignalEvent -State $script:Motion -Id "completion:$gen" -Kind success `
                        -Status 'Request complete' -DurationSeconds 1.5
                }
                # '__OCREPLIED__' needs no UI action.
                continue
            }
            $ev = Resolve-SlopStreamToken -Token $tok
            switch ($ev.Kind) {
                'connected' {
                    Set-SlopRequestConnected -State $script:RequestState -Generation $gen | Out-Null
                    Set-SlopSignalEvent -State $script:Motion -Id "request:${gen}:phase" -Kind thinking `
                        -Status 'Waiting for response' -Sticky
                }
                'warning' {
                    $script:CurrentAssistantText += "`n[$($ev.Reason)]"
                    $script:CurrentAssistantBlock.Child.Text = $script:CurrentAssistantText
                    Set-SlopSignalEvent -State $script:Motion -Id "request:${gen}:warning" -Kind warning `
                        -Status $ev.Reason -DurationSeconds 6.0
                }
                'cancelled' {
                    $script:Failed = $true
                    Set-SlopRequestFailed -State $script:RequestState -Generation $gen -Reason 'Cancelled' | Out-Null
                    $script:CurrentAssistantBlock.Child.Text = Format-SlopStreamFailure -PartialText $script:CurrentAssistantText -Kind 'cancelled' -Reason 'Cancelled'
                    Set-SlopSignalEvent -State $script:Motion -Id "request:$gen" -Kind cancelled `
                        -Status 'Request cancelled' -DurationSeconds 1.5
                }
                'timeout' {
                    $script:Failed = $true
                    Set-SlopRequestFailed -State $script:RequestState -Generation $gen -Reason $ev.Reason | Out-Null
                    $script:CurrentAssistantBlock.Child.Text = Format-SlopStreamFailure -PartialText $script:CurrentAssistantText -Kind 'timeout' -Reason $ev.Reason
                    Set-SlopSignalEvent -State $script:Motion -Id "request:$gen" -Kind error `
                        -Status "Request timed out: $($ev.Reason)" -DurationSeconds 2.0
                }
                'http' {
                    $script:Failed = $true
                    Set-SlopRequestFailed -State $script:RequestState -Generation $gen -Reason $ev.Reason | Out-Null
                    $script:CurrentAssistantBlock.Child.Text = Format-SlopStreamFailure -PartialText $script:CurrentAssistantText -Kind 'http' -Reason $ev.Reason
                    Set-SlopSignalEvent -State $script:Motion -Id "request:$gen" -Kind error `
                        -Status "Request failed: $($ev.Reason)" -DurationSeconds 2.0
                }
                'error' {
                    $script:Failed = $true
                    Set-SlopRequestFailed -State $script:RequestState -Generation $gen -Reason $ev.Reason | Out-Null
                    $script:CurrentAssistantBlock.Child.Text = Format-SlopStreamFailure -PartialText $script:CurrentAssistantText -Kind 'error' -Reason $ev.Reason
                    Set-SlopSignalEvent -State $script:Motion -Id "request:$gen" -Kind error `
                        -Status "Request failed: $($ev.Reason)" -DurationSeconds 2.0
                }
                'done' {
                    if (-not $script:Failed) {
                        $emptyLabel = Format-SlopEmptyResponse -Text $script:CurrentAssistantText
                        if ($emptyLabel) {
                            $script:CurrentAssistantBlock.Child.Text = $emptyLabel
                            $script:CurrentAssistantText = $emptyLabel
                            Set-SlopSignalEvent -State $script:Motion -Id "request:$gen" -Kind error `
                                -Status 'Request returned no response' -DurationSeconds 2.0
                        }
                        else {
                            Set-SlopSignalEvent -State $script:Motion -Id "completion:$gen" -Kind success `
                                -Status 'Request complete' -DurationSeconds 1.5
                        }
                    }
                    Set-SlopRequestCompleted -State $script:RequestState -Generation $gen | Out-Null
                    Finish-Stream -Generation $gen
                    return
                }
                'token' {
                    if ($null -eq $script:RequestState.FirstTokenAt) {
                        Set-SlopRequestFirstToken -State $script:RequestState -Generation $gen | Out-Null
                    }
                    else {
                        Set-SlopRequestToken -State $script:RequestState -Generation $gen | Out-Null
                    }
                    $script:CurrentAssistantText += $ev.Text
                    $nowTick = [DateTime]::UtcNow
                    $script:LastTokenAt = $nowTick
                    # Throttled token pokes make the membrane ripple along its bottom edge.
                    if (($nowTick - $script:LastPokeAt).TotalMilliseconds -ge 120) {
                        $script:LastPokeAt = $nowTick
                        $span = [Math]::Max(1, [int]$Frame.Width - 80)
                        $pokeX = [float](18 + 40 + (Get-Random -Maximum $span))
                        $script:Membrane.Poke($pokeX, [float](18 + $Frame.Height), 14.0)
                    }
                    $script:StalledNow = $false
                    Clear-SlopSignalEvent -State $script:Motion -Id "request:${gen}:phase" | Out-Null
                    Set-SlopBaseCondition -State $script:Motion -Streaming $true `
                        -ChatOpen ([bool]$script:ChatWindow) -Stalled $false
                    $tb = $script:CurrentAssistantBlock.Child
                    if (-not $script:StreamTextSpring) {
                        $script:StreamTextSpring = New-SlopSpring 0.70 240 24
                        $script:StreamTextSpring.Target = 1.0
                    }
                    # Only follow the stream while the user is near the bottom;
                    # otherwise reading earlier turns gets yanked back every token.
                    $nearBottom = ($ChatScroll.ScrollableHeight - $ChatScroll.VerticalOffset) -le 48
                    $tb.Text = $script:CurrentAssistantText
                    if ($nearBottom) { $ChatScroll.ScrollToEnd() }
                }
            }
        }
    })
    $script:Timer = $timer
    $timer.Start()
}

# Chat controls may belong to the pet or to the separate chat window. Handlers
# live at script scope so both surfaces share one implementation.
$script:SlopSendAction = {
    $text = $script:InputBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return }
    $script:InputBox.Text = ''
    Start-Stream -UserText $text
}
$script:SlopStopAction = { Request-StopStream }
$script:SlopInputChangedAction = {
    $script:InputPlaceholder.Visibility = if ([string]::IsNullOrWhiteSpace($script:InputBox.Text)) { 'Visible' } else { 'Collapsed' }
}
$script:SlopInputKeyDownAction = {
    param($s, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Enter -and -not $e.KeyboardDevice.Modifiers) {
        & $script:SlopSendAction
        $e.Handled = $true
    }
}

function Initialize-SlopChatControlHandlers {
    param([Parameter(Mandatory)]$Target)
    $Target.FindName('MicBtn').Add_Click($script:SlopMicAction)
    $Target.FindName('SendBtn').Add_Click($script:SlopSendAction)
    $Target.FindName('StopBtn').Add_Click($script:SlopStopAction)
    $Target.FindName('InputBox').Add_TextChanged($script:SlopInputChangedAction)
    $Target.FindName('InputBox').Add_KeyDown($script:SlopInputKeyDownAction)
}

$script:MicRecording = $false
$script:MicRecorderPath = $null
$script:MicCapTimer = $null
$script:VoiceBusy = $false
$script:VoiceMaxSeconds = 30
$script:VoiceQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()

function Set-SlopMicUiState {
    param([ValidateSet('idle','recording','transcribing')][string]$State)
    if ($State -eq 'recording') {
        $MicBtn.Content = '■'
        $MicBtn.ToolTip = 'Recording... click to stop'
        $MicBtn.IsEnabled = $true
        $SendBtn.IsEnabled = $false
    }
    elseif ($State -eq 'transcribing') {
        $MicBtn.Content = '⏳'
        $MicBtn.ToolTip = 'Transcribing locally...'
        $MicBtn.IsEnabled = $false
        $SendBtn.IsEnabled = $false
    }
    else {
        $MicBtn.Content = '🎤'
        $MicBtn.ToolTip = if ($script:SlopConfigResult.Config.voiceEnabled) { 'Voice note to text (click to start/stop)' } else { 'Enable voice input in Settings' }
        $MicBtn.IsEnabled = [bool]$script:SlopConfigResult.Config.voiceEnabled
        $SendBtn.IsEnabled = -not [bool]$script:IsStreaming
    }
}

function Start-SlopVoiceTranscription {
    param([Parameter(Mandatory)][string]$WavPath)
    $cfg = $script:SlopConfigResult.Config
    $paths = Get-SlopWhisperPaths -InstallRoot $script:VoiceInstallRoot `
        -CliFile ([string]$cfg.whisperRuntimeFile) -ModelFile ([string]$cfg.whisperModelFile)
    $ready = Test-SlopWhisperReady -Paths $paths
    if (-not $ready.Ok) {
        Add-Bubble -Text "[error: voice input unavailable: $($ready.Errors -join '; ')]" -IsUser $false
        Set-SlopMicUiState -State idle
        return
    }
    $script:VoiceBusy = $true
    Set-SlopMicUiState -State transcribing
    Start-ThreadJob -ScriptBlock {
        param($AudioModule, $Paths, $Wav, $Language, $Queue)
        try {
            . $AudioModule
            $result = Invoke-SlopWhisperTranscription -Paths $Paths -WavPath $Wav -Language $Language -TimeoutSeconds 90
            if (-not $result.Ok) { $Queue.Enqueue("__VOICEERR__$($result.Reason)"); return }
            if ([string]::IsNullOrWhiteSpace($result.Text)) { $Queue.Enqueue('__VOICEERR__I did not catch that.'); return }
            $Queue.Enqueue("__VOICE__$($result.Text)")
        }
        catch { $Queue.Enqueue("__VOICEERR__$($_.Exception.Message)") }
        finally {
            if (Test-Path -LiteralPath $Wav) { Remove-Item -LiteralPath $Wav -Force -ErrorAction SilentlyContinue }
            $Queue.Enqueue('__VOICEDONE__')
        }
    } -ArgumentList (Join-Path $PSScriptRoot 'Slop.Audio.ps1'), $paths, $WavPath, ([string]$cfg.whisperLanguage), $script:VoiceQueue
}

function Stop-SlopMicAndTranscribe {
    if (-not $script:MicRecording) { return }
    $script:MicRecording = $false
    if ($script:MicCapTimer) { $script:MicCapTimer.Stop() }
    [SlopWinMM]::mciSendString('stop slopmic', $null, 0, [IntPtr]::Zero) | Out-Null
    [SlopWinMM]::mciSendString(('save slopmic "' + $script:MicRecorderPath + '"'), $null, 0, [IntPtr]::Zero) | Out-Null
    [SlopWinMM]::mciSendString('close slopmic', $null, 0, [IntPtr]::Zero) | Out-Null
    $wav = $script:MicRecorderPath
    $script:MicRecorderPath = $null
    if (-not $wav -or -not (Test-Path -LiteralPath $wav -PathType Leaf)) {
        Add-Bubble -Text '[error: microphone recording was not saved]' -IsUser $false
        Set-SlopMicUiState -State idle
        return
    }
    if ((Get-Item -LiteralPath $wav).Length -le 44) {
        Remove-Item -LiteralPath $wav -Force -ErrorAction SilentlyContinue
        Add-Bubble -Text '[error: microphone recording was empty]' -IsUser $false
        Set-SlopMicUiState -State idle
        return
    }
    Start-SlopVoiceTranscription -WavPath $wav
}

$script:VoiceTimer = [System.Windows.Threading.DispatcherTimer]::new()
$script:VoiceTimer.Interval = [TimeSpan]::FromMilliseconds(40)
$script:VoiceTimer.Add_Tick({
    $q = $script:VoiceQueue
    if ($null -eq $q) { return }
    $tok = $null
    while ($q.TryDequeue([ref]$tok)) {
        if ($tok.StartsWith('__VOICE__')) {
            # Start-Stream already adds the user bubble; do not add it twice.
            Start-Stream -UserText $tok.Substring(9)
        }
        elseif ($tok.StartsWith('__VOICEERR__')) {
            Add-Bubble -Text "[error: $($tok.Substring(12))]" -IsUser $false
            Set-SlopMicUiState -State idle
        }
        elseif ($tok -eq '__VOICEDONE__') { Set-SlopMicUiState -State idle }
    }
})
$script:VoiceTimer.Start()

$script:MicCapTimer = [System.Windows.Threading.DispatcherTimer]::new()
$script:MicCapTimer.Add_Tick({
    if ($script:MicRecording) {
        Stop-SlopMicAndTranscribe
        Add-Bubble -Text "Recording stopped at the $($script:VoiceMaxSeconds)s limit." -IsUser $false
    }
})

$script:SlopMicAction = {
    try {
        if ($script:VoiceBusy) { return }
        if ($script:IsStreaming) {
            Add-Bubble -Text 'Wait for the current reply before starting a voice note.' -IsUser $false
            return
        }
        $cfg = $script:SlopConfigResult.Config
        if (-not $cfg.voiceEnabled) {
            Add-Bubble -Text 'Enable voice input in Settings.' -IsUser $false
            return
        }
        if ($script:MicRecording) { Stop-SlopMicAndTranscribe; return }
        if (-not ('SlopWinMM' -as [type])) {
            Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class SlopWinMM {
  [DllImport("winmm.dll", CharSet=CharSet.Auto)] public static extern int mciSendString(string command, StringBuilder buffer, int bufferSize, IntPtr hwndCallback);
}
"@
        }
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("slop-mic-" + [guid]::NewGuid().ToString('N') + '.wav')
        $script:MicRecorderPath = $tmp
        [SlopWinMM]::mciSendString('open new type waveaudio alias slopmic', $null, 0, [IntPtr]::Zero) | Out-Null
        $result = [SlopWinMM]::mciSendString('record slopmic', $null, 0, [IntPtr]::Zero)
        if ($result -ne 0) { throw "winmm record failed (code $result)" }
        $script:MicRecording = $true
        $script:VoiceMaxSeconds = [int]$cfg.voiceMaxSeconds
        $script:MicCapTimer.Interval = [TimeSpan]::FromSeconds($script:VoiceMaxSeconds)
        $script:MicCapTimer.Start()
        Set-SlopMicUiState -State recording
    }
    catch {
        $script:MicRecording = $false
        if ($script:MicCapTimer) { $script:MicCapTimer.Stop() }
        try { [SlopWinMM]::mciSendString('close slopmic', $null, 0, [IntPtr]::Zero) | Out-Null } catch {}
        if ($script:MicRecorderPath -and (Test-Path -LiteralPath $script:MicRecorderPath)) {
            Remove-Item -LiteralPath $script:MicRecorderPath -Force -ErrorAction SilentlyContinue
        }
        $script:MicRecorderPath = $null
        Set-SlopMicUiState -State idle
        Add-Bubble -Text "[error: mic recording unavailable: $($_.Exception.Message)]" -IsUser $false
    }
}

Initialize-SlopChatControlHandlers -Target $window

# single dispatcher-owned motion clock: ~30 fps render, fixed 1/120 s physics substeps
$script:Motion = New-SlopMotionState
$script:ReducedMotion = -not (Test-SlopClientAreaAnimation)
$script:MotionAccumulator = 0.0
$script:LastMotionTick = [DateTime]::UtcNow
Set-SlopFrameTarget -State $script:Motion -Target 'closed'
Set-SlopBaseCondition -State $script:Motion -Streaming $false -ChatOpen $false -Stalled $false
Initialize-MotionVisuals
Update-PeaAnchor
$script:Membrane = [SlopFrame]::new([float]$Frame.Width, [float]$Frame.Height, 10.0, [Environment]::TickCount)
$script:Membrane.SetMotionScale($(if ($script:ReducedMotion) { 0.0 } else { 1.0 }))
$Stage = $window.FindName('Stage')
$script:FaceLayer = New-SlopFaceLayer -Seed ([Environment]::TickCount)
$script:FaceRegion = @{ Width = 48.0; Height = 48.0 }
Update-SlopFaceRegion
$script:LastPokeAt = [DateTime]::UtcNow

# --- Portable config and first-run onboarding ---
function Save-SlopOnboardingResult {
    param([Parameter(Mandatory)][hashtable]$Result)
    # personaText is returned by the wizard but belongs in persona.md, not config.json.
    $cfg = @{}
    foreach ($key in (New-SlopDefaultConfig).Keys) {
        if ($Result.ContainsKey($key)) { $cfg[$key] = $Result[$key] }
    }
    $check = Test-SlopConfig -Config $cfg
    if (-not $check.Ok) { throw "refusing to save onboarding: $($check.Errors -join '; ')" }
    Write-SlopConfig -Config $cfg
    Write-SlopPersona -Text ([string]$Result.personaText)
    return $cfg
}

function Sync-SlopAutostart {
    param([Parameter(Mandatory)][bool]$Enabled)
    $launcher = Join-Path (Split-Path $PSScriptRoot -Parent) 'run.vbs'
    if (-not (Test-Path -LiteralPath $launcher)) { return }  # developer run, not installed
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    if ($Enabled) {
        New-ItemProperty -Path $runKey -Name 'Sloppy' `
            -Value (Get-SlopAutostartValue -ExecutablePath $launcher) `
            -PropertyType String -Force | Out-Null
    }
    else { Remove-ItemProperty -Path $runKey -Name 'Sloppy' -ErrorAction SilentlyContinue }
}

$script:SlopConfigResult = Read-SlopConfig
if ($script:SlopConfigResult.Ok -and -not $script:SlopConfigResult.Exists) {
    $onboarded = Show-SlopOnboarding -Config $script:SlopConfigResult.Config
    if ($null -eq $onboarded) {
        # A dismissed first run still gets a usable default persona.
        $onboarded = New-SlopFallbackOnboardingResult -Config $script:SlopConfigResult.Config
    }
    $saved = Save-SlopOnboardingResult -Result $onboarded
    Sync-SlopAutostart -Enabled ([bool]$saved.autostart)
    $script:SlopConfigResult.Config = $saved
}
elseif (-not $script:SlopConfigResult.Ok) {
    Add-SlopThoughtBubble -Text "Settings need attention: $($script:SlopConfigResult.Reason). Onboarding will open."
    $onboarded = Show-SlopOnboarding -Config $script:SlopConfigResult.Config
    if ($onboarded) {
        $saved = Save-SlopOnboardingResult -Result $onboarded
        Sync-SlopAutostart -Enabled ([bool]$saved.autostart)
        $script:SlopConfigResult = @{ Ok = $true; Exists = $true; Config = $saved; Reason = $null }
    }
}
Set-SlopMicUiState -State idle
$script:LocalModelProcess = $null
$script:OpenCodeBaseUrl = Get-SlopEffectiveOpenCodeBaseUrl -Config $script:SlopConfigResult.Config
Update-SlopIdentityFromConfig

# Show the configured route from the very first frame, not just after a send.
Update-SlopRouteBadgeFromConfig

$script:SenseEnabled = Get-SlopSenseEnabled
$script:SenseAccumulator = 0.0
$script:MotionIntervalMs = 33
$script:LastWindowLeft = $window.Left
$script:LastWindowTop = $window.Top
$script:MotionTimer = [System.Windows.Threading.DispatcherTimer]::new()
$script:MotionTimer.Interval = [TimeSpan]::FromMilliseconds($script:MotionIntervalMs)
$script:MotionTimer.Add_Tick({
    # cadence: full rate during transitions and active motion, slower at rest.
    $left = $window.Left
    $top = $window.Top
    $moving = ($left -ne $script:LastWindowLeft) -or ($top -ne $script:LastWindowTop)
    $script:LastWindowLeft = $left
    $script:LastWindowTop = $top
    $wantMs = Get-SlopMotionIntervalMs -State $script:Motion -WindowMoving:$moving -Large:($script:ChatMode -eq 'Full')
    if ($wantMs -ne $script:MotionIntervalMs) {
        $script:MotionIntervalMs = $wantMs
        $script:MotionTimer.Interval = [TimeSpan]::FromMilliseconds($wantMs)
    }
    $now = [DateTime]::UtcNow
    $dt = ($now - $script:LastMotionTick).TotalSeconds
    $script:LastMotionTick = $now
    if ($dt -gt 0.25) { $dt = 0.25 }
    $script:MotionAccumulator += $dt
    $step = 1.0 / 120.0
    while ($script:MotionAccumulator -ge $step) {
        Update-SlopMotionState -State $script:Motion -Dt $step -ReducedMotion:$script:ReducedMotion
        foreach ($child in $ChatStack.Children) {
            $tag = $child.Tag
            if ($tag -is [hashtable] -and $tag.ContainsKey('SlopEntrance')) {
                $tag.SlopEntrance.Step($step)
                $tag.SlopLift.Step($step)
            }
        }
        if ($script:StreamTextSpring) { $script:StreamTextSpring.Step($step) }
        $script:MotionAccumulator -= $step
    }
    Apply-SlopMotion -Dt $dt
    # idle wander: nudge horizontally, but never off the visible work area
    if ($script:Motion.Phase -eq 'wander' -and -not $script:ChatWindow) {
        $wa = $script:WorkArea
        $maxLeft = [Math]::Max($wa.X, $wa.Right - $window.ActualWidth)
        $nextLeft = $window.Left + ($script:Motion.WanderDx / 4.0) * $dt
        $window.Left = [Math]::Min($maxLeft, [Math]::Max($wa.X, $nextLeft))
    }
    # System Sense: one cached evaluation per minute when opted in.
    if ($script:SenseEnabled) {
        $script:SenseAccumulator += $dt
        if ($script:SenseAccumulator -ge 60.0) {
            $script:SenseAccumulator = 0.0
            foreach ($alert in @(Invoke-SlopSenseScan)) {
                if ([string]::IsNullOrWhiteSpace($alert)) { continue }
                Add-SlopThoughtBubble -Text $alert
                break
            }
        }
    } else {
        $script:SenseAccumulator = 0.0
    }
    # fade/remove old thought bubbles
    $now = [DateTime]::UtcNow
    foreach ($child in @($Stage.Children)) {
        if ($child -is [System.Windows.Controls.Border] -and $child.Tag -is [hashtable] -and $child.Tag.ContainsKey('Born')) {
            $age = ($now - $child.Tag.Born).TotalSeconds
            if ($age -ge 6.0) { $Stage.Children.Remove($child) | Out-Null }
            elseif ($age -lt 0.5) { $child.Opacity = $age / 0.5 }
            elseif ($age -gt 5.0) { $child.Opacity = (6.0 - $age) / 1.0 }
            else { $child.Opacity = 1.0 }
        }
    }
    Update-SlopFaceRegion
    # face layer drift speed from the EFFECTIVE signal, not the raw base fields.
    # The cache is refreshed each tick by Update-SlopMotionState ->
    # Update-SlopSignal -> Get-SlopSignal; calling it here makes that authority
    # explicit and keeps this block correct if the tick order ever changes.
    $sig = Get-SlopSignal -State $script:Motion
    $frozen = $sig.Kind -in @('approval','stalled','warning','thinking','error','critical')
    $speed = switch -Exact ($sig.Kind) {
        'working' { 1.5 }
        'tool'    { 1.5 }
        'success' { 0.3 + 1.7 * $script:Motion.MoodPulse.Value }
        default   { 0.3 }
    }
    if ($frozen) { $speed = 0.0 }
    if ($script:ReducedMotion) { $frozen = $true; $speed = 0.0 }
    $pattern = switch -Exact ($sig.Kind) {
        'working'  { 'ring' }
        'tool'     { 'line' }
        'success'  { 'burst' }
        'error'    { 'cross' }
        'critical' { 'cross' }
        'approval' { 'spiral' }
        'stalled'  { 'spiral' }
        'warning'  { 'spiral' }
        'thinking' { 'spiral' }
        default    { $script:Motion.FaceExpression }
    }
    Update-SlopFaceLayer -Target $script:FaceLayer -Time ([DateTime]::UtcNow.Ticks / 1e7) -Speed $speed -Width $script:FaceRegion.Width -Height $script:FaceRegion.Height -Frozen:$frozen -Pattern $pattern -Inset 3.0
})
$script:MotionTimer.Start()

$window.Add_Closed({
    if ($script:ChatWindow) { $script:ChatWindow.Close() }
    if ($script:Timer) { $script:Timer.Stop() }
    if ($script:MotionTimer) { $script:MotionTimer.Stop() }
    if ($script:Cts) { $script:Cts.Cancel() }
    Reject-SlopPendingApprovals -Generation $script:RequestState.Generation
    try { $closeAuth = New-SlopOpenCodeAuthHeader } catch { $closeAuth = $null }
    if ($script:OpenCodeSessionId -and $closeAuth) {
        $session = [uri]::EscapeDataString($script:OpenCodeSessionId)
        $url = "$($script:OpenCodeBaseUrl)/api/session/$session"
        $job = Start-ThreadJob -ScriptBlock {
            param($Url, $Auth)
            try {
                $client = New-Object System.Net.Http.HttpClient
                $req = [Net.Http.HttpRequestMessage]::new('DELETE', $Url)
                foreach ($h in $Auth.GetEnumerator()) { $req.Headers.TryAddWithoutValidation($h.Key, $h.Value) | Out-Null }
                $client.SendAsync($req).GetAwaiter().GetResult() | Out-Null
            } catch { } finally { if ($client) { $client.Dispose() } }
        } -ArgumentList $url, $closeAuth
        $script:OpenCodeSideJobs.Add($job)
    }
    Remove-SlopCompletedSideJobs
    $script:OpenCodeSessionId = $null
})

$window.ShowDialog() | Out-Null
