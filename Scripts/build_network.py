#!/usr/bin/env python3
"""Build a saved, ground-level OSM walking network for one supported region."""
import argparse, urllib.request, urllib.parse, urllib.error, json, math, collections, pathlib, datetime, shutil

ROOT=pathlib.Path(__file__).resolve().parent.parent
REGIONS={
 'kokura': {
  'name':'小倉駅周辺','bounds':(33.8775,130.8710,33.8925,130.8900),'network_id':'kokura-ground-osm',
  'destinations':[('kokura','小倉駅南側・実験接続点',33.8860,130.8821),('kyomachi','京町・実験接続点',33.8847,130.8810),('uomachi','魚町・実験接続点',33.8830,130.8806),('castle','小倉城付近・実験接続点',33.8846,130.8750),('riverwalk','紫川東岸・実験接続点',33.8815,130.8770)],
 },
 'tobata': {
  'name':'九工大前駅・戸畑キャンパス周辺','bounds':(33.8880,130.8320,33.9010,130.8520),'network_id':'tobata-ground-osm',
  'destinations':[('kyukodai-mae','九工大前駅付近・実験接続点',33.9001,130.8406),('kit-main-gate','戸畑キャンパス正門付近・実験接続点',33.8947,130.8393),('kit-south','戸畑キャンパス南側・実験接続点',33.8918,130.8398)],
 },
}
WALK={'footway','path','pedestrian','steps','corridor'}
ROAD={'living_street','residential','service','unclassified','tertiary','tertiary_link','secondary','secondary_link','primary','primary_link','track'}

parser=argparse.ArgumentParser()
parser.add_argument('--region',choices=REGIONS,default='kokura')
parser.add_argument('--fetch',action='store_true',help='archive existing files and fetch fresh OSM data')
args=parser.parse_args();region=REGIONS[args.region];B=region['bounds']
raw=ROOT/f'Data/raw/{args.region}-osm.json';query_path=ROOT/f'Data/raw/{args.region}-query.txt';output=ROOT/f'Data/{args.region}-network.json'
query='[out:json][timeout:60];way["highway"~"^('+'|'.join(sorted(WALK|ROAD))+')$"]('+','.join(map(str,B))+');out meta;>;out skel qt;'

def archive_existing():
 stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H-%M-%SZ');archive=ROOT/'Data/archive';archive.mkdir(parents=True,exist_ok=True)
 for path in (raw,query_path,output):
  if path.exists():shutil.copy2(path,archive/f'{path.stem}-{stamp}{path.suffix}')

if args.fetch:
 archive_existing();raw.parent.mkdir(parents=True,exist_ok=True)
 payload=urllib.parse.urlencode({'data':query}).encode();last_error=None
 for endpoint in ('https://overpass.private.coffee/api/interpreter','https://lz4.overpass-api.de/api/interpreter','https://overpass-api.de/api/interpreter','https://overpass.kumi.systems/api/interpreter'):
  try:
   req=urllib.request.Request(endpoint,data=payload,headers={'User-Agent':'JunctionGuide-MVP/1.0','Accept':'application/json'})
   raw.write_bytes(urllib.request.urlopen(req,timeout=120).read());break
  except (urllib.error.URLError,TimeoutError) as error:last_error=error
 else:raise SystemExit(f'Overpass APIから取得できませんでした: {last_error}')
if not raw.exists():raise SystemExit(f'{raw.relative_to(ROOT)} がありません。Overpass APIから取得する場合は --fetch を付けて実行してください。')

d=json.loads(raw.read_text());nodes={str(e['id']):e for e in d['elements'] if e['type']=='node'};ways=[e for e in d['elements'] if e['type']=='way']
def inside(n):return B[0]<=n['lat']<=B[2] and B[1]<=n['lon']<=B[3]
def coord(n):return {'latitude':n['lat'],'longitude':n['lon']}
def distance(a,b):
 r=math.pi/180;x=math.sin((a['lat']-b['lat'])*r/2)**2+math.cos(a['lat']*r)*math.cos(b['lat']*r)*math.sin((a['lon']-b['lon'])*r/2)**2
 return 6371000*2*math.atan2(math.sqrt(x),math.sqrt(max(0,1-x)))

edges=[];adjacency=collections.defaultdict(set)
for w in ways:
 t=w['tags'];layer=t.get('layer','1' if t.get('bridge','no')!='no' else '0')
 if t.get('access') in ('private','no') and t.get('foot') not in ('yes','designated','permissive'):continue
 if t.get('foot') in ('no','private') or layer not in ('0','1') or (layer=='1' and t.get('bridge','no')=='no') or t.get('level','0')!='0' or t.get('tunnel','no')!='no' or t.get('indoor','no')!='no' or t.get('highway') in ('steps','corridor') or t.get('service')=='drive-through' or t.get('area')=='yes':continue
 ids=list(map(str,w['nodes']));direction={'yes':'forward','1':'forward','-1':'backward'}.get(t.get('oneway:foot'),'both')
 for a,b in zip(ids,ids[1:]):
  if a==b or a not in nodes or b not in nodes or not inside(nodes[a]) or not inside(nodes[b]):continue
  length=distance(nodes[a],nodes[b])
  if length<0.05:continue
  edges.append({'id':f'osm:{w["id"]}:{a}:{b}','name':t.get('name',{'footway':'名称未登録の歩行区間','path':'名称未登録の小道','pedestrian':'名称未登録の歩行者道路','service':'名称未登録の通路・構内道路'}.get(t['highway'],'名称未登録の道路')),'from':a,'to':b,'shape':[coord(nodes[a]),coord(nodes[b])],'distance':length,'direction':direction,'conditions':('歩行用OSMデータ。' if t['highway'] in WALK else '車道OSMデータ。歩道の有無・幅・')+'現地接続・横断・利用条件は未確認','sourceID':f'OSM way {w["id"]} version {w.get("version","unknown")}','verification':'現地未確認','layer':t.get('layer','1' if t.get('bridge','no')!='no' else '未記載'),'kind':t['highway']})
  adjacency[a].add(b);adjacency[b].add(a)
if not adjacency:raise SystemExit('対象範囲に利用可能な道路がありません。')
seen=set();components=[]
for node in adjacency:
 if node in seen:continue
 queue=[node];component={node};seen.add(node)
 while queue:
  for neighbor in adjacency[queue.pop()]:
   if neighbor not in seen:seen.add(neighbor);component.add(neighbor);queue.append(neighbor)
 components.append(component)
component=max(components,key=len);edges=[e for e in edges if e['from'] in component and e['to'] in component]
by_node=collections.defaultdict(list)
for edge in edges:by_node[edge['from']].append(edge);by_node[edge['to']].append(edge)
def signature(edge):return (edge['name'],edge['kind'],edge['direction'],edge['layer'],edge['sourceID'])
anchors={node for node,node_edges in by_node.items() if len(node_edges)!=2 or signature(node_edges[0])!=signature(node_edges[1])}
used=set();merged=[]
for edge in edges:
 if edge['id'] in used:continue
 a=edge['from'];b=edge['to'];shape=list(edge['shape']);length=edge['distance'];used.add(edge['id']);base=edge
 if edge['direction']=='both':
  for reverse in (False,True):
   current=a if reverse else b
   while current not in anchors:
    options=[candidate for candidate in by_node[current] if candidate['id'] not in used and signature(candidate)==signature(base)]
    if len(options)!=1:break
    nxt=options[0];used.add(nxt['id']);other=nxt['to'] if nxt['from']==current else nxt['from'];point=coord(nodes[other]);length+=nxt['distance']
    if reverse:shape.insert(0,point);a=other
    else:shape.append(point);b=other
    current=other
 merged.append(dict(base,id=f'osm:{base["sourceID"].split()[2]}:{a}:{b}',**{'from':a,'to':b,'shape':shape,'distance':length}))
active={edge[key] for edge in merged for key in ('from','to')}
places=[{'id':node,'name':'接続点 '+node[-5:],'coordinate':coord(nodes[node])} for node in sorted(active)]
destinations=[]
for identifier,name,lat,lon in region['destinations']:
 node=min(active,key=lambda candidate:distance(nodes[candidate],{'lat':lat,'lon':lon}));candidate_distance=distance(nodes[node],{'lat':lat,'lon':lon})
 if candidate_distance>40:raise SystemExit(f'{name} に40m以内の道路接続点がありません（{candidate_distance:.1f}m）。座標または範囲を確認してください。')
 destinations.append({'id':identifier,'name':name,'nodeID':node,'note':'OSMネットワーク上の実験接続点。施設入口・避難所ではありません。同行者による現地確認が必要です。'})
network={'id':region['network_id'],'name':region['name'],'version':d['osm3s']['timestamp_osm_base'],'bounds':dict(zip(('south','west','north','east'),B)),'source':'© OpenStreetMap contributors / ODbL 1.0','acquiredAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'isSimulated':False,'nodes':places,'edges':merged,'destinations':destinations}
output.write_text(json.dumps(network,ensure_ascii=False,indent=2));query_path.write_text(query+'\n')
print('region:',args.region,'components:',len(components),'nodes:',len(places),'segments:',len(merged))
for destination,definition in zip(destinations,region['destinations']):
 node=nodes[destination['nodeID']];print(destination['name'],destination['nodeID'],f'{distance(node,{"lat":definition[2],"lon":definition[3]}):.1f}m',node['lat'],node['lon'])
