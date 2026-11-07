# 构建 Flutter Windows（Phase 0 验证用）
# 关键点：
# 1) Windows 插件需要「开发人员模式」（symlink）
# 2) Flutter 3.47.9 的 windows 模板不会自动设置 CMAKE_INSTALL_PREFIX，
#    这里显式指向 runner/<Config>，否则 INSTALL 会尝试写 C:\Program Files
# 3) media_kit 首次构建会下载 mpv/ANGLE 7z；网络抖动时脚本预下载并校验 MD5
param(
    [ValidateSet("Debug", "Release", "Profile")]
    [string]$Config = "Debug"
)
$ErrorActionPreference = "Stop"
$env:HTTPS_PROXY = ""
$env:HTTP_PROXY = ""
$env:PATH = "E:\App\flutter\bin;$env:PATH"

$root = Split-Path -Parent $PSScriptRoot
$app = Join-Path $root "flutter_app"
$prefix = (Join-Path $app "build\windows\x64\runner\$Config").Replace("\", "/")
$env:CMAKE_INSTALL_PREFIX = $prefix

$cache = Join-Path $app "build\windows\x64"
New-Item -ItemType Directory -Force -Path $cache | Out-Null

$archives = @(
    @{
        Name = "mpv-dev-x86_64-20230924-git-652a1dd.7z"
        Url  = "https://github.com/media-kit/libmpv-win32-video-build/releases/download/2023-09-24/mpv-dev-x86_64-20230924-git-652a1dd.7z"
        Md5  = "a832ef24b3a6ff97cd2560b5b9d04cd8"
    },
    @{
        Name = "ANGLE.7z"
        Url  = "https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/download/v1.0.1/ANGLE.7z"
        Md5  = "e866f13e8d552348058afaafe869b1ed"
    }
)

foreach ($item in $archives) {
    $target = Join-Path $cache $item.Name
    $ok = (Test-Path $target) -and ((Get-FileHash $target -Algorithm MD5).Hash.ToLower() -eq $item.Md5)
    if (-not $ok) {
        Write-Host "下载 $($item.Name) ..."
        Remove-Item $target -ErrorAction SilentlyContinue
        curl.exe -L --fail --retry 3 -o $target $item.Url
        $hash = (Get-FileHash $target -Algorithm MD5).Hash.ToLower()
        if ($hash -ne $item.Md5) { throw "$($item.Name) MD5 校验失败: $hash" }
    }
}

Push-Location $app
try {
    & E:\App\flutter\bin\flutter.bat build windows --$($Config.ToLower())
} finally {
    Pop-Location
}
