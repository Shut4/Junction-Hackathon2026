#!/usr/bin/env python3
"""Build a saved, ground-level OSM walking network for one supported region."""
import argparse, urllib.request, urllib.parse, urllib.error, json, math, collections, pathlib, datetime, shutil, hashlib

ROOT=pathlib.Path(__file__).resolve().parent.parent
from region_data import load_regions, validate_network, validate_raw, summarize_update, write_json
REGIONS=load_regions(ROOT/'Data/regions.json')
WALK={'footway','path','pedestrian','steps','corridor'}
ROAD={'living_street','residential','service','unclassified','tertiary','tertiary_link','secondary','secondary_link','primary','primary_link','track'}

parser=argparse.ArgumentParser()
parser.add_argument('--region',choices=REGIONS,default='kokura')
parser.add_argument('--check',action='store_true',help='validate all catalogued networks without modifying files')
parser.add_argument('--output',type=pathlib.Path,help='write a validated candidate to this path before deployment')
parser.add_argument('--fetch',action='store_true',help='archive existing files and fetch fresh OSM data')
args=parser.parse_args()
if args.check:
 for key,definition in REGIONS.items():
  path=ROOT/f'Data/{key}-network.json'
  validate_network(json.loads(path.read_text()),definition)
  print(f'{key}: valid')
 raise SystemExit(0)
region=REGIONS[args.region];B=tuple(region['bounds'][key] for key in ('south','west','north','east'))
raw=ROOT/f'Data/raw/{args.region}-osm.json';query_path=ROOT/f'Data/raw/{args.region}-query.txt';output=ROOT/f'Data/{args.region}-network.json'
metadata_path=ROOT/f'Data/raw/{args.region}-metadata.json'
query='[out:json][timeout:60];way["highway"~"^('+'|'.join(sorted(WALK|ROAD))+')$"]('+','.join(map(str,B))+');out meta;>;out skel qt;'

def archive_existing():
 stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H-%M-%S-%fZ');archive=ROOT/'Data/archive';archive.mkdir(parents=True,exist_ok=True)
 for path in (raw,query_path,metadata_path,output):
  if path.exists():shutil.copy2(path,archive/f'{path.stem}-{stamp}{path.suffix}')

if args.fetch:
 archive_existing();raw.parent.mkdir(parents=True,exist_ok=True)
 payload=urllib.parse.urlencode({'data':query}).encode();last_error=None
 for endpoint in ('https://overpass.private.coffee/api/interpreter','https://lz4.overpass-api.de/api/interpreter','https://overpass-api.de/api/interpreter','https://overpass.kumi.systems/api/interpreter'):
  try:
   req=urllib.request.Request(endpoint,data=payload,headers={'User-Agent':'JunctionGuide-MVP/1.0','Accept':'application/json'})
   body=urllib.request.urlopen(req,timeout=120).read();response=json.loads(body);timestamp=response.get('osm3s',{}).get('timestamp_osm_base')
   if not timestamp:raise ValueError('OSM基準時刻がありません')
   base_time=datetime.datetime.fromisoformat(timestamp.replace('Z','+00:00'));age=datetime.datetime.now(datetime.timezone.utc)-base_time
   if age>datetime.timedelta(days=14):raise ValueError(f'OSM基準時刻が古すぎます（{timestamp}）')
   validate_raw(response)
   write_json(raw,response)
   write_json(metadata_path,{'fetchedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'endpoint':endpoint,'osmTimestamp':timestamp,'rawSHA256':hashlib.sha256(raw.read_bytes()).hexdigest(),'license':region['license'],'bounds':region['bounds']})
   query_path.write_text(query+'\n')
   break
  except (urllib.error.URLError,TimeoutError,json.JSONDecodeError,ValueError) as error:last_error=error
 else:raise SystemExit(f'Overpass APIから取得できませんでした: {last_error}')
if not raw.exists():raise SystemExit(f'{raw.relative_to(ROOT)} がありません。Overpass APIから取得する場合は --fetch を付けて実行してください。')

d=json.loads(raw.read_text());validate_raw(d);nodes={str(e['id']):e for e in d['elements'] if e['type']=='node'};ways=[e for e in d['elements'] if e['type']=='way']
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
component_sizes=sorted((len(item) for item in components),reverse=True);component=max(components,key=len)
edges_before_component_filter=len(edges);edges=[e for e in edges if e['from'] in component and e['to'] in component]
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
for definition in region['destinations']:
 identifier,name,lat,lon=(definition[k] for k in ('id','name','latitude','longitude'))
 node=min(active,key=lambda candidate:distance(nodes[candidate],{'lat':lat,'lon':lon}));candidate_distance=distance(nodes[node],{'lat':lat,'lon':lon})
 if candidate_distance>40:raise SystemExit(f'{name} に40m以内の道路接続点がありません（{candidate_distance:.1f}m、最寄り {nodes[node]["lat"]},{nodes[node]["lon"]}）。座標または範囲を確認してください。')
 destinations.append({'id':identifier,'name':name,'nodeID':node,'note':'OSMネットワーク上の実験接続点。施設入口・避難所ではありません。同行者による現地確認が必要です。'})
network={'id':region['networkID'],'name':region['name'],'version':d['osm3s']['timestamp_osm_base'],'bounds':dict(zip(('south','west','north','east'),B)),'source':'© OpenStreetMap contributors / ODbL 1.0','acquiredAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'isSimulated':False,'nodes':places,'edges':merged,'destinations':destinations}
# Include the graph content in the version: conversion changes with the same OSM
# timestamp must still trigger the existing report migration gate.
fingerprint=hashlib.sha256(json.dumps([network[k] for k in ('id','bounds','nodes','edges','destinations')],ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest()
network['version'] += '+'+fingerprint[:16]
raw_hash=hashlib.sha256(raw.read_bytes()).hexdigest()
metadata=json.loads(metadata_path.read_text()) if metadata_path.exists() else {}
verified_metadata=metadata if metadata.get('rawSHA256') == raw_hash else {}
network['provenance']={'sourceURL':region['sourceURL'],'license':region['license'],'osmTimestamp':d['osm3s']['timestamp_osm_base'],'rawSHA256':raw_hash,'converterVersion':1,'fetchedAt':verified_metadata.get('fetchedAt'),'endpoint':verified_metadata.get('endpoint')}

validate_network(network,region)
if output.exists(): print(json.dumps(summarize_update(json.loads(output.read_text()),network),ensure_ascii=False))
if args.output:
 write_json(args.output,network)
else:
 if not args.fetch: archive_existing()
 write_json(output,network);query_path.write_text(query+'\n')
print('region:',args.region,'components:',len(components),'component_nodes:',component_sizes[:10],'discarded_edges:',edges_before_component_filter-len(edges),'nodes:',len(places),'segments:',len(merged))
for destination,definition in zip(destinations,region['destinations']):
 node=nodes[destination['nodeID']]
 gap=distance(node,{'lat':definition['latitude'],'lon':definition['longitude']})
 print(destination['name'],destination['nodeID'],f'{gap:.1f}m',node['lat'],node['lon'])
