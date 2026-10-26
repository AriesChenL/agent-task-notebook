#!/usr/bin/env python3
import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
binary = root / 'dist/Agent Notebook.app/Contents/MacOS/tasknote'
with tempfile.TemporaryDirectory(prefix='tasknote-smoke-') as directory:
    env = dict(os.environ, TASKNOTE_HOME=directory)
    def cli(*args):
        result = subprocess.run([str(binary), *args], env=env, capture_output=True, text=True, check=True)
        return json.loads(result.stdout)
    task = cli('add', '--title', '中文任务', '--directory', '/tmp/path with spaces', '--status', 'running')
    key = task['id']
    cli('session', 'add', key, '--tool', 'Codex', '--name', '实现会话')
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        list(pool.map(lambda n: cli('note', key, '--text', f'并发记录 {n}'), range(24)))
    task = cli('show', key)
    assert len(task['activities']) == 26
    assert len(task['sessions']) == 1
    assert task['directory'] == '/tmp/path with spaces'
    cli('update', key, '--status', 'waiting', '--next', '请验收')
    assert len(cli('list', '--status', 'waiting')) == 1
    assert not cli('list', '--status', 'done')
    cli('session', 'remove', key, '--id', task['sessions'][0]['id'])
    assert not cli('show', key)['sessions']
    for args in [('update', key, '--status', 'bogus'), ('add', '--title', ''), ('list', '--typo', 'x')]:
        result = subprocess.run([str(binary), *args], env=env, capture_output=True, text=True)
        assert result.returncode == 1 and result.stderr
    cli('update', key, '--tags', '后端,紧急，后端')
    assert cli('show', key)['tags'] == ['后端', '紧急']
    assert len(cli('list', '--tag', '紧急')) == 1
    assert not cli('list', '--tag', '不存在')
    cli('update', key, '--tags', '')
    assert cli('show', key)['tags'] == []
    cli('update', key, '--start', '2026-10-23T09:00:00+08:00', '--end', '2026-10-23T10:00:00+08:00')
    assert cli('show', key)['startAt'] == '2026-10-23T01:00:00Z'
    before = cli('show', key)
    result = subprocess.run([str(binary), 'update', key, '--end', '2026-10-22T10:00:00+08:00'], env=env, capture_output=True)
    assert result.returncode == 1 and cli('show', key) == before
    cli('update', key, '--start', '', '--end', '')
    assert cli('show', key).get('startAt') is None
    cli('update', key, '--status', 'cancelled')
    assert cli('show', key)['status'] == 'cancelled'
    assert len(cli('list', '--status', 'cancelled')) == 1
    cli('update', key, '--status', 'running')
    assert not cli('list', '--status', 'cancelled')
    print('CLI smoke passed: CRUD, sessions, JSON, validation, 24 cross-process concurrent updates')
