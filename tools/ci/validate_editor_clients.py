# SPDX-License-Identifier: MIT
"""Parse all generated client settings, including DeepSeek Harness' YAML loader."""
from pathlib import Path
import argparse
import json
import tomllib
import yaml


def validate(directory):
    directory=Path(directory)
    report=json.loads((directory/'result.json').read_text(encoding='utf-8'))
    assert report['passed'] and len(report['cases'])==26
    launch=report['launch'];ids=[]
    for case in report['cases']:
        text=(directory/case['file']).read_text(encoding='utf-8')
        document=tomllib.loads(text)if case['format']=='toml'else yaml.safe_load(text)if case['format']=='yaml'else json.loads(text)
        key=case['id'];ids.append(key)
        if key=='deepseek_harness':
            plugin=document[0]['insert'][0]
            assert plugin['name']=='@deepseek-ai/dsh-mcp-client'
            entry=plugin['config']
            assert entry['serverName']=='ft2' and entry['transport']=='stdio'
        elif key in ('codex','grok','hermes'):entry=document['mcp_servers']['ft2']
        elif key in ('vscode','vscode_insiders'):entry=document['servers']['ft2']
        elif key=='zed':entry=document['context_servers']['ft2']
        elif key=='zcode':entry=document['mcp']['servers']['ft2']
        elif key=='opencode':
            entry=document['mcp']['ft2']
            assert entry['command']==[launch['command'],*launch['args']]
            continue
        else:entry=document['mcpServers']['ft2']
        assert entry['command']==launch['command'] and entry['args']==launch['args'],key
    assert len(set(ids))==26 and 'deepseek_harness'in ids
    v2=json.loads((directory/'opencode_v2.json').read_text(encoding='utf-8'))['mcp']['servers']['ft2']
    assert v2['protocol']=='legacy' and 'enabled'not in v2
    result={'passed':True,'clients':26,'generated_settings':27,'deepseek_harness_verified':True,'checks':report['checks']}
    (directory/'parsed-settings.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    return result


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--directory',type=Path,required=True)
    print(json.dumps(validate(parser.parse_args().directory)))
