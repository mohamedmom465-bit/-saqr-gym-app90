param(
  [switch]$Strict
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$android = Join-Path $root 'android'
$app = Join-Path $android 'app'
$manifest = Join-Path $app 'src/main/AndroidManifest.xml'

if (!(Test-Path $manifest)) { throw "AndroidManifest.xml not found. Run 'flutter create --platforms=android .' first." }

# 0) App-level compileSdk/NDK + multidex + lint + packaging (root cause of the
#    checkReleaseAarMetadata / duplicate resource failures we kept hitting on CI).
$gradleKtsPath = Join-Path $app 'build.gradle.kts'
if (Test-Path $gradleKtsPath) {
  $g = Get-Content $gradleKtsPath -Raw
  if ($g -notmatch 'compileSdk\s*=\s*36') {
    $g = [regex]::Replace($g, '(?m)^\s*compileSdk\s*=.*$', '    compileSdk = 36')
  }
  if ($g -notmatch 'ndkVersion\s*=\s*"28\.2\.13676358"') {
    if ($g -match '(?m)^\s*ndkVersion\s*=.*$') {
      $g = [regex]::Replace($g, '(?m)^\s*ndkVersion\s*=.*$', '    ndkVersion = "28.2.13676358"')
    } else {
      $g = [regex]::Replace($g, '(?s)(compileSdk\s*=\s*36)', '$1' + "`n    ndkVersion = `"28.2.13676358`"", 1)
    }
  }
  if ($g -notmatch 'multiDexEnabled\s*=\s*true') {
    $g = [regex]::Replace($g, '(?s)(defaultConfig\s*\{)', '$1' + "`n        multiDexEnabled = true", 1)
  }
  if ($g -notmatch 'androidx\.multidex:multidex') {
    if ($g -match '(?s)dependencies\s*\{') {
      $g = [regex]::Replace($g, '(?s)(dependencies\s*\{)', '$1' + "`n    implementation(`"androidx.multidex:multidex:2.0.1`")", 1)
    }
  }
  if ($g -notmatch '(?s)lint\s*\{') {
    $g = [regex]::Replace($g, '(?s)(android\s*\{)', '$1' + "`n    lint {`n        checkReleaseBuilds = false`n        abortOnError = false`n    }", 1)
  }
  if ($g -notmatch '(?s)packaging\s*\{') {
    $g = [regex]::Replace($g, '(?s)(android\s*\{)', '$1' + "`n    packaging {`n        resources {`n            excludes += setOf(`"META-INF/AL2.0`", `"META-INF/LGPL2.1`", `"META-INF/*.kotlin_module`")`n            pickFirsts += setOf(`"**/libc++_shared.so`", `"**/libjsc.so`")`n        }`n    }", 1)
  }
  Set-Content -Path $gradleKtsPath -Value $g -Encoding UTF8
}

# 0b) Root-level: force the SAME compileSdk/NDK on every plugin module too.
#     Without this, an individual plugin (e.g. file_picker) can still be
#     compiled against an older SDK than the app and fail checkReleaseAarMetadata,
#     even though the app module itself is set correctly above.
$rootGradleKts = Join-Path $android 'build.gradle.kts'
if (Test-Path $rootGradleKts) {
  $r = Get-Content $rootGradleKts -Raw
  if ($r -notmatch 'plugins\.withId\("com\.android\.library"\)') {
    $r += @"

subprojects {
    plugins.withId("com.android.library") {
        extensions.configure(com.android.build.gradle.LibraryExtension::class.java) {
            compileSdk = 36
            ndkVersion = "28.2.13676358"
        }
    }
    plugins.withId("com.android.application") {
        extensions.configure(com.android.build.gradle.BaseAppModuleExtension::class.java) {
            compileSdk = 36
            ndkVersion = "28.2.13676358"
        }
    }
}
"@
    Set-Content -Path $rootGradleKts -Value $r -Encoding UTF8
  }
}

# 1) Enable core-library desugaring required by flutter_local_notifications 18.x.
$gradleKts = Join-Path $app 'build.gradle.kts'
$gradleGroovy = Join-Path $app 'build.gradle'
if (Test-Path $gradleKts) {
  $p = Get-Content $gradleKts -Raw
  if ($p -notmatch 'isCoreLibraryDesugaringEnabled\s*=\s*true') {
    if ($p -notmatch '(?s)android\s*\{') { throw "android { } block not found in build.gradle.kts" }
    $p = [regex]::Replace($p, '(?s)(android\s*\{)', '$1' + "`n    compileOptions {`n        isCoreLibraryDesugaringEnabled = true`n        sourceCompatibility = JavaVersion.VERSION_17`n        targetCompatibility = JavaVersion.VERSION_17`n    }", 1)
  }
  if ($p -notmatch 'coreLibraryDesugaring\("com\.android\.tools:desugar_jdk_libs:2\.1\.4"\)') {
    if ($p -match '(?s)dependencies\s*\{') {
      $p = [regex]::Replace($p, '(?s)(dependencies\s*\{)', '$1' + "`n    coreLibraryDesugaring(`"com.android.tools:desugar_jdk_libs:2.1.4`")", 1)
    } else {
      $p += "`n`ndependencies {`n    coreLibraryDesugaring(\"com.android.tools:desugar_jdk_libs:2.1.4\")`n}`n"
    }
  }
  Set-Content -Path $gradleKts -Value $p -Encoding UTF8
} elseif (Test-Path $gradleGroovy) {
  $p = Get-Content $gradleGroovy -Raw
  if ($p -notmatch 'coreLibraryDesugaringEnabled\s+true') {
    if ($p -notmatch '(?s)android\s*\{') { throw "android { } block not found in build.gradle" }
    $p = [regex]::Replace($p, '(?s)(android\s*\{)', '$1' + "`n    compileOptions {`n        coreLibraryDesugaringEnabled true`n        sourceCompatibility JavaVersion.VERSION_17`n        targetCompatibility JavaVersion.VERSION_17`n    }", 1)
  }
  if ($p -notmatch 'desugar_jdk_libs:2\.1\.4') {
    if ($p -match '(?s)dependencies\s*\{') {
      $p = [regex]::Replace($p, '(?s)(dependencies\s*\{)', '$1' + "`n    coreLibraryDesugaring \"com.android.tools:desugar_jdk_libs:2.1.4\"", 1)
    } else {
      $p += "`n`ndependencies {`n    coreLibraryDesugaring \"com.android.tools:desugar_jdk_libs:2.1.4\"`n}`n"
    }
  }
  Set-Content -Path $gradleGroovy -Value $p -Encoding UTF8
} else {
  throw 'Neither android/app/build.gradle.kts nor android/app/build.gradle exists.'
}

# 2) Add explicit app permissions needed by camera + wake lock + scheduled notifications.
$m = Get-Content $manifest -Raw
$permissions = @(
  'android.permission.CAMERA',
  'android.permission.WAKE_LOCK',
  'android.permission.POST_NOTIFICATIONS',
  'android.permission.RECEIVE_BOOT_COMPLETED',
  'android.permission.VIBRATE'
)
foreach ($perm in $permissions) {
  if ($m -notmatch [regex]::Escape("android:name=\"$perm\"")) {
    $m = [regex]::Replace($m, '(<manifest[^>]*>)', '$1' + "`n    <uses-permission android:name=\"$perm\" />", 1)
  }
}

# 3) Scheduled notifications + notification actions receivers required by flutter_local_notifications 16+.
$receivers = @'
        <receiver
            android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver
            android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON" />
            </intent-filter>
        </receiver>
        <receiver
            android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver" />
'@
if ($m -notmatch 'com\.dexterous\.flutterlocalnotifications\.ScheduledNotificationReceiver') {
  $m = [regex]::Replace($m, '(?s)(<application\b[^>]*>)', '$1' + "`n" + $receivers.TrimEnd(), 1)
}
Set-Content -Path $manifest -Value $m -Encoding UTF8

Write-Host 'Android configuration applied: desugaring + permissions + notification receivers.'
