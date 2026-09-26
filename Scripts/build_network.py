#!/usr/bin/env python3
"""Explicit build-time OSM fetch. Never called by the app. ODbL source retained."""
import urllib.request, urllib.parse, json, math, collections, pathlib, datetime, sys
ROOT=pathlib.Path(__file__).resolve().parent.parent
# 0.4: Kokura station surroundings incl. road types that pedestrians share (sidewalk presence unverified).
B=(33.8775,130.8710,33.8925,130.8900)
WALK={'footway','path','pedestrian','steps','corridor'}
ROAD={'living_street','residential','service','unclassified','tertiary','tertiary_link','secondary','secondary_link','primary','primary_link','track'}
query='[out:json][timeout:60];way["highway"~"^('+'|'.join(sorted(WALK|ROAD))+')$"]('+','.join(map(str,B))+');out meta;>;out skel qt;'
raw=ROOT/'Data/raw/kokura-osm.json'
if not raw.exists():
 if '--fetch' not in sys.argv: sys.exit('Data/raw/kokura-osm.json がありません。Overpass APIから取得する場合は --fetch を付けて実行してください。')
 req=urllib.request.Request('https://overpass-api.de/api/interpreter',data=urllib.parse.urlencode({'data':query}).encode(),headers={'User-Agent':'JunctionGuide-MVP/1.0','Accept':'application/json'})
 raw.write_bytes(urllib.request.urlopen(req,timeout=90).read())
d=json.loads(raw.read_text()); nodes={str(e['id']):e for e in d['elements'] if e['type']=='node'}; ways=[e for e in d['elements'] if e['type']=='way']
def inside(n): return B[0]<=n['lat']<=B[2] and B[1]<=n['lon']<=B[3]
def coord(n): return {'latitude':n['lat'],'longitude':n['lon']}
def distance(a,b):
 r=math.pi/180; x=math.sin((a['lat']-b['lat'])*r/2)**2+math.cos(a['lat']*r)*math.cos(b['lat']*r)*math.sin((a['lon']-b['lon'])*r/2)**2
 return 6371000*2*math.atan2(math.sqrt(x),math.sqrt(max(0,1-x)))
# Segments are between real OSM vertices; no invented crossing connections.
edges=[]; adjacency=collections.defaultdict(set)
for w in ways:
 t=w['tags']
 # Ground-level only. Road bridges (layer<=1) are kept so the river crossings stay connected; tunnels/indoor/steps/corridors are excluded.
 layer=t.get('layer','1' if t.get('bridge','no')!='no' else '0')
 if t.get('access') in ('private','no') and t.get('foot') not in ('yes','designated','permissive'): continue
 if t.get('foot') in ('no','private') or layer not in ('0','1') or (layer=='1' and t.get('bridge','no')=='no') or t.get('level','0')!='0' or t.get('tunnel','no')!='no' or t.get('indoor','no')!='no' or t.get('highway') in ('steps','corridor') or t.get('service') in ('drive-through',) or t.get('area')=='yes': continue
 ids=list(map(str,w['nodes'])); direction={'yes':'forward','1':'forward','-1':'backward'}.get(t.get('oneway:foot'),'both')
 for a,b in zip(ids,ids[1:]):
  if a==b or not inside(nodes[a]) or not inside(nodes[b]): continue
  length=distance(nodes[a],nodes[b])
  if length<0.05: continue
  eid=f'osm:{w["id"]}:{a}:{b}'
  edges.append({'id':eid,'name':t.get('name',{'footway':'名称未登録の歩行区間','path':'名称未登録の小道','pedestrian':'名称未登録の歩行者道路','service':'名称未登録の通路・構内道路'}.get(t['highway'],'名称未登録の道路')),'from':a,'to':b,'shape':[coord(nodes[a]),coord(nodes[b])],'distance':length,'direction':direction,'conditions':('歩行用OSMデータ。' if t['highway'] in WALK else '車道OSMデータ。歩道の有無・幅・') +'現地接続・横断・利用条件は未確認','sourceID':f'OSM way {w["id"]} version {w.get("version","unknown")}','verification':'現地未確認','layer':t.get('layer','1' if t.get('bridge','no')!='no' else '未記載'),'kind':t['highway']})
  adjacency[a].add(b);adjacency[b].add(a)
seen=set(); components=[]
for node in adjacency:
 if node in seen:continue
 queue=[node]; c={node};seen.add(node)
 while queue:
  for neighbor in adjacency[queue.pop()]:
   if neighbor not in seen: seen.add(neighbor);c.add(neighbor);queue.append(neighbor)
 components.append(c)
component=max(components,key=len);edges=[e for e in edges if e['from'] in component and e['to'] in component]
# Split only at junctions or edge attribute changes. Collapse degree-2 vertices for usable list entries.
by_node=collections.defaultdict(list)
for e in edges:
 by_node[e['from']].append(e);by_node[e['to']].append(e)
def signature(e):return (e['name'],e['kind'],e['direction'],e['layer'],e['sourceID'])
anchors={n for n,es in by_node.items() if len(es)!=2 or signature(es[0])!=signature(es[1])}
used=set(); merged=[]
for edge in edges:
 if edge['id'] in used:continue
 # Directed segments are retained; most walking ways are bidirectional.
 a=edge['from'];b=edge['to']; shape=list(edge['shape']);length=edge['distance'];used.add(edge['id']); base=edge
 if edge['direction']=='both':
  for reverse in (False,True):
   current=a if reverse else b
   while current not in anchors:
    options=[e for e in by_node[current] if e['id'] not in used and signature(e)==signature(base)]
    if len(options)!=1:break
    nxt=options[0];used.add(nxt['id']);other=nxt['to'] if nxt['from']==current else nxt['from'];p=coord(nodes[other]);length+=nxt['distance']
    if reverse:shape.insert(0,p);a=other
    else:shape.append(p);b=other
    current=other
 merged.append(dict(base,id=f'osm:{base["sourceID"].split()[2]}:{a}:{b}',**{'from':a,'to':b,'shape':shape,'distance':length}))
active={e[k] for e in merged for k in ['from','to']}
places=[{'id':n,'name':'接続点 '+n[-5:],'coordinate':coord(nodes[n])} for n in sorted(active)]
destinations=[]
for identifier,name,lat,lon in [('kokura','小倉駅南側・実験接続点',33.8860,130.8821),('kyomachi','京町・実験接続点',33.8847,130.8810),('uomachi','魚町・実験接続点',33.8830,130.8806),('castle','小倉城付近・実験接続点',33.8846,130.8750),('riverwalk','紫川東岸・実験接続点',33.8815,130.8770)]:
 node=min(active,key=lambda n:distance(nodes[n],{'lat':lat,'lon':lon}))
 destinations.append({'id':identifier,'name':name,'nodeID':node,'note':'OSMネットワーク上の実験接続点。施設入口・避難所ではありません。同行者による現地確認が必要です。'})
network={'id':'kokura-ground-osm','version':d['osm3s']['timestamp_osm_base'],'bounds':dict(zip(['south','west','north','east'],B)),'source':'© OpenStreetMap contributors / ODbL 1.0','acquiredAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'isSimulated':False,'nodes':places,'edges':merged,'destinations':destinations}
(ROOT/'Data/kokura-network.json').write_text(json.dumps(network,ensure_ascii=False,indent=2))
(ROOT/'Data/raw/query.txt').write_text(query+'\n')
print('components before selection:',len(components),'selected nodes:',len(places),'segments:',len(merged),'destinations:',destinations)
