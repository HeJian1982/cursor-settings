# Copyright (c) 2026 HeJian. All rights reserved.
# Cursor Model Detective - mitmproxy 抓包脚本
# 用于分析 Cursor IDE 的 AI 模型调用

"""
使用方式:
1. 安装 mitmproxy: pip install mitmproxy
2. 运行: mitmproxy -s cursor_model_detective.py --listen-port 8080
3. 在 Cursor 设置中配置 HTTP 代理: 127.0.0.1:8080
4. 在 Cursor 中进行 AI 对话，观察终端输出

或者使用 mitmdump (无界面版本):
mitmdump -s cursor_model_detective.py --listen-port 8080
"""

import json
import re
from datetime import datetime
from urllib.parse import parse_qs, urlparse

from mitmproxy import http, ctx


class CursorModelDetector:
    """检测 Cursor 的 AI 模型调用"""

    def __init__(self):
        self.model_calls = []
        self.suspicious_hosts = set()
        self.start_time = datetime.now()

        # 已知的 AI API 域名模式
        self.ai_host_patterns = [
            r'api\.anthropic\.com',
            r'api\.openai\.com',
            r'api\.azure\.com',
            r'api\.cohere\.ai',
            r'api\.mistral\.ai',
            r'api\.googleapis\.com',
            r'cursor\.sh',
            r'cursor\.com',
            r'.*\.anthropic\.com',
            r'.*\.openai\.com',
            r'.*\.azure\.com',
            r'.*\.cohere\.ai',
        ]

    def is_ai_request(self, host: str) -> bool:
        """检查是否可能是 AI API 请求"""
        for pattern in self.ai_host_patterns:
            if re.match(pattern.replace('.', r'\.').replace('*', '.*'), host, re.IGNORECASE):
                return True
        return False

    def extract_model_info(self, content: bytes, content_type: str) -> dict:
        """从请求/响应中提取模型信息"""
        info = {}

        if not content:
            return info

        try:
            # 尝试解析 JSON
            if 'json' in content_type.lower() or content.startswith(b'{'):
                data = json.loads(content.decode('utf-8', errors='ignore'))

                # Anthropic 格式
                if 'model' in data:
                    info['model'] = data['model']

                # OpenAI 格式
                if 'model' in data:
                    info['model'] = data['model']

                # 检查 stream 选项
                if 'stream' in data:
                    info['stream'] = data['stream']

                # 检查 messages
                if 'messages' in data:
                    info['message_count'] = len(data['messages'])
                    # 检查是否有 system prompt
                    for msg in data['messages']:
                        if msg.get('role') == 'system':
                            info['has_system_prompt'] = True
                            if len(msg.get('content', '')) > 100:
                                info['system_prompt_length'] = len(str(msg['content']))

                # 检查 max_tokens
                if 'max_tokens' in data:
                    info['max_tokens'] = data['max_tokens']

            # 尝试从原始文本中提取模型信息
            text = content.decode('utf-8', errors='ignore')

            # 常见的模型名称模式
            model_patterns = [
                r'"model"\s*:\s*"([^"]+)"',
                r'model["\']?\s*:\s*["\']?([a-zA-Z0-9\-_.]+)',
                r'claude[-]([a-zA-Z0-9\-]+)',
                r'gpt[-]([0-9.]+)',
                r'claude-[0-9]-[a-zA-Z0-9\-]+',
                r'claude-sonnet-[0-9]+',
                r'claude-opus-[0-9]+',
                r'claude-haiku-[0-9]+',
            ]

            for pattern in model_patterns:
                match = re.search(pattern, text, re.IGNORECASE)
                if match:
                    potential_model = match.group(0) if 'model' in pattern else match.group(1)
                    # 过滤掉明显不是模型名的结果
                    if potential_model and not potential_model.startswith('model'):
                        info['potential_model'] = potential_model

        except (json.JSONDecodeError, UnicodeDecodeError):
            pass

        return info

    def response_to_model_info(self, content: bytes) -> dict:
        """从响应中提取模型信息"""
        info = {}

        if not content:
            return info

        try:
            text = content.decode('utf-8', errors='ignore')

            # Anthropic 响应格式
            if 'anthropic' in text.lower():
                # 查找 model 字段
                model_match = re.search(r'"model"\s*:\s*"([^"]+)"', text)
                if model_match:
                    info['model'] = model_match.group(1)

                # 查找 usage 信息
                usage_match = re.search(r'"usage"\s*:\s*\{([^}]+)\}', text)
                if usage_match:
                    info['usage'] = usage_match.group(0)

            # X-Headers (Anthropic 使用)
            # 这些信息通常在响应头中

        except (UnicodeDecodeError, AttributeError):
            pass

        return info

    def request(self, flow: http.HTTPFlow):
        """处理出站请求"""
        host = flow.request.pretty_host
        method = flow.request.method
        path = flow.request.path
        content = flow.request.content or b''

        # 记录可疑的 AI 请求
        if self.is_ai_request(host):
            timestamp = datetime.now().strftime('%H:%M:%S.%f')[:-3]

            info = {
                'timestamp': timestamp,
                'host': host,
                'method': method,
                'path': path,
                'type': 'request'
            }

            # 提取请求体中的模型信息
            content_type = flow.request.headers.get('content-type', '')
            model_info = self.extract_model_info(content, content_type)
            info.update(model_info)

            # 记录特定 header
            if 'x-api-key' in flow.request.headers:
                info['has_api_key'] = True
            if 'anthropic-version' in flow.request.headers:
                info['anthropic_version'] = flow.request.headers['anthropic-version']

            self.model_calls.append(info)
            self.suspicious_hosts.add(host)

            # 打印关键发现
            if model_info.get('model'):
                ctx.log.info(f"[CURSOR MODEL] {timestamp} {method} {host} -> Model: {model_info['model']}")
            else:
                ctx.log.info(f"[CURSOR API] {timestamp} {method} {host}{path}")

    def response(self, flow: http.HTTPFlow):
        """处理入站响应"""
        host = flow.request.pretty_host
        content = flow.response.content or b''
        status = flow.response.status_code

        if self.is_ai_request(host):
            timestamp = datetime.now().strftime('%H:%M:%S.%f')[:-3]

            # 从响应中提取模型信息
            model_info = self.response_to_model_info(content)

            if model_info.get('model'):
                ctx.log.info(f"[MODEL CONFIRMED] {timestamp} {host} -> {model_info['model']}")

            # 检查响应头中的模型信息
            for header_name, header_value in flow.response.headers.items():
                if 'model' in header_name.lower():
                    ctx.log.info(f"[HEADER MODEL] {header_name}: {header_value}")

            # Anthropic 特有的响应头
            if 'x-api-key' not in [h.lower() for h in flow.request.headers.keys()]:
                anthropic_headers = [h for h in flow.response.headers.keys()
                                   if h.lower().startswith('anthropic')]
                for h in anthropic_headers:
                    ctx.log.debug(f"[ANTHROPIC HEADER] {h}: {flow.response.headers[h]}")

    def done(self):
        """抓包结束时调用"""
        print("\n" + "=" * 60)
        print("🎯 CURSOR MODEL DETECTIVE - 分析报告")
        print("=" * 60)

        # 统计
        print(f"\n📊 统计:")
        print(f"   - 总 AI API 请求: {len(self.model_calls)}")
        print(f"   - 涉及的 API 域名: {len(self.suspicious_hosts)}")

        if self.suspicious_hosts:
            print(f"\n🌐 检测到的 AI API 域名:")
            for host in sorted(self.suspicious_hosts):
                print(f"   • {host}")

        # 提取确认的模型
        confirmed_models = set()
        for call in self.model_calls:
            if call.get('model'):
                confirmed_models.add(call['model'])

        if confirmed_models:
            print(f"\n🤖 确认使用的模型:")
            for model in sorted(confirmed_models):
                print(f"   • {model}")

        # 显示详细请求记录
        if self.model_calls:
            print(f"\n📋 详细请求记录:")
            for call in self.model_calls[:20]:  # 最多显示 20 条
                model_str = f" [模型: {call.get('model', '未知')}]" if call.get('model') else ""
                tokens_str = f" [max_tokens: {call.get('max_tokens', '未设置')}]" if call.get('max_tokens') else ""
                print(f"   {call['timestamp']} {call['method']} {call['host']}{call['path']}{model_str}{tokens_str}")

        print("\n" + "=" * 60)


# 创建插件实例
addons = [CursorModelDetector()]
