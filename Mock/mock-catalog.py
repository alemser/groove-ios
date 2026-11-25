"""
mock-catalog.py — a zero-dependency fake groove-catalog server for previewing
the Groove iOS app without a real backend.

Serves canned tracks, plays, releases, enrich jobs, pending associations, status,
and generated cover art on http://127.0.0.1:7073 — everything the app reads.

Run:   python3 Mock/mock-catalog.py
Then:  launch the app in a simulator and connect to host 127.0.0.1, port 7073.

Pure Python 3 standard library. Leave it running in a terminal; Ctrl-C to stop.

MOCK_EDITION_QUESTION=1 opens a "which pressing is playing?" question on
/status, offering two of the library's releases (rel-0 and rel-3); choosing or
dismissing closes it.

RIG_URL=http://127.0.0.1:7099 sends /rig/* (but /rig/capture/*) to a groove-rig
running there instead of the canned rig answers, as groove-catalog does: a
local groove-rig with a fake DeviceLink bridge shows the DeviceLink screens.

Scenarios, for checking a screen against what a board does:
  FAIL_PREFIX=/rig/,/enrich/providers/   every write (POST/PUT/PATCH/DELETE) whose
      path starts with one of these answers 502 {"error": "..."}: the apps'
      failed-action messages, with their Retry.
  IDLE=1          nothing is playing and no album waits to be added: the
      Library grid starts with a release card.
  ASSOC_AFTER=20  the pending associations appear only this many seconds after
      start: a banner that arrives after the grid loaded.
  WARM_UP=30      the amplifier reads warming_up, with warming_up_until this
      many seconds after start, as groove-rig does after a power_on it sent:
      the remote's warm-up countdown. Past it, /rig/status reads on.
  SETUP=new       a board just set up: no enricher is on (/status has no
      enricher_chain) and no recognition provider has credentials, as
      groove-catalog and groove-identity answer before anything is configured.
      Home's "Finish Setting Up" card asks for both.
  SETUP=enriched  the enrichers are done, the recognition provider is not: the
      card offers only the optional step, with Not Now.
  UPDATES=unset   board updates (/system/updates, groove-updater's status as
      groove-catalog forwards it): nobody answered "automatic or ask first"
      yet, so the apps ask. Other values: available (ask first, a release with
      a security fix waits for approval), installed (automatic, a release just
      installed), rolled_back (the last install was rolled back), none (an
      older catalog: 404), off (the updater is off: 503). Unset: ask first and
      up to date. The preference, approval and check change the mock's state.
  MOCK_LOG=1      prints each request, with the seconds since start.
"""

import time
START = time.time()
import json, os, struct, zlib, http.server, socketserver, re
from urllib.parse import urlparse, parse_qs

EDITION_QUESTION_OPEN = os.environ.get("MOCK_EDITION_QUESTION") == "1"
RIG_URL = os.environ.get("RIG_URL", "").rstrip("/")
WARM_UP = float(os.environ.get("WARM_UP", "0"))
SETUP = os.environ.get("SETUP", "")

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

def edition_question():
    a, b = release(0), release(3)
    return {"artist": a["artist"], "album": a["album"], "track_id": 100, "candidates": [
        {"source": a["source"], "release_id": a["release_id"], "album": a["album"], "year": "1977",
         "release_format": "vinyl", "artwork_url": a["artwork_url"], "tracklist_count": 10,
         "position": "A1", "suggested": True, "suggested_why": "the detector hears vinyl"},
        {"source": b["source"], "release_id": b["release_id"], "album": b["album"], "year": "2001",
         "release_format": "cd", "artwork_url": b["artwork_url"], "tracklist_count": 12, "position": "1"},
    ]}

def stylus_state():
    return {"active":True,"profile":{"id":1,"catalog_id":9,"brand":"Ortofon","model":"2M Blue",
        "stylus_profile":"Nude Elliptical","lifetime_hours":800,"initial_used_hours":0,
        "installed_at":"2026-05-01T10:00:00Z","is_custom":False},
        "metrics":{"vinyl_hours_since_install":312.4,"stylus_hours_total":312.4,
        "remaining_hours":487.6,"wear_percent":39.05,"state":"healthy"}}

def recognition_providers():
    if SETUP:
        # groove-identity before anything is configured: the built-ins listed, off.
        return {"chain_mode":"first_success","min_confidence":0.6,"offline":False,"suspended":False,
            "custom_providers":[],"builtins":{},
            "chain":[{"id":"acrcloud","display_name":"ACRCloud","enabled":False,"configured":False},
                {"id":"audd","display_name":"AudD","enabled":False,"configured":False}]}
    return {"chain_mode":"first_success","min_confidence":0.6,"offline":False,"suspended":False,
        "custom_providers":[],
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
            "power":rig_power()}}

def rig_power():
    """The amplifier's power: warming up until WARM_UP seconds after start, then on."""
    warm_until = START + WARM_UP
    if time.time() < warm_until:
        until = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(warm_until))
        return {"state":"warming_up","confidence":"high","method":"command_inference","warming_up_until":until}
    return {"state":"on","confidence":"high","method":"vu_probe"}

def stylus_catalog():
    return {"items":[
        {"id":9,"brand":"Ortofon","model":"2M Blue","stylus_profile":"Nude Elliptical",
            "min_hours":500,"max_hours":1000,"recommended_hours":800,"confidence":"low"},
        {"id":2,"brand":"Denon","model":"DL-103","stylus_profile":"Conical",
            "min_hours":300,"max_hours":500,"recommended_hours":500,"confidence":"medium"},
        {"id":6,"brand":"Audio-Technica","model":"AT-VM95ML","stylus_profile":"MicroLine",
            "min_hours":800,"max_hours":1200,"recommended_hours":1000,"confidence":"low"},
    ]}

# Fake groove-detector /capture/* behind /rig/capture/*: a quiet variable line
# out whose level follows the gain step (28 steps, -12..+30 dB, like oceano's
# USB card). Like the real meter, a gain change rescales the reading at once
# (no re-measuring); the live needle wobbles around the window level.
CAPTURE={"input_level":"fixed","step":5}
CAPTURE_TARGET={"too_low_below":0.035,"low_below":0.09,"high_above":0.40,"high_peak":0.89,"clip_peak":0.98}

def capture_band(rms,peak):
    t=CAPTURE_TARGET
    if peak>=t["clip_peak"]: return "clipping"
    if peak>=t["high_peak"] or rms>t["high_above"]: return "high"
    if rms<t["too_low_below"]: return "too_low"
    if rms<t["low_below"]: return "low"
    return "good"

def capture_suggest(step,rms,peak,band):
    # Same rule as groove-detector's level.Suggest.
    import math
    if band=="good" or rms<=0: return None
    t=CAPTURE_TARGET; target=math.sqrt(t["low_below"]*t["high_above"])
    delta=min(20*math.log10(target/rms),12.0)
    if peak>0: delta=min(delta,20*math.log10(0.8/peak))
    s=max(0,min(28,step+math.floor(delta/1.5)))
    return None if s==step else s

def capture_level():
    import math, random
    step=CAPTURE["step"]; db=-12+1.5*step
    rms=0.02*10**((db+4.5)/20); peak=min(1.0,rms*3.2)
    band=capture_band(rms,peak)
    prog={"band":band,"live_rms":round(rms*random.uniform(0.6,1.1),4),
        "rms_p95":round(rms,4),"peak_max":round(peak,4),
        "seconds":20.0,"min_seconds":5.0,"window_seconds":20.0,"target":CAPTURE_TARGET}
    if peak>0: prog["headroom_db"]=round(20*math.log10(1/peak),1)
    s=capture_suggest(step,rms,peak,band)
    if s is not None: prog["suggested_step"]=s
    return {"input_level":CAPTURE["input_level"],"gate":"programme",
        "gain":{"pct":round(step*100/28),"step":step,"max_step":28,"db":db,
            "db_per_step":1.5,"control":"Mic"},
        "programme":prog}

# "Add to library" suggestions (groove-catalog#24): recognized albums with no
# edition in the library yet. Accept/fork/dismiss resolve them in memory.
def sg_edition(src,rid,fmt,country,year,label,total,matched,cover,confirmed=False,reasons=()):
    return {"source":src,"release_id":rid,"artist":"Talking Heads","album":"Remain in Light",
        "release_format":fmt,"release_date":year,"country":country,"label":label,
        "artwork_url":"/catalog/artwork/tracks/%d"%(100+cover),"track_total":total,
        "confirmed":confirmed,"matched_tracks":matched,"score":50.0-len(rid),
        "reasons":list(reasons)}
SUGGESTIONS={1:{"id":1,"artist":"Talking Heads","album":"Remain in Light","status":"pending",
    "medium_hint":"vinyl","created_at":"2026-10-11T19:00:00Z","updated_at":"2026-10-11T19:20:00Z",
    "recognized_tracks":[{"track_id":104,"title":"Born Under Punches"},{"track_id":112,"title":"Crosseyed and Painless"},
        {"track_id":120,"title":"The Great Curve"}],
    "editions":[
        sg_edition("musicbrainz","mb-ril-cd","cd","US","1984","Sire",8,3,4,True,
            ("edition the play was confirmed on","3/3 recognized tracks on tracklist","played in tracklist order")),
        sg_edition("discogs","dg-ril-lp","vinyl","UK","1980","Sire",8,3,12,False,
            ("3/3 recognized tracks on tracklist","played in tracklist order","matches vinyl playback")),
        sg_edition("discogs","dg-ril-lp-us","vinyl","US","1980","Sire",8,3,20,False,("3/3 recognized tracks on tracklist",)),
        sg_edition("itunes","it-ril","digital","US","2006","Rhino",12,3,4,False,("3/3 recognized tracks on tracklist",)),
        sg_edition("musicbrainz","mb-ril-remaster","cd","EU","2006","Rhino",12,3,12,False,("3/3 recognized tracks on tracklist",)),
        sg_edition("discogs","dg-ril-cass","cassette","US","1980","Sire",8,2,20,False,("2/3 recognized tracks on tracklist",)),
        sg_edition("musicbrainz","mb-ril-jp","cd","JP","1989","Sire",8,3,4,False,("3/3 recognized tracks on tracklist",)),
    ]}}

def suggestion_view(sg,alts=5):
    out={k:v for k,v in sg.items() if k!="editions"}
    eds=sg["editions"]
    out["primary"]=eds[0] if eds else None
    rest=eds[1:]
    out["alternatives"]=rest[:alts]
    out["more_alternatives"]=max(0,len(rest)-alts)
    return out

def pending_suggestions(alts=5):
    return [suggestion_view(sg,alts) for sg in SUGGESTIONS.values() if sg["status"]=="pending"]

if os.environ.get("IDLE") == "1":
    SUGGESTIONS.clear()

ASSOC_AFTER = float(os.environ.get("ASSOC_AFTER", "0"))
FAIL_PREFIXES = [p for p in os.environ.get("FAIL_PREFIX", "").split(",") if p]

UPDATES = os.environ.get("UPDATES", "")

def update_status_initial():
    s = {"preference": "ask_first", "phase": "idle",
         "installed": {"release": "2026.12.1", "components": [{"name": "groove-catalog", "version": "a1b2c3d"}]},
         "available": None, "approved_release": "",
         "last_check": {"at": "2026-12-14T11:02:00Z", "error": ""}, "last_result": None}
    if UPDATES == "unset":
        s.update(preference="unset", last_check=None)
    if UPDATES == "available":
        s["available"] = {"release": "2026.12.2", "published_at": "2026-12-14T10:00:00Z",
            "notes": "Fixes the screen staying dim after Bluetooth pauses.", "security": True,
            "components": ["groove-display"]}
    if UPDATES == "installed":
        s["preference"] = "automatic"
        s["last_result"] = {"release": "2026.12.1", "outcome": "installed", "at": "2026-12-15T02:14:00Z",
            "notes": "Fixes the screen staying dim after Bluetooth pauses.", "error": ""}
    if UPDATES == "rolled_back":
        s["last_result"] = {"release": "2026.12.2", "outcome": "rolled_back", "at": "2026-12-15T02:14:00Z",
            "notes": "", "error": "groove-display did not come up"}
    return s

UPDATE_STATUS = update_status_initial()

def update_route(method, path, body):
    """(status code, answer) for a /system/updates* request."""
    if UPDATES == "none": return 404, {"error": "not found"}
    if UPDATES == "off": return 503, {"error": "groove-updater is not running"}
    s = UPDATE_STATUS
    if method == "GET" and path == "/system/updates": return 200, s
    if method == "PUT" and path == "/system/updates/preference":
        if body.get("preference") not in ("automatic", "ask_first"):
            return 400, {"error": "preference must be automatic or ask_first"}
        s["preference"] = body["preference"]; return 200, s
    if s["preference"] == "unset": return 409, {"error": "no update preference set yet"}
    if method == "POST" and path == "/system/updates/check":
        s["last_check"] = {"at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "error": ""}
        return 202, s
    if method == "POST" and path == "/system/updates/approval":
        if not s["available"] or body.get("release") != s["available"]["release"]:
            return 409, {"error": "that release is not the available one"}
        s.update(approved_release=body["release"], phase="waiting_for_idle"); return 200, s
    if method == "DELETE" and path == "/system/updates/approval":
        s.update(approved_release="", phase="idle"); return 200, s
    return 404, {"error": "not found"}


def identify_search():
    """Two editions of each album, as a release search finds them. Like groove-catalog,
    only the first hit carries a tracklist: the others are looked up through prefill."""
    hits = []
    for i, (artist, album, title, _) in enumerate(ARTISTS):
        for k, (fmt, country) in enumerate((("vinyl", "GB"), ("cd", "DE"))):
            hit = {"source": ["musicbrainz", "discogs"][k], "artist": artist, "title": title, "album": album,
                "recording_id": "rec-%d" % i, "release_id": "rel-%d-%s" % (i, fmt), "release_format": fmt,
                "release_date": "19%d-01-01" % (80 + i), "country": country, "label": "Mock Records",
                "artwork_url": "/catalog/artwork/tracks/%d" % (100 + i)}
            if not hits:
                hit["tracklist"] = [{"ordinal": t + 1, "position": "A%d" % (t + 1), "title": "Track %d" % (t + 1),
                    "duration_ms": 200000 + t * 9000} for t in range(8)]
            hits.append(hit)
    return {"items": hits}


def prefill(hit):
    """The edition a hit names, with its tracklist. Alternate releases have a track with no
    time, as many providers' editions do; the second it takes is a provider's lookup."""
    time.sleep(1)
    timed = sum(map(ord, hit.get("release_id") or "")) % 2 == 0
    tracklist = [{"ordinal": t + 1, "position": "A%d" % (t + 1), "title": "Track %d" % (t + 1),
        "duration_ms": 200000 if timed or t < 3 else None} for t in range(6)]
    return {"release": {"id": 0, "job_id": 0, "status": "", "artist": hit.get("artist"), "album": hit.get("album"),
        "release_format": hit.get("release_format"), "country": hit.get("country"), "tracklist": tracklist}}


class H(http.server.BaseHTTPRequestHandler):
    def _rig_proxied(self):
        """Forwards a /rig/* request to RIG_URL when set; True when it did."""
        if not RIG_URL or not self.path.startswith("/rig/") or self.path.startswith("/rig/capture/"):
            return False
        import urllib.request, urllib.error
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n) if n else None
        req = urllib.request.Request(RIG_URL + self.path[len("/rig"):], data=body, method=self.command,
                                     headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=40) as r:
                code, data = r.status, r.read()
        except urllib.error.HTTPError as e:
            code, data = e.code, e.read()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
        return True

    def log_message(self,fmt,*a):
        if os.environ.get("MOCK_LOG") == "1": print("%.1f" % (time.time() - START), fmt % a, flush=True)

    def _failing(self):
        """FAIL_PREFIX: a write the scenario makes fail, as a board that didn't answer."""
        if any(self.path.startswith(p) for p in FAIL_PREFIXES):
            self._json({"error": "the board did not answer in time"}, 502)
            return True
        return False
    def _json(self,obj,code=200):
        b=json.dumps(obj).encode(); self.send_response(code)
        self.send_header("Content-Type","application/json"); self.send_header("Content-Length",str(len(b)))
        self.end_headers(); self.wfile.write(b)
    def _updates(self):
        """Answers a /system/updates* request; False for any other path."""
        path = urlparse(self.path).path
        if not path.startswith("/system/updates"): return False
        body = self._body() if self.command in ("POST", "PUT") else {}
        code, answer = update_route(self.command, path, body)
        self._json(answer, code); return True
    def do_GET(self):
        if self._rig_proxied(): return
        if self._updates(): return
        p=urlparse(self.path); path=p.path
        m=re.match(r"/catalog/artwork/tracks/(\d+)",path)
        if m:
            b=COVERS[int(m.group(1))%len(COVERS)]
            self.send_response(200); self.send_header("Content-Type","image/png"); self.send_header("Content-Length",str(len(b)))
            self.end_headers(); self.wfile.write(b); return
        if path=="/status":
            status = {"playback":{"active":os.environ.get("IDLE") != "1","epoch":5001,"track_id":100,
                "artist":"Midnight Oil","title":"The Dead Heart","album":"Diesel and Dust",
                "source":"acrcloud","position_ms":74000,"duration_ms":275000,"confidence":0.95,
                "artwork_url":"/catalog/artwork/tracks/100","media_format":"vinyl"},
                "catalog_schema_version":7,"catalog_db_path":"/var/lib/groove-catalog/catalog.db",
                "enricher_chain":["musicbrainz","discogs","itunes"]}
            if SETUP=="new":
                del status["enricher_chain"]  # groove-catalog omits it when empty
            if EDITION_QUESTION_OPEN:
                status["edition_question"] = edition_question()
            return self._json(status)
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
        if path=="/catalog/library/suggestions":
            alts=int(parse_qs(p.query).get("alternatives",["5"])[0])
            items=pending_suggestions(alts)
            return self._json({"suggestions":items,"pending":len(items)})
        m=re.match(r"/catalog/library/suggestions/(\d+)$",path)
        if m:
            sg=SUGGESTIONS.get(int(m.group(1)))
            if not sg: return self._json({"error":"not found"},404)
            return self._json(suggestion_view(sg,int(parse_qs(p.query).get("alternatives",["5"])[0])))
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
        if path=="/catalog/identify/search":
            return self._json(identify_search())
        if path=="/catalog/tracks/pending-release":
            return self._json({"items":[]})
        if path=="/catalog/plays/pending-association":
            n = 3 if time.time() - START >= ASSOC_AFTER else 0
            return self._json({"items":[{"listener_epoch":6000+i,"started_at":"2026-07-12T17:0%d:00Z"%i,
                "failure_reason":"no_match","suggested_track_id":100+i,"suggested_artist":ARTISTS[i%len(ARTISTS)][0],
                "suggested_title":ARTISTS[i%len(ARTISTS)][2],"suggested_album":ARTISTS[i%len(ARTISTS)][1]} for i in range(n)],"total":n})
        if path=="/enrich/providers" and SETUP=="new":
            return self._json({"order":["musicbrainz","discogs","itunes"],"chain":[
                {"id":"musicbrainz","display_name":"MusicBrainz","enabled":False,"configured":False},
                {"id":"discogs","display_name":"Discogs","enabled":False,"configured":False},
                {"id":"itunes","display_name":"iTunes Search","enabled":False,"configured":True}]})
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
        if path=="/rig/capture/level":
            return self._json(capture_level())
        if path=="/identity/recognition/providers":
            return self._json(recognition_providers())
        m=re.match(r"/rig/sessions/(.+)",path)
        if m:
            return self._json({"id":m.group(1),"kind":"learn","status":"success",
                "backend":"broadlink","target_id":"cd_player","action":"stop"})
        self._json({"error":"not found"},404)
    def do_POST(self):
        if self._failing(): return
        if self._rig_proxied(): return
        if self._updates(): return
        global EDITION_QUESTION_OPEN
        if self.path=="/catalog/stylus/replace": return self._json(stylus_state())
        if self.path=="/catalog/user-releases/prefill-from-search": return self._json(prefill(self._body()))
        if self.path in ("/identity/album-programme/choose-edition", "/identity/album-programme/dismiss-edition-question"):
            EDITION_QUESTION_OPEN = False
            self.send_response(204); self.end_headers(); return
        m=re.match(r"/catalog/library/suggestions/(\d+)/(accept|fork|dismiss)",self.path)
        if m:
            sg=SUGGESTIONS.get(int(m.group(1)))
            if not sg: return self._json({"error":"not found"},404)
            if sg["status"]!="pending": return self._json({"error":"library suggestion is not pending"},409)
            body=self._body(); action=m.group(2)
            ed=next((e for e in sg["editions"] if e["source"]==body.get("source") and e["release_id"]==body.get("release_id")),sg["editions"][0])
            draft={"id":990,"job_id":7990,"status":"pending","source":"user","release_id":"user-%s"%ed["release_id"],
                "artist":ed["artist"],"album":ed["album"],"title":ed["album"],"release_format":ed["release_format"],
                "release_date":ed["release_date"],"country":ed["country"],"label":ed["label"],"artwork_url":ed["artwork_url"],
                "tracklist":[{"position":str(t+1),"ordinal":t+1,"title":"Track %d"%(t+1),"duration_ms":200000+t*9000} for t in range(ed["track_total"])]}
            if action=="fork":
                return self._json({"draft":draft,"job":{"id":7990,"listener_epoch":1000000000001,"artist":ed["artist"],
                    "album":ed["album"],"title":ed["album"],"status":"complete"},"track_id":0})
            sg["status"]="accepted" if action=="accept" else "dismissed"
            if action=="accept":
                draft["status"]="confirmed"
                return self._json({"suggestion":suggestion_view(sg),"release":draft})
            return self._json(suggestion_view(sg))
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
    def _body(self):
        n=int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n) or b"{}")
    def do_PUT(self):
        if self._failing(): return
        if self._rig_proxied(): return
        if self._updates(): return
        if self.path=="/catalog/stylus": return self._json(stylus_state())
        if self.path=="/rig/capture/input-level":
            to=self._body().get("input_level","fixed"); frm=CAPTURE["input_level"]
            restored=False
            if to!=frm:
                # Each mode keeps its own gain, like the real detector.
                CAPTURE[frm+"_step"]=CAPTURE["step"]
                if to+"_step" in CAPTURE and CAPTURE[to+"_step"]!=CAPTURE["step"]:
                    CAPTURE["step"]=CAPTURE[to+"_step"]; restored=True
                CAPTURE["input_level"]=to
            return self._json({"input_level":to,"capture_gain_pct":round(CAPTURE["step"]*100/28),"gain_restored":restored})
        if self.path=="/rig/capture/gain":
            step=int(self._body().get("capture_gain_step",CAPTURE["step"]))
            if not 0<=step<=28: return self._json({"error":"capture_gain_step must be 0–28"},400)
            CAPTURE["step"]=step; g=capture_level()["gain"]
            return self._json({"capture_gain_pct":g["pct"],"capture_gain_step":step,
                "capture_gain_max_step":28,"capture_gain_db":g["db"],"capture_gain_control":"Mic"})
        if self.path.startswith("/identity/recognition/providers"):
            return self._json(recognition_providers())
        self._json({"ok":True})
    def do_PATCH(self):
        if self._failing(): return
        if self._rig_proxied(): return
        if self.path.startswith("/identity/recognition/providers/"):
            return self._json(recognition_providers())
        self._json(track(0))
    def do_DELETE(self):
        if self._failing(): return
        if self._rig_proxied(): return
        if self._updates(): return
        self._json({"ok":True})

# Threaded: the app fires several requests at once (and URLSession may hold
# an idle connection open), which a single-threaded server serialises into a
# screen full of "Loading…".
socketserver.ThreadingTCPServer.allow_reuse_address=True
socketserver.ThreadingTCPServer.daemon_threads=True
with socketserver.ThreadingTCPServer(("127.0.0.1",7073),H) as s:
    print("mock catalog on :7073"); s.serve_forever()
