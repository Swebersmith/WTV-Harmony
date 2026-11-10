param(
  [string]$ToolHome,
  [string]$BuildRoot = (Join-Path $env:TEMP 'wtv-harmony-build'),
  [string]$OutputDir,
  [string]$SigningConfigPath,
  [string]$JdkHome,
  [switch]$RequireApi26
)
$ErrorActionPreference = 'Stop'
$sourceRoot = $PSScriptRoot
if (-not $ToolHome) {
  throw '请通过 -ToolHome 指定 HarmonyOS API 26 DevEco 或 Command Line Tools 目录。'
}
$ToolHome = (Resolve-Path -LiteralPath $ToolHome).Path
# Give the SDK a path accepted by Hvigor even when the original workspace has Chinese characters.
$toolAlias = Join-Path (Split-Path -Parent $BuildRoot) 'wtv-harmony-tools'
if ($ToolHome -match '[^\x00-\x7F]') {
  if (-not (Test-Path -LiteralPath $toolAlias)) { New-Item -ItemType Junction -Path $toolAlias -Target $ToolHome | Out-Null }
  if ((Get-Item -LiteralPath $toolAlias).Target -ne $ToolHome) { throw '工具别名已指向其他目录，请更换 BuildRoot 的父目录。' }
  $ToolHome = $toolAlias
}
$sdk = Get-Content -LiteralPath (Join-Path $ToolHome 'sdk\default\sdk-pkg.json') -Raw | ConvertFrom-Json
$isApi26 = $sdk.data.apiVersion -eq '26' -or $sdk.data.apiVersion -eq '26.0.0'
if (-not $isApi26) { throw '本工程需要 HarmonyOS 7 / API 26 SDK。' }
New-Item -ItemType Directory -Path $BuildRoot -Force | Out-Null
foreach ($name in @('AppScope','entry','mpv','hvigor','build-profile.json5','hvigorfile.ts','oh-package.json5')) {
  Copy-Item -LiteralPath (Join-Path $sourceRoot $name) -Destination $BuildRoot -Recurse -Force
}
$profilePath = Join-Path $BuildRoot 'build-profile.json5'
$profile = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json
if ($isApi26) {
  $profile.app.products[0].targetSdkVersion = '26.0.0'
  $hvigorConfig = @{modelVersion='26.0.0';dependencies=@{};execution=@{daemon=$false};logging=@{level='info'}}
  $hvigorConfig | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $BuildRoot 'hvigor\hvigor-config.json5') -Encoding utf8
  $package = Get-Content -LiteralPath (Join-Path $BuildRoot 'oh-package.json5') -Raw | ConvertFrom-Json
  $package.modelVersion = '26.0.0'
  $package | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $BuildRoot 'oh-package.json5') -Encoding utf8
}
if ($SigningConfigPath) {
  $material = Get-Content -LiteralPath $SigningConfigPath -Raw | ConvertFrom-Json
  $profile.app.signingConfigs = @(@{name='default';type='HarmonyOS';material=$material})
  $profile.app.products[0] | Add-Member -NotePropertyName signingConfig -NotePropertyValue default -Force
}
$profile | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $profilePath -Encoding utf8
$env:NODE_HOME = Join-Path $ToolHome 'tools\node'
if (-not (Test-Path -LiteralPath $env:NODE_HOME)) { $env:NODE_HOME = Join-Path $ToolHome 'tool\node' }
$selectedJdk = if ($JdkHome) { $JdkHome } elseif (Test-Path -LiteralPath (Join-Path $ToolHome 'jbr')) { Join-Path $ToolHome 'jbr' } else { $env:JAVA_HOME }
if (-not $selectedJdk -or -not (Test-Path -LiteralPath (Join-Path $selectedJdk 'bin\java.exe'))) { throw '请用 -JdkHome 指定 JDK；API 26 建议使用 JDK 21。' }
$env:JAVA_HOME = $selectedJdk
$env:DEVECO_SDK_HOME = Join-Path $ToolHome 'sdk'
$env:Path = "$env:NODE_HOME;$env:JAVA_HOME\bin;$env:Path"
$hvigor = Join-Path $ToolHome 'tools\hvigor\bin\hvigorw.bat'
if (-not (Test-Path -LiteralPath $hvigor)) { $hvigor = Join-Path $ToolHome 'bin\hvigorw.bat' }
Push-Location -LiteralPath $BuildRoot
try {
  & (Join-Path $ToolHome 'bin\ohpm.bat') install --all
  if ($LASTEXITCODE -ne 0) { throw '本地 MPV 模块依赖安装失败。' }
  & $hvigor assembleHap --mode module -p product=default -p buildMode=debug --no-daemon 2>&1 | Tee-Object -FilePath (Join-Path $sourceRoot 'last-build.log')
  if ($LASTEXITCODE -ne 0) { throw "HAP 编译失败，退出码 $LASTEXITCODE" }
} finally { Pop-Location }
$outputRoot = if ($OutputDir) { $OutputDir } else { Join-Path $sourceRoot 'dist' }
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
$suffix = if ($SigningConfigPath) {'signed'} else {'unsigned'}
$inputHap = Join-Path $BuildRoot "entry\build\default\outputs\default\entry-default-$suffix.hap"
$appVersion = (Get-Content -LiteralPath (Join-Path $sourceRoot 'AppScope\app.json5') -Raw | ConvertFrom-Json).app.versionName
$outputHap = Join-Path $outputRoot "YingyuVideo-$appVersion-$suffix.hap"
Copy-Item -LiteralPath $inputHap -Destination $outputHap -Force
Write-Output "HAP: $outputHap"
Write-Output "SDK: $($sdk.data.displayName) / $($sdk.data.apiVersion)"
Get-FileHash -LiteralPath $outputHap -Algorithm SHA256
