# Four-screen first-run wizard. WPF is confined to Show-SlopOnboarding; the
# preset and markdown helpers below stay headless for tests.
$ErrorActionPreference = 'Stop'
if (-not (Get-Command Get-SlopIdentityColors -ErrorAction SilentlyContinue)) {
    throw 'Slop.Config.ps1 must be dot-sourced before Slop.Onboarding.ps1'
}

$script:SlopPresetPersonas = @{
    calm         = @{ Label = 'Calm';         Sample = 'Let us take this one step at a time. No rush.' }
    playful      = @{ Label = 'Playful';      Sample = 'Okay, that is a delightfully weird question. I am in.' }
    curious      = @{ Label = 'Curious';      Sample = 'Ooh — tell me more about that. What made you think of it?' }
    professional = @{ Label = 'Professional'; Sample = 'Understood. Here is the concise answer, then the trade-offs.' }
}

function Get-SlopPersonaPresets {
    return @($script:SlopPresetPersonas.Keys | Sort-Object | ForEach-Object {
        [pscustomobject]@{ Id = $_; Label = $script:SlopPresetPersonas[$_].Label; Sample = $script:SlopPresetPersonas[$_].Sample }
    })
}

function New-SlopPersonaMarkdown {
    param(
        [Parameter(Mandatory)][ValidateSet('calm','playful','curious','professional')][string]$Preset,
        [Parameter(Mandatory)][string]$Name,
        [string]$OwnerName = '',
        [AllowEmptyString()][string]$CustomText = ''
    )
    $voice = @{
        calm         = 'Speak calmly and briefly. Never rush the user.'
        playful      = 'Be warm, light and playful. Use the occasional dry joke.'
        curious      = 'Lead with genuine curiosity and one follow-up question.'
        professional = 'Be concise, precise and structured. State trade-offs.'
    }[$Preset]
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add("You are $Name, a small private desktop companion.")
    if (-not [string]::IsNullOrWhiteSpace($OwnerName)) {
        $lines.Add("The person you talk to goes by $OwnerName. Use it only when it feels natural.")
    }
    $lines.Add($voice)
    $lines.Add('You live on the users computer. You have no accounts, no cloud and no tools.')
    $lines.Add('Be honest about what you can and cannot do. Keep replies short enough to read at a glance.')
    if (-not [string]::IsNullOrWhiteSpace($CustomText)) {
        $lines.Add('')
        $lines.Add('Additional instructions from the user:')
        $lines.Add($CustomText.Trim())
    }
    return ($lines -join "`n") + "`n"
}

# A first-run dismissal still needs a usable default persona. Kept headless so
# the shell bootstrap can call it without opening a second window.
function New-SlopFallbackOnboardingResult {
    param([Parameter(Mandatory)][hashtable]$Config)
    $result = @{} + (New-SlopDefaultConfig)
    foreach ($key in $Config.Keys) { if ($result.ContainsKey($key)) { $result[$key] = $Config[$key] } }
    $result.personaText = New-SlopPersonaMarkdown -Preset 'calm' -Name ([string]$result.name) -OwnerName ([string]$result.ownerName) -CustomText ([string]$result.instructions)
    return $result
}

function Show-SlopOnboarding {
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [ValidateRange(1,4)][int]$StartScreen = 1
    )

    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Sloppy setup" Width="520" Height="360"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ResizeMode="NoResize" WindowStartupLocation="CenterScreen">
  <Window.Resources>
    <Style x:Key="SlopButton" TargetType="Button">
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="BorderBrush" Value="Transparent"/>
    </Style>
  </Window.Resources>
  <Border Margin="12" CornerRadius="18" Background="#F21E293B"
          BorderBrush="#663B82F6" BorderThickness="1" Padding="18">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <TextBlock x:Name="StepTitle" Foreground="#EAEAEA" FontWeight="Bold" FontSize="15"
                 Margin="2,0,0,10" Text="1 of 4 · What should I call you?"/>
      <Grid Grid.Row="1">
        <StackPanel x:Name="Screen1" VerticalAlignment="Center">
          <TextBlock Foreground="#B8B8C0" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,8"
                     Text="Pick a name for your companion. You can change it later."/>
          <TextBox x:Name="NameBox" Height="32" FontSize="13" MaxLength="40"
                   Background="#18FFFFFF" Foreground="#EAEAEA" BorderBrush="#44FFFFFF"
                   Padding="7,4" VerticalContentAlignment="Center"/>
          <TextBlock Foreground="#B8B8C0" FontSize="11" TextWrapping="Wrap" Margin="0,14,0,8"
                     Text="What should I call you? (optional)"/>
          <TextBox x:Name="OwnerBox" Height="32" FontSize="13" MaxLength="40"
                   Background="#18FFFFFF" Foreground="#EAEAEA" BorderBrush="#44FFFFFF"
                   Padding="7,4" VerticalContentAlignment="Center"/>
        </StackPanel>
        <StackPanel x:Name="Screen2" Visibility="Collapsed" VerticalAlignment="Center"
                    HorizontalAlignment="Center">
          <TextBlock Foreground="#B8B8C0" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,12"
                     HorizontalAlignment="Center" Text="Choose your colour."/>
          <WrapPanel x:Name="SwatchStrip" Width="300" HorizontalAlignment="Center"/>
          <Ellipse x:Name="PreviewPea" Width="26" Height="26" Margin="0,20,0,0"
                   HorizontalAlignment="Center" Fill="#6366F1"/>
        </StackPanel>
        <StackPanel x:Name="Screen3" Visibility="Collapsed">
          <TextBlock Foreground="#B8B8C0" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,6"
                     Text="Pick a voice, then add any instructions you want kept."/>
          <StackPanel x:Name="PresetList"/>
          <TextBlock x:Name="SampleLine" Foreground="#D6D6E0" FontSize="11" FontStyle="Italic"
                     TextWrapping="Wrap" MinHeight="34" Margin="10,6,0,8"/>
          <TextBox x:Name="CustomBox" Height="66" FontSize="11" AcceptsReturn="True"
                   TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"
                   Background="#18FFFFFF" Foreground="#EAEAEA" BorderBrush="#44FFFFFF"
                   Padding="7,5" ToolTip="Anything else I should remember?"/>
        </StackPanel>
        <ScrollViewer x:Name="Screen4" Visibility="Collapsed" VerticalScrollBarVisibility="Auto">
          <StackPanel Margin="0,0,8,0">
            <TextBlock Foreground="#B8B8C0" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,8"
                       Text="Choose where answers come from. Tier 1 - built-in local Qwen; Tier 2 - OpenCode. Custom is an advanced local endpoint, not a tier. Nothing is sent anywhere until you opt in."/>
            <RadioButton x:Name="BrainBuiltIn" GroupName="SlopBrain" IsChecked="True"
                         Foreground="#EAEAEA" FontSize="11" Margin="0,2"
                         Content="Built-in — works offline (recommended)"/>
            <RadioButton x:Name="BrainCustom" GroupName="SlopBrain"
                         Foreground="#EAEAEA" FontSize="11" Margin="0,2"
                         Content="Custom — local OpenAI-compatible endpoint"/>
            <StackPanel x:Name="EndpointRow" Visibility="Collapsed" Margin="20,4,0,8">
              <TextBox x:Name="EndpointBox" Height="28" FontSize="11" MaxLength="200"
                       Background="#18FFFFFF" Foreground="#EAEAEA" BorderBrush="#44FFFFFF"
                       Padding="6,3" VerticalContentAlignment="Center"
                       ToolTip="Local http URL, for example http://127.0.0.1:11434"/>
              <TextBox x:Name="ModelBox" Height="28" FontSize="11" MaxLength="120" Margin="0,6,0,0"
                       Background="#18FFFFFF" Foreground="#EAEAEA" BorderBrush="#44FFFFFF"
                       Padding="6,3" VerticalContentAlignment="Center" ToolTip="Model name"/>
            </StackPanel>
            <RadioButton x:Name="BrainOpenCodeLocal" GroupName="SlopBrain"
                         Foreground="#EAEAEA" FontSize="11" Margin="0,2"
                         Content="OpenCode — use a local provider"/>
            <RadioButton x:Name="BrainOpenCodeRemote" GroupName="SlopBrain"
                         Foreground="#EAEAEA" FontSize="11" Margin="0,2"
                         Content="OpenCode — use a remote provider (disclosure first)"/>
            <StackPanel x:Name="OpenCodeRow" Visibility="Collapsed" Margin="20,4,0,8">
              <TextBox x:Name="ProviderBox" Height="27" FontSize="11" MaxLength="80"
                       Background="#18FFFFFF" Foreground="#EAEAEA" BorderBrush="#44FFFFFF"
                       Padding="6,3" VerticalContentAlignment="Center" ToolTip="Provider, for example Ollama"/>
              <TextBox x:Name="RouteModelBox" Height="27" FontSize="11" MaxLength="120" Margin="0,5,0,0"
                       Background="#18FFFFFF" Foreground="#EAEAEA" BorderBrush="#44FFFFFF"
                       Padding="6,3" VerticalContentAlignment="Center" ToolTip="Model"/>
              <TextBox x:Name="AgentBox" Height="27" FontSize="11" MaxLength="80" Margin="0,5,0,0"
                       Background="#18FFFFFF" Foreground="#EAEAEA" BorderBrush="#44FFFFFF"
                       Padding="6,3" VerticalContentAlignment="Center" ToolTip="OpenCode agent id"/>
              <ComboBox x:Name="ProfileCombo" Height="27" FontSize="11" Margin="0,5,0,0"
                        ToolTip="Capability profile"/>
              <TextBlock x:Name="EffectiveModelText" Foreground="#B8B8C0" FontSize="10"
                         Margin="0,5,0,0" TextWrapping="Wrap"/>
              <Button x:Name="TermsButton" Content="Read the data route and provider terms"
                      Style="{StaticResource SlopButton}" Background="#22FFFFFF"
                      Foreground="#EAEAEA" FontSize="10" HorizontalAlignment="Left"
                      Padding="8,3" Margin="0,8,0,0"/>
            </StackPanel>
            <TextBlock Text="Voice input" Foreground="#93A4BD" FontSize="10" FontWeight="SemiBold" Margin="0,8,0,4"/>
            <CheckBox x:Name="VoiceEnabledCheck" Foreground="#B8B8C0" FontSize="10" Margin="0,2,0,4"
                      Content="Enable voice input (local Whisper small; off by default)"/>
            <ComboBox x:Name="VoiceLanguageCombo" Height="26" FontSize="11" Width="120"
                      HorizontalAlignment="Left" ToolTip="Whisper language"/>
            <TextBlock x:Name="VoiceReadyText" Foreground="#8A8A96" FontSize="10" TextWrapping="Wrap"
                       Margin="0,5,0,0" Text="Whisper readiness: checking"/>
          </StackPanel>
        </ScrollViewer>
      </Grid>
      <DockPanel Grid.Row="2" Margin="0,12,0,0" LastChildFill="False">
        <TextBlock x:Name="ErrorText" DockPanel.Dock="Left" Foreground="#FCA5A5" FontSize="10"
                   TextWrapping="Wrap" MaxWidth="320" VerticalAlignment="Center"/>
        <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
          <Button x:Name="CloseBtn" Content="Cancel" Style="{StaticResource SlopButton}"
                  Background="#22FFFFFF" Foreground="#EAEAEA" FontSize="11"
                  Padding="10,4" Margin="0,0,6,0"/>
          <Button x:Name="BackBtn" Content="Back" Style="{StaticResource SlopButton}"
                  Background="#22FFFFFF" Foreground="#EAEAEA" FontSize="11"
                  Padding="10,4" Margin="0,0,6,0"/>
          <Button x:Name="NextBtn" Content="Next" Style="{StaticResource SlopButton}"
                  Background="#3B82F6" Foreground="White" FontSize="11"
                  FontWeight="SemiBold" Padding="12,4"/>
        </StackPanel>
      </DockPanel>
    </Grid>
  </Border>
</Window>
'@
    $dlg = [System.Windows.Markup.XamlReader]::Parse($xaml)
    # WPF refuses Owner when the owner window has not been shown yet. First run
    # opens the wizard before the shell window, so only attach when it is safe.
    if ($window -and $window.IsVisible) { $dlg.Owner = $window }

    $script:SlopOnboardingDialog = $dlg
    $script:SlopOnboardingScreen = $StartScreen
    $script:SlopOnboardingResult = $null
    $script:SelectedColor = if ($Config.color) { [string]$Config.color } else { 'ocean' }
    $script:SelectedPreset = if ($Config.personality) { [string]$Config.personality } else { 'calm' }

    $NameBox = $dlg.FindName('NameBox')
    $OwnerBox = $dlg.FindName('OwnerBox')
    $SwatchStrip = $dlg.FindName('SwatchStrip')
    $PreviewPea = $dlg.FindName('PreviewPea')
    $PresetList = $dlg.FindName('PresetList')
    $SampleLine = $dlg.FindName('SampleLine')
    $CustomBox = $dlg.FindName('CustomBox')
    $EndpointRow = $dlg.FindName('EndpointRow')
    $EndpointBox = $dlg.FindName('EndpointBox')
    $ModelBox = $dlg.FindName('ModelBox')
    $OpenCodeRow = $dlg.FindName('OpenCodeRow')
    $ProviderBox = $dlg.FindName('ProviderBox')
    $RouteModelBox = $dlg.FindName('RouteModelBox')
    $AgentBox = $dlg.FindName('AgentBox')
    $ProfileCombo = $dlg.FindName('ProfileCombo')
    $EffectiveModelText = $dlg.FindName('EffectiveModelText')
    $VoiceEnabledCheck = $dlg.FindName('VoiceEnabledCheck')
    $VoiceLanguageCombo = $dlg.FindName('VoiceLanguageCombo')
    $VoiceReadyText = $dlg.FindName('VoiceReadyText')
    $StepTitle = $dlg.FindName('StepTitle')
    $ErrorText = $dlg.FindName('ErrorText')
    $BackBtn = $dlg.FindName('BackBtn')
    $NextBtn = $dlg.FindName('NextBtn')

    $defaults = New-SlopDefaultConfig
    $NameBox.Text = if ($Config.name) { [string]$Config.name } else { [string]$defaults.name }
    $OwnerBox.Text = if ($Config.ownerName) { [string]$Config.ownerName } else { [string]$defaults.ownerName }
    $CustomBox.Text = if ($Config.instructions) { [string]$Config.instructions } else { [string]$defaults.instructions }
    $EndpointBox.Text = if ($Config.endpointUrl) { [string]$Config.endpointUrl } else { [string]$defaults.endpointUrl }
    $ModelBox.Text = if ($Config.modelName) { [string]$Config.modelName } elseif ($Config.model) { [string]$Config.model } else { [string]$defaults.modelName }
    $ProviderBox.Text = if ($Config.provider) { [string]$Config.provider } else { [string]$defaults.provider }
    $RouteModelBox.Text = if ($Config.model) { [string]$Config.model } else { @(Get-SlopBrainModelOptions -Brain 'opencode')[0] }
    $AgentBox.Text = if ($Config.agentId) { [string]$Config.agentId } else { 'sloppy' }
    foreach ($preset in Get-SlopPersonalities) { $ProfileCombo.Items.Add($preset) | Out-Null }
    foreach ($profile in Get-SlopCapabilityProfiles) { $ProfileCombo.Items.Add($profile) | Out-Null }
    $ProfileCombo.SelectedItem = if ($Config.capabilityProfile) { [string]$Config.capabilityProfile } else { 'companion' }
    $VoiceEnabledCheck.IsChecked = [bool]$Config.voiceEnabled
    foreach ($language in Get-SlopWhisperLanguages) { $VoiceLanguageCombo.Items.Add($language) | Out-Null }
    $VoiceLanguageCombo.SelectedItem = if ($Config.whisperLanguage) { [string]$Config.whisperLanguage } else { 'auto' }
    $VoiceReadyText.Text = 'Whisper readiness: ' + (Get-SlopVoiceReadinessText -Config $Config)

    $titles = @(
        '1 of 4 · What should I call you?',
        '2 of 4 · Pick your colour',
        '3 of 4 · Choose your voice',
        '4 of 4 · Where do answers come from?'
    )

    function Set-SlopWizardScreen {
        param([int]$Number)
        $script:SlopOnboardingScreen = $Number
        for ($i = 1; $i -le 4; $i++) {
            $screen = $dlg.FindName("Screen$i")
            if ($screen) { $screen.Visibility = if ($i -eq $Number) { 'Visible' } else { 'Collapsed' } }
        }
        $StepTitle.Text = $titles[$Number - 1]
        $ErrorText.Text = ''
        $BackBtn.IsEnabled = ($Number -gt 1)
        $NextBtn.Content = if ($Number -eq 4) { 'Finish' } else { 'Next' }
    }

    foreach ($entry in (Get-SlopIdentityColors).GetEnumerator() | Sort-Object Key) {
        $key = [string]$entry.Key
        $swatch = New-Object System.Windows.Controls.Button
        $swatch.Width = 30; $swatch.Height = 30; $swatch.CornerRadius = [System.Windows.CornerRadius]::new(15)
        $swatch.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString([string]$entry.Value)
        $swatch.Margin = [System.Windows.Thickness]::new(0,0,8,8)
        $swatch.Cursor = 'Hand'; $swatch.ToolTip = $key; $swatch.Tag = $key
        $swatch.Style = $window.Resources['SlopButton']
        $swatch.Add_Click({ param($s,$e)
            $script:SelectedColor = [string]$s.Tag
            $PreviewPea.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString((Get-SlopIdentityColor -ColorKey $script:SelectedColor))
        })
        $SwatchStrip.Children.Add($swatch) | Out-Null
    }
    $PreviewPea.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString((Get-SlopIdentityColor -ColorKey $script:SelectedColor))

    foreach ($preset in Get-SlopPersonaPresets) {
        $id = [string]$preset.Id
        $radio = New-Object System.Windows.Controls.RadioButton
        $radio.GroupName = 'SlopPreset'
        $radio.Content = $preset.Label
        $radio.Tag = $id
        $radio.Foreground = [System.Windows.Media.Brushes]::White
        $radio.FontSize = 11
        $radio.Margin = [System.Windows.Thickness]::new(10,2,0,2)
        $radio.IsChecked = ($id -eq $script:SelectedPreset)
        $radio.Add_Checked({ param($s,$e)
            $script:SelectedPreset = [string]$s.Tag
            $sample = Get-SlopPersonaPresets | Where-Object { $_.Id -eq $script:SelectedPreset } | Select-Object -First 1
            if ($sample) { $SampleLine.Text = $sample.Sample }
        })
        $PresetList.Children.Add($radio) | Out-Null
    }
    $initialSample = Get-SlopPersonaPresets | Where-Object { $_.Id -eq $script:SelectedPreset } | Select-Object -First 1
    if ($initialSample) { $SampleLine.Text = $initialSample.Sample }

    function Update-SlopBrainFields {
        if ($BrainCustom.IsChecked) {
            $EndpointRow.Visibility = 'Visible'
            $OpenCodeRow.Visibility = 'Collapsed'
        }
        elseif ($BrainOpenCodeLocal.IsChecked -or $BrainOpenCodeRemote.IsChecked) {
            $EndpointRow.Visibility = 'Collapsed'
            $OpenCodeRow.Visibility = 'Visible'
        }
        else {
            $EndpointRow.Visibility = 'Collapsed'
            $OpenCodeRow.Visibility = 'Collapsed'
        }
        $cfg = @{} + (New-SlopDefaultConfig)
        $cfg.agent = @{}
        $cfg.model = [string]$RouteModelBox.Text
        $agentStub = @{ model = [string]$RouteModelBox.Text }
        $EffectiveModelText.Text = 'Effective model: ' + (Resolve-SlopEffectiveModel -Agent $agentStub -Config $cfg)
    }
    foreach ($r in @($BrainBuiltIn,$BrainCustom,$BrainOpenCodeLocal,$BrainOpenCodeRemote)) {
        $r.Add_Checked({ param($s,$e) Update-SlopBrainFields })
    }
    Update-SlopBrainFields

    $TermsButton = $dlg.FindName('TermsButton')
    $TermsButton.Add_Click({ param($s,$e)
        if (Get-Command Show-SlopDisclosure -ErrorAction SilentlyContinue) {
            $kind = if ($BrainOpenCodeRemote.IsChecked) { 'opencode-remote' } else { 'opencode-local' }
            # No verified provider terms URL is bundled. An empty value makes the
            # disclosure state plainly that retention/training terms are unknown.
            Show-SlopDisclosure -Route @{ Kind=$kind; Provider=[string]$ProviderBox.Text; Model=[string]$RouteModelBox.Text } | Out-Null
        }
    })

    function Get-SlopWizardConfig {
        $result = @{} + (New-SlopDefaultConfig)
        $result.name = $NameBox.Text.Trim()
        $result.ownerName = $OwnerBox.Text.Trim()
        $result.instructions = $CustomBox.Text.Trim()
        $result.color = $script:SelectedColor
        $result.personality = $script:SelectedPreset
        $result.autostart = [bool]$Config.autostart
        $result.voiceEnabled = [bool]$VoiceEnabledCheck.IsChecked
        $result.whisperLanguage = ([string]$VoiceLanguageCombo.SelectedItem).Trim().ToLowerInvariant()

        if ($BrainCustom.IsChecked) {
            $result.brain = 'custom'
            $result.endpointUrl = $EndpointBox.Text.Trim()
            $result.model = $ModelBox.Text.Trim()
            $result.modelName = $ModelBox.Text.Trim()
        }
        elseif ($BrainOpenCodeLocal.IsChecked -or $BrainOpenCodeRemote.IsChecked) {
            $result.brain = 'opencode'
            $result.providerLocality = if ($BrainOpenCodeLocal.IsChecked) { 'local' } else { 'remote' }
            $result.termsUrl = ''
            $result.provider = $ProviderBox.Text.Trim()
            $result.model = $RouteModelBox.Text.Trim()
            $result.modelName = $RouteModelBox.Text.Trim()
            $result.agentId = $AgentBox.Text.Trim()
            $result.agent = @{}
            $result.capabilityProfile = [string]$ProfileCombo.SelectedItem
            $result.openCodeBaseUrl = if ($Config.openCodeBaseUrl) { [string]$Config.openCodeBaseUrl } else { 'http://127.0.0.1:28894' }
            $serviceJson = Join-Path $env:USERPROFILE '.config/opencode/service.json'
            $result.serviceConfigPath = if (Test-Path -LiteralPath $serviceJson) { $serviceJson } else { '' }
        }
        else {
            $result.brain = 'builtin'
        }
        $result.personaText = New-SlopPersonaMarkdown -Preset $result.personality -Name $result.name `
            -OwnerName $result.ownerName -CustomText $CustomBox.Text
        return $result
    }

    function Test-SlopWizardStep {
        param([int]$Number)
        if ($Number -eq 1) {
            $name = $NameBox.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($name) -or $name.Length -gt 40) {
                return 'Give your companion a name between 1 and 40 characters.'
            }
        }
        if ($Number -eq 4) {
            $candidate = Get-SlopWizardConfig
            $check = Test-SlopConfig -Config $candidate
            if (-not $check.Ok) { return ($check.Errors -join '; ') }
            if ($candidate.brain -eq 'custom' -and [string]::IsNullOrWhiteSpace($candidate.model)) {
                return 'Enter the model name your local server expects.'
            }
            if ($candidate.brain -eq 'opencode' -and [string]::IsNullOrWhiteSpace($candidate.model)) {
                return 'Enter the provider model name so the badge can name the real route.'
            }
        }
        return $null
    }

    function Move-SlopWizard {
        param([int]$Delta)
        if ($Delta -gt 0) {
            $problem = Test-SlopWizardStep -Number $script:SlopOnboardingScreen
            if ($problem) { $ErrorText.Text = $problem; return }
            if ($script:SlopOnboardingScreen -eq 4) {
                $script:SlopOnboardingResult = Get-SlopWizardConfig
                $dlg.DialogResult = $true
                return
            }
            Set-SlopWizardScreen -Number ($script:SlopOnboardingScreen + 1)
            return
        }
        if ($script:SlopOnboardingScreen -gt 1) { Set-SlopWizardScreen -Number ($script:SlopOnboardingScreen - 1) }
    }

    $NextBtn.Add_Click({ param($s,$e) Move-SlopWizard -Delta 1 })
    $BackBtn.Add_Click({ param($s,$e) Move-SlopWizard -Delta -1 })
    $CloseBtn.Add_Click({ param($s,$e) $script:SlopOnboardingResult = $null; $dlg.DialogResult = $false })
    $dlg.Add_KeyDown({ param($s,$e)
        if ($e.Key -eq [System.Windows.Input.Key]::Escape) { $script:SlopOnboardingResult = $null; $dlg.DialogResult = $false; $e.Handled = $true; return }
        if ($e.Key -eq [System.Windows.Input.Key]::Enter) {
            # Multiline instructions keep Enter as a newline; every other
            # control commits the current screen.
            if ([System.Windows.Input.Keyboard]::FocusedElement -eq $CustomBox) { return }
            Move-SlopWizard -Delta 1
            $e.Handled = $true
        }
    })

    Set-SlopWizardScreen -Number $StartScreen
    $accepted = $dlg.ShowDialog()
    if ($accepted -and $script:SlopOnboardingResult) { return $script:SlopOnboardingResult }
    return $null
}
