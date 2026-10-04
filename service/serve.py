import json,os
from pathlib import Path
root=Path.home()
os.environ['SPLASH_API_KEY']=json.loads((root/'.omlx/settings.json').read_text())['auth']['api_key']
os.environ['NO_PROXY']='localhost,127.0.0.1'
runtime=root/'.local/lib/splash-1.1.0'
bundle=Path((root/'.local/share/splash-qwen/vision-bundle.txt').read_text().strip())
args=[str(runtime/'python/bin/python3'),'-u',str(runtime/'server/server.py'),str(bundle/'target'),str(bundle/'draft'),'--tokenizer',str(bundle/'tokenizer'),'--model','JonathanColetti/Qwen3.8-27B-Uncensored-GGUF:Q8_0','--binary',str(runtime/'engine/splash'),'--host','127.0.0.1','--port','8000','--max-memory',str(36*1024**3),'--max-context',str(128*1024),'--max-cache-disk',str(8*1024**3),'--default-reasoning-effort','none','--served-model-name','qwen-uncensored-splash']
# Splash Local app preferences; defaults above remain valid without the app.
prefs_path = root/'Library/Application Support/Splash Local/preferences.json'
os.environ['SPLASH_LOCAL_POLICY_CONFIG'] = str(prefs_path)
args.extend(['--served-model-name','qwen-uncensored-splash-no-thinking','--served-model-name','qwen-uncensored-splash-thinking'])
if prefs_path.exists():
 prefs = json.loads(prefs_path.read_text())
 for field, flag, lo, hi, suffix in [('memoryGB','--max-memory',30,48,'G'),('contextK','--max-context',4,256,'K'),('cacheGB','--max-cache-disk',0,64,'G')]:
  value = prefs.get(field)
  if isinstance(value,(int,float)) and not isinstance(value,bool) and lo <= value <= hi and int(value) == value:
   args[args.index(flag)+1] = str(int(value)*(1024 if field == 'contextK' else 1024**3))
 kv = prefs.get('kvFormat','int8')
 if kv in ('int8','bf16'): args.extend(['--kv-format',kv])
os.execv(args[0],args)
