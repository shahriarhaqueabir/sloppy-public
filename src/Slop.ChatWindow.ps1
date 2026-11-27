# src/Slop.ChatWindow.ps1 -- geometry, interaction state and XAML for the
# separate transparent chat window. Dot-sourcing this file constructs no WPF
# objects; callers parse the XAML when they actually open the window.
$ErrorActionPreference = 'Stop'

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
        [double]$PetWidth = 26.0,
        [double]$PetHeight = 26.0,
        [Parameter(Mandatory)]$WorkArea,
        [ValidateSet('Extended','Full')][string]$Mode = 'Extended',
        [double]$ExtendedWidth = 760.0,
        [double]$ExtendedHeight = 540.0
    )
    if ($Mode -eq 'Full') {
        return Get-SlopWorkAreaClampedRect -Left ([double]$WorkArea.X) -Top ([double]$WorkArea.Y) `
            -Width ([double]$WorkArea.Width) -Height ([double]$WorkArea.Height) -WorkArea $WorkArea
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
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <!-- Readability comes from a dark backplate inside the transparent window,
         never from a system material that would replace the WPF surface. -->
    <Border x:Name="ChatBackplate" Grid.RowSpan="3" Margin="4" CornerRadius="12"
            Background="#E612141C" IsHitTestVisible="False"/>
    <Border x:Name="ChatChrome" Grid.Row="0" Background="#F21E293B"
            BorderBrush="#44FFFFFF" BorderThickness="1" CornerRadius="12,12,0,0">
      <Grid>
        <TextBlock Text="S.L.O.P. chat" Foreground="#EAEAEA" FontWeight="SemiBold"
                   FontSize="12" VerticalAlignment="Center" Margin="12,0,0,0"
                   IsHitTestVisible="False"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,0,8,0">
          <Button x:Name="ChatModeButton" Width="22" Height="22" Content="□"
                  ToolTip="Toggle chat size" Background="#33BFDBFE" Foreground="#EAEAEA"
                  BorderBrush="#55FFFFFF" BorderThickness="1" Cursor="Hand" FontSize="11"
                  AutomationProperties.Name="Toggle chat size"/>
          <Button x:Name="ChatCloseButton" Width="22" Height="22" Content="X"
                  ToolTip="Close chat" Background="#33BFDBFE" Foreground="#EAEAEA"
                  BorderBrush="#55FFFFFF" BorderThickness="1" Cursor="Hand" FontSize="11"
                  AutomationProperties.Name="Close chat"/>
        </StackPanel>
      </Grid>
    </Border>
    <Grid Grid.Row="1" Margin="12,6,12,6">
      <ScrollViewer x:Name="ChatScroll" VerticalScrollBarVisibility="Auto"
                    HorizontalScrollBarVisibility="Disabled">
        <StackPanel x:Name="ChatStack"/>
      </ScrollViewer>
    </Grid>
    <Border x:Name="ChatInputChrome" Grid.Row="2" Margin="12,0,12,12" Padding="8" CornerRadius="10"
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
                   Background="#18FFFFFF" Foreground="#EAEAEA" BorderBrush="#44FFFFFF"
                   VerticalContentAlignment="Center"/>
          <TextBlock x:Name="InputPlaceholder" Grid.Column="0" Text="Say something..."
                     Foreground="#93A4BD" FontSize="13" Margin="11,0,0,0"
                     VerticalAlignment="Center" IsHitTestVisible="False"/>
          <Button x:Name="MicBtn" Grid.Column="1" Content="🎤" Width="34" Height="32"
                  Margin="6,0,0,0" Background="#33BFDBFE" Foreground="#EAEAEA"
                  BorderBrush="#55FFFFFF" BorderThickness="1" Cursor="Hand"
                  AutomationProperties.Name="Voice input"/>
          <Button x:Name="SendBtn" Grid.Column="2" Content="Send" Width="54" Height="32"
                  Margin="6,0,0,0" Background="#33BFDBFE" Foreground="#EAEAEA"
                  BorderBrush="#55FFFFFF" BorderThickness="1" Cursor="Hand"
                  AutomationProperties.Name="Send message"/>
          <Button x:Name="StopBtn" Grid.Column="3" Content="Stop" Width="54" Height="32"
                  Margin="6,0,0,0" Visibility="Collapsed" Background="#33BFDBFE"
                  Foreground="#EAEAEA" BorderBrush="#55FFFFFF" BorderThickness="1"
                  Cursor="Hand" AutomationProperties.Name="Stop request"/>
        </Grid>
      </StackPanel>
    </Border>
  </Grid>
</Window>
'@
}
