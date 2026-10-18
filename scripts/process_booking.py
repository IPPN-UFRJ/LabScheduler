"""GitHub Issues booking processor. Never trusts claimed identity in issue body."""
import json, os, re, subprocess, sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
REPO = os.environ.get('REPO', '')
TOKEN = os.environ.get('GH_TOKEN', '')
NUMBER = os.environ.get('ISSUE_NUMBER', '')

def api(method, path, payload=None):
    body = None if payload is None else json.dumps(payload).encode()
    req = Request('https://api.github.com/repos/'+REPO+'/'+path, data=body, method=method,
                  headers={'Authorization':'Bearer '+TOKEN,'Accept':'application/vnd.github+json','User-Agent':'LabScheduler-Actions','Content-Type':'application/json'})
    with urlopen(req, timeout=25) as res:
        return json.loads(res.read().decode() or '{}')

def run(*args):
    subprocess.run(args, check=True, cwd=ROOT)

def comment(issue, message):
    api('POST', f'issues/{issue}/comments', {'body':message})

def handle(issue):
    item = api('GET', f'issues/{issue}')
    author = item['user']['login'].lower()
    title = item['title']
    if not title.startswith('[LabScheduler Booking]'):
        return
    body = item.get('body') or ''
    # Exactly one JSON block; no code execution or untrusted script evaluation.
    match = re.fullmatch(r'\s*```json\s*(\{.*?\})\s*```\s*', body, re.DOTALL)
    if not match:
        raise ValueError('Invalid booking request format. Use the button on the LabScheduler website.')
    request = json.loads(match.group(1))
    if set(request) != {'equipment_code','project_id','start_at','end_at'}:
        raise ValueError('Unexpected booking fields.')
    code, project = request['equipment_code'], request['project_id']
    users = json.loads((ROOT/'config/users.json').read_text())['users']
    user = next((u for u in users if u['github_login'].lower() == author and u['active']), None)
    if not user:
        raise ValueError('Your GitHub account is not active in config/users.json.')
    equip = next((e for e in json.loads((ROOT/'config/equipment.json').read_text())['equipment'] if e['code']==code), None)
    if not equip or not equip['bookable'] or equip['operational_status']!='operational' or equip['kind']=='accessory':
        raise ValueError('Equipment is not bookable.')
    if '*' not in user['authorized_equipment'] and code not in user['authorized_equipment']:
        raise ValueError('You are not authorized for this instrument.')
    proj = next((p for p in json.loads((ROOT/'config/projects.json').read_text())['projects'] if p['id']==project and p['active']), None)
    if not proj or (project not in user['authorized_projects'] and '*' not in user['authorized_projects']):
        raise ValueError('You are not authorized for this project.')
    def parse(value):
        if not isinstance(value,str) or not re.fullmatch(r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:Z|[+-]\d\d:\d\d)',value):
            raise ValueError('Date must be ISO 8601 with timezone.')
        return datetime.fromisoformat(value.replace('Z','+00:00')).astimezone(timezone.utc)
    start,end=parse(request['start_at']),parse(request['end_at'])
    if start < datetime.now(timezone.utc): raise ValueError('Start time must be in the future.')
    if not 0 < (end-start).total_seconds() <= 12*3600: raise ValueError('Duration must be between 1 minute and 12 hours.')
    state_path=ROOT/'data/reservations.json'
    state=json.loads(state_path.read_text())
    if any(r['issue_number']==int(issue) for r in state['reservations']):
        comment(issue,'This request has already been processed.')
        return
    for r in state['reservations']:
        if r['equipment_code']==code and r['status']=='confirmed':
            rs=parse(r['start_at']);re=parse(r['end_at'])
            if start < re and rs < end: raise ValueError('Time slot conflicts with an existing booking.')
    # Public state deliberately excludes username, project, financial and scientific metadata.
    state['reservations'].append({'id':f'LS-{issue}','issue_number':int(issue),'equipment_code':code,'start_at':start.isoformat().replace('+00:00','Z'),'end_at':end.isoformat().replace('+00:00','Z'),'status':'confirmed'})
    state_path.write_text(json.dumps(state,ensure_ascii=False,indent=2)+'\n')
    run('git','config','user.name','github-actions[bot]')
    run('git','config','user.email','41898282+github-actions[bot]@users.noreply.github.com')
    run('git','add','data/reservations.json')
    run('git','commit','-m',f'Booking {issue}: {code}')
    run('git','push','origin','HEAD:main')
    comment(issue,f'✅ Reservation **LS-{issue}** confirmed for equipment `{code}`. Calendar will update after the Pages deployment.')
    api('PATCH',f'issues/{issue}',{'state':'closed'})

def main():
    if os.environ.get('EVENT_NAME')=='workflow_dispatch':
        print('Manual trigger: no issue to process')
        return
    try:
        handle(NUMBER)
    except Exception as exc:
        msg=str(exc)
        print('Booking rejected:',msg,file=sys.stderr)
        if NUMBER:
            comment(NUMBER,'❌ Booking not accepted: '+msg.replace('`',''))
            api('PATCH',f'issues/{NUMBER}',{'state':'closed'})
        sys.exit(1)

if __name__=='__main__': main()
