# Copyright (c) 2026 HeJian. All rights reserved.
# 安装抓包工具依赖

# 需要 Python 3.8+

Write-Host "🔧 安装 mitmproxy..." -ForegroundColor Cyan

# 安装 mitmproxy (包含 mitmdump)
pip install mitmproxy

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n✅ mitmproxy 安装成功!" -ForegroundColor Green

    Write-Host "`n📝 使用步骤:" -ForegroundColor Yellow
    Write-Host "1. 运行抓包脚本:"
    Write-Host "   mitmdump -s `"$PSScriptRoot\cursor_model_detective.py`" --listen-port 8080"
    Write-Host ""
    Write-Host "2. 在 Cursor 中配置代理:"
    Write-Host "   - 打开 Cursor 设置"
    Write-Host "   - 搜索 'proxy' 或 '代理'"
    Write-Host "   - 设置 HTTP 代理: 127.0.0.1:8080"
    Write-Host ""
    Write-Host "3. 在 Cursor 中进行 AI 对话"
    Write-Host ""
    Write-Host "4. 观察终端输出，查看检测到的模型信息"
    Write-Host ""
    Write-Host "5. 完成后按 Ctrl+C 停止 mitmdump"
    Write-Host "   并在 Cursor 中取消代理设置"
} else {
    Write-Host "`n❌ mitmproxy 安装失败" -ForegroundColor Red
    Write-Host "请尝试手动安装: pip install mitmproxy" -ForegroundColor Yellow
}
