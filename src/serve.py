#!/usr/bin/env python3
"""Serve the site (public/) to the home network, to look at it before it goes on the web. Usage: python src/serve.py [--port 8801] [--local] [--root DIR]
Anyone on the same Wi-Fi can open the printed address. --local listens on this computer only.
Build it first with make site."""
import argparse,functools,http.server,os,socket
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__))); SITE=os.path.join(ROOT,'public')
class Server(http.server.ThreadingHTTPServer):
    request_queue_size=128   # a browser opens many connections at once; the default of 5 drops some
    daemon_threads=True
class Handler(http.server.SimpleHTTPRequestHandler):
    protocol_version='HTTP/1.1'
    extensions_map={**http.server.SimpleHTTPRequestHandler.extensions_map,'.json':'application/json','.svg':'image/svg+xml','.woff2':'font/woff2','.js':'text/javascript'}
    def end_headers(s):
        s.send_header('Cache-Control','no-cache'); super().end_headers()
    def log_message(s,*a): pass
def lan_ip():
    try:
        x=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); x.connect(('10.255.255.255',1)); ip=x.getsockname()[0]; x.close(); return ip
    except OSError: return None
if __name__=='__main__':
    ap=argparse.ArgumentParser(); ap.add_argument('--port',type=int,default=8801); ap.add_argument('--local',action='store_true'); ap.add_argument('--root',default=SITE); a=ap.parse_args()
    SITE=os.path.abspath(a.root)
    if not os.path.exists(os.path.join(SITE,'index.html')): raise SystemExit('No site yet. Run: make site')
    host='127.0.0.1' if a.local else '0.0.0.0'
    srv=Server((host,a.port),functools.partial(Handler,directory=SITE))
    print(f'Appellation Atlas is open at http://localhost:{a.port}/'+('' if a.local or not lan_ip() else f' and, on the home Wi-Fi, http://{lan_ip()}:{a.port}/'),flush=True)
    srv.serve_forever()
