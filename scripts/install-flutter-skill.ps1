# 安装并修复 flutter-skill CLI（Windows）
# 用途：给 AI/自动化提供 Flutter 应用截图、点击、inspect 能力。
# 注意：CLI 原生二进制在 npm 包里有 Windows 命名 bug，这里做一次修复。
$ErrorActionPreference = "Stop"
$env:HTTPS_PROXY = ""
$env:HTTP_PROXY = ""

Write-Host "[1/4] npm 安装 flutter-skill"
npm install -g flutter-skill

$pkg = Join-Path $env:APPDATA "npm\node_modules\flutter-skill"
$version = (Get-Content (Join-Path $pkg "package.json") | ConvertFrom-Json).version
Write-Host "[2/4] 下载 Windows 原生二进制（v$version 资产）"
$release = "v0.9.37"
$binDir = Join-Path $env:USERPROFILE ".flutter-skill\bin"
New-Item -ItemType Directory -Force -Path $binDir | Out-Null
$exe = Join-Path $binDir "flutter-skill-windows-x64.exe-v$version.exe"
if (-not (Test-Path $exe)) {
    curl.exe -L --fail --retry 2 `
        -o $exe `
        "https://github.com/ai-dashboad/flutter-skill/releases/download/$release/flutter-skill-windows-x64.exe"
}

Write-Host "[3/4] 修复 CLI 的 Windows 后缀判断"
$cli = Join-Path $pkg "bin\cli.js"
$text = Get-Content $cli -Raw
if ($text -notmatch "suffix") {
    $text = $text.Replace(
        '  return path.join(binDir, `${binaryName}-v${VERSION}`);',
        "  const suffix = process.platform === 'win32' ? '.exe' : '';`n  return path.join(binDir, ``${binaryName}-v``${VERSION}``${suffix}``);"
    )
    Set-Content -Path $cli -Value $text -Encoding UTF8
}

Write-Host "[4/4] 验证"
& flutter-skill --version
Write-Host "完成。用法示例：flutter-skill launch <flutter_app 目录>"
