#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Cursor Agent transcript parser — 提取会话元数据和消息
输出: JSON array of {stats, messages}
"""
import sys, json, os, re, hashlib, socket
sys.stdout.reconfigure(encoding='utf-8')
from datetime import datetime

def clean_text(text):
    if not text: return ''
    text = re.sub(r'<timestamp>[^<]*</timestamp>', '', text)
    text = re.sub(r'<user_query>[^<]*</user_query>', '', text)
    text = re.sub(r'<system_notification>.*?</system_notification>', '', text, flags=re.DOTALL)
    text = re.sub(r'<image_files>.*?</image_files>', '', text, flags=re.DOTALL)
    text = re.sub(r'\[Image\]', '[图片]', text)
    text = re.sub(r'These images can be copied.*', '', text, flags=re.DOTALL)
    return text.strip()

def extract_timestamp(text):
    m = re.search(r'<timestamp>(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2}:\d{2})', text)
    if m:
        try: return datetime.strptime(f"{m.group(1)} {m.group(2)}", '%Y-%m-%d %H:%M:%S')
        except: pass
    m = re.search(r'<timestamp>\w+day,?\s+(\w+)\s+(\d+),?\s+(\d+),?\s+(\d+):(\d+)\s*(AM|PM)', text, re.IGNORECASE)
    if m:
        try:
            months = {'Jan':1,'Feb':2,'Mar':3,'Apr':4,'May':5,'Jun':6,'Jul':7,'Aug':8,'Sep':9,'Oct':10,'Nov':11,'Dec':12}
            month=months.get(m.group(1)[:3],6); day=int(m.group(2)); year=int(m.group(3))
            hour=int(m.group(4)); minute=int(m.group(5)); ampm=m.group(6).upper()
            if ampm=='PM' and hour<12: hour+=12
            elif ampm=='AM' and hour==12: hour=0
            return datetime(year,month,day,hour,minute)
        except: pass
    return None

def extract_user_query(text):
    m = re.search(r'<user_query>(.*?)(?:</user_query>|$)', text, re.DOTALL)
    if m:
        raw = m.group(1).strip()
        raw = re.sub(r'<timestamp>[^<]*</timestamp>', '', raw, flags=re.DOTALL)
        raw = re.sub(r'<image_files>.*?</image_files>', '', raw, flags=re.DOTALL)
        raw = re.sub(r'\[Image\]', '', raw).strip()
        return raw[:500]
    return text[:500].strip()

def extract_file_refs(text):
    refs = set()
    for m in re.finditer(r'[A-Z]:[/\\][/\w. +-]+', text):
        p = m.group(0).replace('\\', '/')
        if p.startswith('E:/') or p.startswith('e:/') or p.startswith('C:/Users/HJ'):
            refs.add(p)
    return list(refs)[:20]

def parse_content(content):
    texts=[]; tool_name=None; has_images=False; file_refs=set()
    if not content: return '', 'mixed', None, False, []
    for item in content:
        t = item.get('type','')
        if t=='text':
            txt=item.get('text','')
            if txt:
                texts.append(txt)
                if '[Image]' in txt or 'image_files' in txt: has_images=True
                file_refs.update(extract_file_refs(txt))
        elif t=='tool_use':
            tool_name=item.get('name','')
    raw_text=clean_text('\n'.join(texts))[:5000]
    ctype='tool_use' if (tool_name and not texts) else 'text' if texts else 'mixed'
    return raw_text, ctype, tool_name, has_images, list(file_refs)

def process_session(session_uuid, session_dir, since_date):
    main_file = os.path.join(session_dir, session_uuid + '.jsonl')
    if not os.path.exists(main_file): return None

    hostname = socket.gethostname()
    username = os.environ.get('USERNAME', os.environ.get('USER', 'HJ2'))

    stats = dict(total_turns=0,total_user_turns=0,total_assistant_turns=0,
                 total_tool_calls=0,total_messages=0,total_size_bytes=0,
                 first_user_ts=None,last_user_ts=None,
                 first_user_query='',first_user_query_hash='',
                 session_title='',is_active=True,
                 machine_name=hostname,
                 username=username,
                 workspace='e:\\\\HJ\\\\cursor')

    try: stats['total_size_bytes']=os.path.getsize(main_file)
    except: pass

    subagent_dir = os.path.join(session_dir, 'subagents')
    if os.path.isdir(subagent_dir):
        stats['total_tool_calls']=len([f for f in os.listdir(subagent_dir) if f.endswith('.jsonl')])

    messages=[]; first_ts=None; last_ts=None
    try:
        with open(main_file, 'r', encoding='utf-8', errors='replace') as f:
            for turn_index, line in enumerate(f):
                try: obj=json.loads(line)
                except: continue
                role=obj.get('role','')
                if role not in ('user','assistant','system'): continue
                stats['total_messages']+=1; stats['total_turns']+=1
                if role=='user': stats['total_user_turns']+=1
                elif role=='assistant': stats['total_assistant_turns']+=1

                msg_content=obj.get('message',{}).get('content',[])
                raw_for_ts='\n'.join(item.get('text','') for item in msg_content if item.get('type')=='text')
                ts=extract_timestamp(raw_for_ts)
                raw_text,ctype,tool_name,has_images,file_refs=parse_content(msg_content)

                if ts:
                    if first_ts is None: first_ts=ts
                    last_ts=ts

                if role=='user' and not stats['first_user_query'] and raw_for_ts:
                    stats['first_user_query']=extract_user_query(raw_for_ts)
                    stats['first_user_ts']=ts
                    if stats['first_user_query']:
                        stats['first_user_query_hash']=hashlib.sha1(stats['first_user_query'].encode('utf-8')).hexdigest()

                if not stats['session_title'] and stats['first_user_query']:
                    stats['session_title']=stats['first_user_query'][:60].replace('\n',' ').strip()

                messages.append({
                    'turn_index': turn_index,
                    'role': role,
                    'content_type': ctype,
                    'raw_text': raw_text[:2000],
                    'tool_name': tool_name,
                    'has_images': has_images,
                    'has_file_refs': bool(file_refs),
                    'file_refs': file_refs,
                    'ts': ts.strftime('%Y-%m-%d %H:%M:%S') if ts else None
                })

        if messages and messages[-1]['role']=='assistant':
            stats['is_active']=False
    except Exception as e:
        print('ERROR: {}: {}'.format(main_file, e), file=sys.stderr)
        return None

    stats['first_user_ts']=first_ts.strftime('%Y-%m-%d %H:%M:%S') if first_ts else None
    stats['last_user_ts']=last_ts.strftime('%Y-%m-%d %H:%M:%S') if last_ts else None
    stats['session_uuid']=session_uuid

    if since_date and first_ts:
        try:
            since_dt = datetime.strptime(since_date, '%Y-%m-%d')
            if first_ts.date() < since_dt.date(): return None
        except: pass

    return {'stats': stats, 'messages': messages}

def walk(transcript_dir):
    results=[]
    if not os.path.isdir(transcript_dir): return results
    for uuid_dir in sorted(os.listdir(transcript_dir)):
        d=os.path.join(transcript_dir, uuid_dir)
        if not os.path.isdir(d): continue
        main_file=os.path.join(d, uuid_dir+'.jsonl')
        if os.path.exists(main_file): results.append((main_file, uuid_dir, d))
    return results

if __name__=='__main__':
    transcript_dir = sys.argv[1] if len(sys.argv) > 1 else os.environ.get(
        'TRANSCRIPT_DIR', r'C:\Users\HJ2\.cursor\projects\e-HJ-cursor\agent-transcripts')
    since_date = sys.argv[2] if len(sys.argv) > 2 else ''

    results = walk(transcript_dir)
    sessions = []
    for main_file, session_uuid, session_dir in results:
        data = process_session(session_uuid, session_dir, since_date)
        if data: sessions.append(data)
    json.dump(sessions, sys.stdout, ensure_ascii=False, default=str)
