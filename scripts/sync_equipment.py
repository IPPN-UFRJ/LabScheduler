#!/usr/bin/env python3
"""Synchronize GitHub catalog into Supabase via service-role REST. No extra dependencies."""
import json, os, urllib.request, urllib.error
from pathlib import Path
config=json.loads(Path('config/equipment.json').read_text(encoding='utf-8'))
items=config['equipment'];codes=[i['code'] for i in items]
assert len(codes)==len(set(codes)), 'Duplicate codes'
assert len(items)>0
url=os.environ['SUPABASE_URL'].rstrip('/')
key=os.environ['SUPABASE_SERVICE_ROLE_KEY']
inst=os.environ['LABSCHEDULER_INSTITUTION_ID']
headers={'apikey':key,'Authorization':'Bearer '+key,'Content-Type':'application/json','Prefer':'resolution=merge-duplicates,return=minimal'}
for e in items:
 assert isinstance(e['bookable'],bool) and e['kind'] in ('instrument','accessory')
 assert e['operational_status'] in ('operational','maintenance','unavailable','retired')
 assert isinstance(e['notice'],dict) and all(isinstance(e['notice'].get(k,''),str) for k in ('pt','en','es'))
 assert e['kind']!='accessory' or not e['bookable'], 'Accessory cannot be bookable'
for e in items:
 payload={'institution_id':inst,'code':e['code'],'name':e['name'],'lab':e['lab'],'manufacturer':e['manufacturer'],'model':e['model'],'kind':e['kind'],'operational_status':e['operational_status'],'active':e['bookable'],'notice':e['notice'],'pnipe_url':e['pnipe_url'],'depends_on':e['depends_on']}
 request=urllib.request.Request(url+'/rest/v1/equipment?on_conflict=institution_id,code',data=json.dumps(payload,ensure_ascii=False).encode(),headers=headers,method='POST')
 try:
  with urllib.request.urlopen(request,timeout=25) as response: assert response.status in (200,201,204)
 except urllib.error.HTTPError as err: raise RuntimeError(f'Could not sync {e["code"]}: HTTP {err.code} {err.read().decode()[:400]}') from err
print(f'Synchronized {len(items)} equipment records')
