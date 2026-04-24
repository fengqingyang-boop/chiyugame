@echo off
setlocal enabledelayedexpansion
:: 设置字符集为 UTF-8，防止中文乱码
chcp 65001 >nul

:: 获取传入的参数：参数1为SessionID，参数2为轮次，参数3为PR描述（可选）
set SESSION_ID=%~1
set ROUND=%~2
set PR_DESC=%~3

:: 检查参数是否完整
if "%SESSION_ID%"=="" (
    echo [错误] 请提供 Session ID。
    echo 用法示例: submit_pr.bat "your-session-id-123" 2 "修复了登录页面的bug"
    exit /b 1
)
if "%ROUND%"=="" (
    echo [错误] 请提供当前轮次。
    echo 用法示例: submit_pr.bat "your-session-id-123" 2 "修复了登录页面的bug"
    exit /b 1
)

:: 如果没有提供描述，则使用默认描述
if "%PR_DESC%"=="" (
    set PR_DESC=Feedback for round %ROUND%
)

:: 尝试获取当前所在的主分支名称 (自动识别是 master 还是 main)
for /f "delims=" %%i in ('git rev-parse --abbrev-ref HEAD') do set MAIN_BRANCH=%%i

if "%MAIN_BRANCH%"=="" (
    echo [错误] 无法获取当前分支，请确认当前目录是一个 Git 仓库。
    exit /b 1
)

set NEW_BRANCH=round-%ROUND%

echo ==================================================
echo 🚀 开始处理第 %ROUND% 轮自动化提交流程
echo Session ID: %SESSION_ID%
echo 主分支: %MAIN_BRANCH%
echo 新分支: %NEW_BRANCH%
echo PR描述: %PR_DESC%
echo ==================================================
echo.

echo [1/6] 创建并切换到新分支 %NEW_BRANCH%...
git checkout -b %NEW_BRANCH%
if %errorlevel% neq 0 (
    echo [提示] 尝试直接切换到已存在的分支 %NEW_BRANCH%...
    git checkout %NEW_BRANCH%
    if !errorlevel! neq 0 (
        echo [错误] 分支操作失败，请手动检查。
        exit /b 1
    )
)
echo.

echo [2/6] 暂存并提交代码...
git add .
git commit -m "Auto commit for round %ROUND%"
:: 如果没有代码变动，commit 会报错但无需退出，可以直接继续
echo.

echo [3/6] 推送到远程仓库...
set MAX_RETRIES=3
set RETRY_COUNT=0
:RETRY_PUSH
git push -u origin %NEW_BRANCH%
if %errorlevel% neq 0 (
    set /a RETRY_COUNT+=1
    if !RETRY_COUNT! lss %MAX_RETRIES% (
        echo [警告] 推送失败，网络可能不稳定。正在进行第 !RETRY_COUNT! 次重试...
        timeout /t 3 >nul
        goto RETRY_PUSH
    ) else (
        echo [错误] 达到最大重试次数，推送失败。请检查网络连接后手动重试。
        exit /b 1
    )
)
echo.

echo [4/6] 调用 GitHub CLI 创建 PR...
set RETRY_COUNT=0
:RETRY_PR
set PR_URL=
:: 创建 PR 并将返回的 PR 链接保存到变量 PR_URL 中
for /f "delims=" %%i in ('gh pr create --title "%SESSION_ID%" --body "%PR_DESC%" --base %MAIN_BRANCH% --head %NEW_BRANCH% 2^>^&1') do (
    set PR_URL=%%i
    echo %%i | findstr /i "http" >nul
    if !errorlevel! equ 0 (
        set PR_URL=%%i
    )
)

echo !PR_URL! | findstr /i "http" >nul
if !errorlevel! neq 0 (
    set /a RETRY_COUNT+=1
    if !RETRY_COUNT! lss %MAX_RETRIES% (
        echo [警告] 创建 PR 失败，网络可能不稳定。正在进行第 !RETRY_COUNT! 次重试...
        timeout /t 3 >nul
        goto RETRY_PR
    ) else (
        echo [错误] 达到最大重试次数，创建 PR 失败。GitHub CLI 输出: !PR_URL!
        exit /b 1
    )
)
echo ✅ PR 创建成功: !PR_URL!
echo.

echo [5/6] 自动合并 PR 到 %MAIN_BRANCH%...
set RETRY_COUNT=0
:RETRY_MERGE
gh pr merge !PR_URL! --merge
if %errorlevel% neq 0 (
    set /a RETRY_COUNT+=1
    if !RETRY_COUNT! lss %MAX_RETRIES% (
        echo [警告] 合并 PR 失败，网络可能不稳定。正在进行第 !RETRY_COUNT! 次重试...
        timeout /t 3 >nul
        goto RETRY_MERGE
    ) else (
        echo [错误] 达到最大重试次数，合并 PR 失败。
        echo [提示] 你的 PR 已经创建成功，链接是: !PR_URL!
        echo [提示] 请尝试在浏览器中打开上面的链接手动合并。
        exit /b 1
    )
)
echo ✅ PR 合并成功！
echo.

echo [6/6] 切回 %MAIN_BRANCH% 分支并拉取最新代码...
git checkout %MAIN_BRANCH%
git pull origin %MAIN_BRANCH%
echo.

echo ==================================================
echo 🎉 全部完成！请将以下信息发给甲方：
echo.
echo 【PR 链接】: !PR_URL!
echo 【PR 描述】: %PR_DESC%
echo ==================================================
