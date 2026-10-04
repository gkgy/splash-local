import json,os,subprocess,time,urllib.request
from pathlib import Path
root=Path.home()
key=json.loads((root/'.omlx/settings.json').read_text())['auth']['api_key']
def ready():
 try:
  req=urllib.request.Request('http://127.0.0.1:8000/v1/models',headers={'Authorization':'Bearer '+key})
  with urllib.request.urlopen(req,timeout=3) as r:return bool(json.load(r).get('data'))
 except Exception:return False
if ready():raise SystemExit(0)
service=f'gui/{os.getuid()}/local.splash.qwen-uncensored'
p=subprocess.run(['launchctl','print',service],capture_output=True,text=True)
if p.returncode:subprocess.run(['launchctl','bootstrap',f'gui/{os.getuid()}',str(root/'Library/LaunchAgents/local.splash.qwen-uncensored.plist')],check=True)
subprocess.run(['launchctl','kickstart',service],check=True)
print('正在启动 Splash 本地 Qwen…',flush=True)
for _ in range(600):
 if ready():raise SystemExit(0)
 time.sleep(1)
raise SystemExit('启动未完成，请检查 ~/.local/share/splash-qwen/server.log')
