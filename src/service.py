#!/usr/bin/env python3
"""Run the app as a Mac background service (a launchd agent), so it starts at login and restarts if it stops.
  service.py install     write ~/Library/LaunchAgents/com.poursheets.appellation-atlas.plist and start it
  service.py uninstall   stop it and remove the file
  service.py status      whether it is running, and the end of its log
It serves public/ on port 8801 at home. The log is ~/Library/Logs/appellation-atlas.log."""
import os,plistlib,subprocess,sys
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LABEL='com.poursheets.appellation-atlas'
PLIST=os.path.expanduser(f'~/Library/LaunchAgents/{LABEL}.plist'); LOG=os.path.expanduser('~/Library/Logs/appellation-atlas.log')
DOMAIN=f'gui/{os.getuid()}'
def sh(*a): return subprocess.run(a,capture_output=True,text=True)
def install():
    py=os.path.join(ROOT,'.venv','bin','python')
    spec=dict(Label=LABEL,ProgramArguments=[py,os.path.join(ROOT,'src','serve.py'),'--port','8801'],WorkingDirectory=ROOT,
              RunAtLoad=True,KeepAlive=True,ThrottleInterval=10,StandardOutPath=LOG,StandardErrorPath=LOG,
              EnvironmentVariables=dict(PYTHONUNBUFFERED='1'))
    os.makedirs(os.path.dirname(PLIST),exist_ok=True)
    if os.path.exists(PLIST): sh('launchctl','bootout',DOMAIN,PLIST)
    plistlib.dump(spec,open(PLIST,'wb'))
    r=sh('launchctl','bootstrap',DOMAIN,PLIST)
    if r.returncode: sys.exit(f'launchctl bootstrap failed: {r.stderr.strip()}')
    print('Installed and started',LABEL)
def uninstall():
    if os.path.exists(PLIST): sh('launchctl','bootout',DOMAIN,PLIST); os.remove(PLIST); print('Stopped and removed',LABEL)
    else: print('Not installed.')
def status():
    r=sh('launchctl','print',f'{DOMAIN}/{LABEL}')
    if r.returncode: print('Not running (not loaded).')
    else:
        keep=[l.strip() for l in r.stdout.splitlines() if l.strip().split(' =')[0] in ('state','pid','last exit code','runs')]
        print('\n'.join(keep))
    if os.path.exists(LOG): print('--- log ---'); print(''.join(open(LOG,errors='replace').readlines()[-8:]),end='')
if __name__=='__main__':
    {'install':install,'uninstall':uninstall,'status':status}.get(sys.argv[1] if len(sys.argv)>1 else '',lambda:sys.exit(__doc__))()
