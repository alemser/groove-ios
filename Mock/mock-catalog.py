"""
mock-catalog.py — a zero-dependency fake groove-catalog server for previewing
the Groove iOS app without a real backend.

Serves canned tracks, plays, releases, enrich jobs, pending associations, status,
and generated cover art on http://127.0.0.1:7073 — everything the app reads.

Run:   python3 Mock/mock-catalog.py
Then:  launch the app in a simulator and connect to host 127.0.0.1, port 7073.

Pure Python 3 standard library. Leave it running in a terminal; Ctrl-C to stop.
"""

import json, struct, zlib, http.server, socketserver, re
from urllib.parse import urlparse, parse_qs

def png(r,g,b):
    w=h=160
    raw=bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w):
            # subtle diagonal shade
            f=0.7+0.3*((x+y)/(w+h))
            raw+=bytes([int(r*f),int(g*f),int(b*f)])
    def chunk(t,d): 
        c=t+d; return struct.pack(">I",len(d))+c+struct.pack(">I",zlib.crc32(c)&0xffffffff)
    sig=b'\x89PNG\r\n\x1a\n'
    ihdr=struct.pack(">IIBBBBB",w,h,8,2,0,0,0)
    idat=zlib.compress(bytes(raw),9)
    return sig+chunk(b'IHDR',ihdr)+chunk(b'IDAT',idat)+chunk(b'IEND',b'')

COVERS=[png(79,209,217),png(197,160,89),png(107,201,168),png(224,112,112),png(120,110,180),png(90,140,200)]

ARTISTS=[("Midnight Oil","Diesel and Dust","The Dead Heart","acrcloud"),
 ("Peter Gabriel","So","Sledgehammer","audd"),
 ("The Cure","Mixed Up","Lullaby","local_index"),
 ("Fleetwood Mac","Rumours","The Chain","acrcloud"),
 ("Talking Heads","Remain in Light","Once in a Lifetime","audd"),
 ("Kate Bush","Hounds of Love","Running Up That Hill","acrcloud"),
 ("Gary Moore","Still Got the Blues","Walking by Myself","local_index"),
 ("Dire Straits","Brothers in Arms","So Far Away","acrcloud")]

def track(i):
    a=ARTISTS[i%len(ARTISTS)]
    return {"id":100+i,"artist":a[0],"title":a[2],"album":a[1],
        "provider_artist":a[0],"provider_title":a[2],"provider_album":a[1],
        "has_display_override": i%4==0,"isrc":"GBAAA00000%02d"%i,
        "release_format":["vinyl","cd","digital"][i%3],
        "confirmed_release_format":["vinyl","cd","digital"][i%3],
        "release_confirmed": i%3==0,"duration_ms":180000+i*7000}

def play(i):
    a=ARTISTS[i%len(ARTISTS)]
    ident = i%5!=4
    return {"id":900+i,"listener_epoch":5000+i,"track_id":(100+i) if ident else None,
        "started_at":"2026-07-12T18:%02d:00Z"%(59-i if i<59 else 0),
        "source":a[3] if ident else "","reason":"" if ident else "no_match",
        "artist":a[0] if ident else "","title":a[2] if ident else "","album":a[1] if ident else "",
        "artwork_url":"/catalog/artwork/tracks/%d"%(100+i),
        "release_confirmed": i%3==0,"release_format":["vinyl","cd","digital"][i%3],
        "confidence":0.9-(i%5)*0.05,"duration_ms":180000+i*5000}

def release(i):
    a=ARTISTS[i%len(ARTISTS)]
    return {"source":["user","musicbrainz","discogs"][i%3],"release_id":"rel-%d"%i,
        "artist":a[0],"album":a[1],"year":str(1980+i),"release_format":["vinyl","cd","digital"][i%3],
        "label":"Columbia","country":"US","artwork_url":"/catalog/artwork/tracks/%d"%(100+i),
        "owned": i%3==0,"deletable": i%3==0,"tracklist_count":10+i,"catalog_tracks":i%4,
        "confirmed_at":"2026-07-10T12:00:00Z"}

def stylus_state():
    return {"active":True,"profile":{"id":1,"catalog_id":9,"brand":"Ortofon","model":"2M Blue",
        "stylus_profile":"Nude Elliptical","lifetime_hours":800,"initial_used_hours":0,
        "installed_at":"2026-05-01T10:00:00Z","is_custom":False},
        "metrics":{"vinyl_hours_since_install":312.4,"stylus_hours_total":312.4,
        "remaining_hours":487.6,"wear_percent":39.05,"state":"healthy"}}

def recognition_providers():
    return {"chain_mode":"sequential",
        "chain":[{"id":"acrcloud","display_name":"ACRCloud","enabled":True,"configured":True},
            {"id":"audd","display_name":"AudD","enabled":True,"configured":False},
            {"id":"local_index","display_name":"Local Index","enabled":True,"configured":True}],
        "builtins":{
            "acrcloud":{"name":"acrcloud","enabled":True,"host":"identify-eu-west-1.acrcloud.com",
                "api_key":"••••••••","api_secret":"••••••••","configured":True},
            "audd":{"name":"audd","enabled":True,"host":"","api_key":"","api_secret":"","configured":False}}}

def rig_equipment():
    return {"items":[{"id":"cd_player","label":"CD Player","backend":"broadlink",
        "actions":["power_toggle","play","pause","stop","next","previous","eject"],
        "role":"physical_media","physical_format":"cd","input_ids":["cd"],"has_remote":True}]}

def rig_status():
    return {"schema_version":1,
        "targets":[{"id":"amplifier","label":"Amplifier","backend":"broadlink",
            "capabilities":["power_toggle","volume_up","volume_down","next_input","prev_input","select_input"],
            "actions":{"power_toggle":{"learned":True},"volume_up":{"learned":True},
                "volume_down":{"learned":True},"next_input":{"learned":True},
                "prev_input":{"learned":True},"select_input":{"learned":True}}},
            {"id":"cd_player","label":"CD Player","backend":"broadlink",
            "capabilities":["power_toggle","play","pause","stop","next","previous","eject"],
            "actions":{"power_toggle":{"learned":True},"play":{"learned":True},
                "pause":{"learned":True},"stop":{"learned":False},
                "next":{"learned":False},"previous":{"learned":False},"eject":{"learned":False}}}],
        "amplifier":{"profile_id":"denon-pma","maker":"Denon","model":"PMA-600NE","input_mode":"discrete",
            "active_input_id":"phono","active_input_label":"Phono",
            "inputs":[{"id":"phono","label":"Phono","visible":True},
                {"id":"cd","label":"CD","visible":True},
                {"id":"airplay","label":"AirPlay","visible":True}],
            "power":{"state":"on","confidence":"high","method":"vu_probe"}}}

def stylus_catalog():
    return {"items":[
        {"id":9,"brand":"Ortofon","model":"2M Blue","stylus_profile":"Nude Elliptical",
            "min_hours":500,"max_hours":1000,"recommended_hours":800,"confidence":"low"},
        {"id":2,"brand":"Denon","model":"DL-103","stylus_profile":"Conical",
            "min_hours":300,"max_hours":500,"recommended_hours":500,"confidence":"medium"},
        {"id":6,"brand":"Audio-Technica","model":"AT-VM95ML","stylus_profile":"MicroLine",
            "min_hours":800,"max_hours":1200,"recommended_hours":1000,"confidence":"low"},
    ]}

class H(http.server.BaseHTTPRequestHandler):
    def log_message(self,*a): pass
    def _json(self,obj,code=200):
        b=json.dumps(obj).encode(); self.send_response(code)
        self.send_header("Content-Type","application/json"); self.send_header("Content-Length",str(len(b)))
        self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        p=urlparse(self.path); path=p.path
        m=re.match(r"/catalog/artwork/tracks/(\d+)",path)
        if m:
            b=COVERS[int(m.group(1))%len(COVERS)]
            self.send_response(200); self.send_header("Content-Type","image/png"); self.send_header("Content-Length",str(len(b)))
            self.end_headers(); self.wfile.write(b); return
        if path=="/status":
            return self._json({"playback":{"active":True,"epoch":5001,"track_id":100,
                "artist":"Midnight Oil","title":"The Dead Heart","album":"Diesel and Dust",
                "source":"acrcloud","position_ms":74000,"duration_ms":275000,"confidence":0.95,
                "artwork_url":"/catalog/artwork/tracks/100","media_format":"vinyl"},
                "catalog_schema_version":7,"catalog_db_path":"/var/lib/groove-catalog/catalog.db",
                "enricher_chain":["musicbrainz","discogs","itunes"]})
        if path=="/catalog/plays":
            return self._json({"items":[play(i) for i in range(24)],"page":1,"limit":50,"total":24,"total_pages":1})
        if path=="/catalog/tracks":
            return self._json({"items":[track(i) for i in range(24)],"page":1,"limit":50,"total":24,"total_pages":1})
        m=re.match(r"/catalog/tracks/(\d+)/profile",path)
        if m:
            i=int(m.group(1))-100
            return self._json({"track":track(max(0,i)),"fingerprints":[{"id":1,"track_id":100+i,"fingerprint_version":"v2","fingerprint_hash":"abc","offset_ms":0}],"plays":[play(i),play(i+1)]})
        m=re.match(r"/catalog/tracks/(\d+)$",path)
        if m: return self._json(track(int(m.group(1))-100))
        if path=="/catalog/releases":
            return self._json({"releases":[release(i) for i in range(12)]})
        if path=="/catalog/enrich/jobs":
            return self._json([{"id":700+i,"listener_epoch":5000+i,"track_id":100+i,
                "isrc":"GBAAA00000%02d"%i,"artist":ARTISTS[i%len(ARTISTS)][0],"title":ARTISTS[i%len(ARTISTS)][2],
                "album":ARTISTS[i%len(ARTISTS)][1],"status":["complete","pending","failed","enriching"][i%4]} for i in range(6)])
        m=re.match(r"/catalog/enrich/jobs/(\d+)",path)
        if m:
            i=int(m.group(1))-700
            rels=[{"id":800+i*2+k,"job_id":700+i,"status":"pending","source":["musicbrainz","discogs"][k%2],
                "release_id":"r%d"%k,"artist":ARTISTS[i%len(ARTISTS)][0],"title":ARTISTS[i%len(ARTISTS)][2],
                "album":ARTISTS[i%len(ARTISTS)][1],"release_format":["vinyl","cd"][k%2],"release_date":"1987-03-0%d"%(k+1),
                "artwork_url":"/catalog/artwork/tracks/%d"%(100+i),
                "tracklist":[{"position":"A%d"%(t+1),"ordinal":t+1,"title":"Track %d"%(t+1),"duration_ms":200000+t*9000} for t in range(8)]} for k in range(2)]
            return self._json({"job":{"id":700+i,"listener_epoch":5000+i,"artist":ARTISTS[i%len(ARTISTS)][0],
                "title":ARTISTS[i%len(ARTISTS)][2],"album":ARTISTS[i%len(ARTISTS)][1],"status":"complete","isrc":"GBAAA0000010"},"releases":rels})
        if path=="/catalog/plays/pending-association":
            return self._json({"items":[{"listener_epoch":6000+i,"started_at":"2026-07-12T17:0%d:00Z"%i,
                "failure_reason":"no_match","suggested_track_id":100+i,"suggested_artist":ARTISTS[i%len(ARTISTS)][0],
                "suggested_title":ARTISTS[i%len(ARTISTS)][2],"suggested_album":ARTISTS[i%len(ARTISTS)][1]} for i in range(3)],"total":3})
        if path=="/enrich/providers":
            return self._json({"order":["musicbrainz","discogs","itunes"],"chain":[
                {"id":"musicbrainz","display_name":"MusicBrainz","enabled":True,"configured":True},
                {"id":"discogs","display_name":"Discogs","enabled":True,"configured":True},
                {"id":"itunes","display_name":"iTunes","enabled":False,"configured":False}]})
        if path=="/catalog/stylus":
            return self._json(stylus_state())
        if path=="/catalog/stylus/catalog":
            return self._json(stylus_catalog())
        if path=="/rig/status":
            return self._json(rig_status())
        if path=="/rig/equipment":
            return self._json(rig_equipment())
        if path=="/identity/recognition/providers":
            return self._json(recognition_providers())
        m=re.match(r"/rig/sessions/(.+)",path)
        if m:
            return self._json({"id":m.group(1),"kind":"learn","status":"success",
                "backend":"broadlink","target_id":"cd_player","action":"stop"})
        self._json({"error":"not found"},404)
    def do_POST(self):
        if self.path=="/catalog/stylus/replace": return self._json(stylus_state())
        if self.path.startswith("/rig/targets/") and "/actions/" in self.path:
            return self._json(rig_status())
        if self.path=="/rig/observe/power/ensure_on":
            return self._json({"state":"on","confidence":"high","method":"vu_probe"})
        if self.path=="/rig/observe/power/ensure_off":
            return self._json({"state":"off","confidence":"high","method":"vu_probe"})
        if self.path=="/rig/runtime/active_input":
            return self._json({"input_id":"phono","input_label":"Phono"})
        if self.path=="/rig/sessions/learn":
            return self._json({"id":"sess-1","kind":"learn","status":"success",
                "backend":"broadlink","target_id":"cd_player","action":"stop"},202)
        if self.path=="/rig/equipment":
            return self._json({"id":"new_device","label":"New Device","backend":"broadlink",
                "actions":["power_toggle"],"role":"physical_media","physical_format":"cd",
                "has_remote":True},201)
        self._json({"ok":True})
    def do_PUT(self):
        if self.path=="/catalog/stylus": return self._json(stylus_state())
        if self.path.startswith("/identity/recognition/providers"):
            return self._json(recognition_providers())
        self._json({"ok":True})
    def do_PATCH(self):
        if self.path.startswith("/identity/recognition/providers/"):
            return self._json(recognition_providers())
        self._json(track(0))
    def do_DELETE(self): self._json({"ok":True})

socketserver.TCPServer.allow_reuse_address=True
with socketserver.TCPServer(("127.0.0.1",7073),H) as s:
    print("mock catalog on :7073"); s.serve_forever()
