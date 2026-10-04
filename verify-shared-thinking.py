"""Functional checks against the already-running, authenticated local Splash."""
import json, urllib.request
from pathlib import Path
root=Path.home(); key=json.loads((root/'.omlx/settings.json').read_text())['auth']['api_key']
def request(path,body=None):
 req=urllib.request.Request('http://127.0.0.1:8000'+path,data=None if body is None else json.dumps(body).encode(),headers={'Authorization':'Bearer '+key,'Content-Type':'application/json'})
 return urllib.request.urlopen(req,timeout=120)
with request('/v1/models') as r: models=[m['id'] for m in json.load(r)['data']]
assert 'qwen-uncensored-splash-no-thinking' in models
assert 'qwen-uncensored-splash-thinking' in models
print('Model aliases visible:', models,flush=True)
for model,effort,expect in [('qwen-uncensored-splash',None,False),('qwen-uncensored-splash-no-thinking','xhigh',False),('qwen-uncensored-splash-thinking','none',True)]:
 body={'model':model,'messages':[{'role':'user','content':'What is 2+3? Reply briefly.'}],'max_tokens':160,'stream':True,'stream_options':{'include_usage':True}}
 if effort is not None:body['reasoning_effort']=effort
 usage=None;content='';reason=''
 with request('/v1/chat/completions',body) as r:
  for line in r:
   if not line.startswith(b'data:'): continue
   data=line[5:].strip()
   if data==b'[DONE]':break
   event=json.loads(data)
   assert 'error' not in event,event
   if event.get('usage'):usage=event['usage']
   choices=event.get('choices',[])
   if choices:
    delta=choices[0].get('delta',{});content+=delta.get('content') or '';reason+=delta.get('reasoning_content') or ''
 assert usage, 'missing usage'
 tokens=usage['completion_tokens_details']['reasoning_tokens']
 assert (tokens>0)==expect,(model,usage)
 assert content.strip(),(model,'no final answer')
 print(json.dumps({'model':model,'requested_effort':effort,'reasoning_tokens':tokens,'answer':content},ensure_ascii=False),flush=True)
with request('/v1/responses',{'model':'qwen-uncensored-splash-no-thinking','input':'Reply with the word ready.','reasoning':{'effort':'high'},'max_output_tokens':64}) as r:
 result=json.load(r)
 assert result['usage']['output_tokens_details']['reasoning_tokens']==0,result.get('usage')
 print('Responses API fixed-off passed:',result['usage'],flush=True)
