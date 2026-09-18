$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$app = Join-Path $root 'android/app'
$manifest = Join-Path $app 'src/main/AndroidManifest.xml'
if (!(Test-Path $manifest)) { throw 'AndroidManifest.xml is missing.' }
$gradle = if (Test-Path (Join-Path $app 'build.gradle.kts')) { Get-Content (Join-Path $app 'build.gradle.kts') -Raw } else { Get-Content (Join-Path $app 'build.gradle') -Raw }
$rootGradlePath = Join-Path $root 'android/build.gradle.kts'
$rootGradle = if (Test-Path $rootGradlePath) { Get-Content $rootGradlePath -Raw } else { '' }
$m = Get-Content $manifest -Raw
$checks = @(
  @('app compileSdk = 36', ($gradle -match 'compileSdk\s*=\s*36')),
  @('app ndkVersion 28.2.13676358', ($gradle -match 'ndkVersion\s*=\s*"28\.2\.13676358"')),
  @('multidex enabled', ($gradle -match 'multiDexEnabled\s*=\s*true')),
  @('packaging excludes configured', ($gradle -match '(?s)packaging\s*\{')),
  @('root-level compileSdk unified across all plugins', ($rootGradle -match 'plugins\.withId\("com\.android\.library"\)')),
  @('core library desugaring', ($gradle -match 'isCoreLibraryDesugaringEnabled\s*=\s*true|coreLibraryDesugaringEnabled\s+true')),
  @('desugar_jdk_libs 2.1.4', ($gradle -match 'desugar_jdk_libs:2\.1\.4')),
  @('CAMERA permission', ($m -match 'android\.permission\.CAMERA')),
  @('WAKE_LOCK permission', ($m -match 'android\.permission\.WAKE_LOCK')),
  @('POST_NOTIFICATIONS permission', ($m -match 'android\.permission\.POST_NOTIFICATIONS')),
  @('RECEIVE_BOOT_COMPLETED permission', ($m -match 'android\.permission\.RECEIVE_BOOT_COMPLETED')),
  @('ScheduledNotificationReceiver', ($m -match 'ScheduledNotificationReceiver')),
  @('ScheduledNotificationBootReceiver', ($m -match 'ScheduledNotificationBootReceiver')),
  @('ActionBroadcastReceiver', ($m -match 'ActionBroadcastReceiver'))
)
$failed = $false
foreach ($c in $checks) {
  if ($c[1]) { Write-Host "[OK] $($c[0])" } else { Write-Host "[FAIL] $($c[0])"; $failed = $true }
}
if ($failed) { exit 1 }
