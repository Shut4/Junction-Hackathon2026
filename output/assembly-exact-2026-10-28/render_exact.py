"""Draw a new coordinate-based illustration; no generative-image geometry is used."""
from pathlib import Path
import json, math, hashlib, html
from PIL import Image, ImageDraw, ImageFont
from pypdf import PdfReader

HERE=Path(__file__).resolve().parent
ROOT=HERE.parent.parent
SOURCE=Path('/Users/akiyoshishuta/Documents/開発分/HeroesLeague/細長基板_配置配線図_2026-10-28.pdf')
BASE=ROOT/'output/pdf/ae-d-th-layout-2026-10-28'
assert hashlib.sha256(SOURCE.read_bytes()).digest()==hashlib.sha256((BASE/'細長基板_配置配線図_2026-10-28.pdf').read_bytes()).digest()
data=json.loads((BASE/'配置と配線.json').read_text())
text='\n'.join(p.extract_text() for p in PdfReader(SOURCE).pages)
expected=[('W01','G3','A12'),('W02','G2','A13'),('W03','A5','A15'),('W04','A6','A14'),('W05','A2','外付け'),('W06','G2上面','外付け'),('W07','底面印字','PH 2P'),('W08','底面印字','PH 2P'),('W09','F16','外付け'),('W10','F12','外付け')]
assert [(w['id'],w['a'],w['b']) for w in data['wires']]==expected
for w in data['wires']:assert w['id'] in text
for s in ['G3 → A12','G2 → A13','A5 → A15','A6 → A14','F16 → LRA①','F12 → LRA②','XIAO上面GND → 接点b','BAT+底面','BAT-底面']:
    assert s in text,s

WIDTH,HEIGHT=3600,2530
K=1.5
im=Image.new('RGB',(int(WIDTH*K),int(HEIGHT*K)),'#f3f6f8')
d=ImageDraw.Draw(im)
FONT=BASE/'source/NotoSansJP.ttf'
fonts={}
svg=[]
INK='#183246';GREY='#536a7b';BLUE='#227bab';MUTED='#e4ecf1'
C={'3V3':'#ce3936','GND':'#202c35','SDA':'#087ec2','SCL':'#b28200','BUTTON':'#208b50','BAT+':'#ce3936','BAT-':'#202c35','OUT+':'#c04a9b','OUT-':'#7754b6'}
def font(n):
    if n not in fonts:fonts[n]=ImageFont.truetype(str(FONT),int(n*K))
    return fonts[n]
def scaled(p):return tuple(float(v)*K for v in p)
def rect(b,fill='#ffffff',stroke=None,r=0,width=2):
    bb=scaled(b)
    if r:d.rounded_rectangle(bb,radius=r*K,fill=fill,outline=stroke,width=int(width*K))
    else:d.rectangle(bb,fill=fill,outline=stroke,width=int(width*K))
    svg.append(f'<rect x="{b[0]}" y="{b[1]}" width="{b[2]-b[0]}" height="{b[3]-b[1]}" rx="{r}" fill="{fill or "none"}" stroke="{stroke or "none"}" stroke-width="{width}"/>')
def line(ps,color=INK,width=3,dash=False,halo=False):
    if halo:line(ps,'#ffffff',width+7)
    points=[scaled(p) for p in ps]
    if dash:
        for a,b in zip(ps,ps[1:]):
            length=math.dist(a,b);n=max(1,int(length/12))
            for j in range(0,n,2):
                s=j/n;t=min(j+1,n)/n
                d.line([scaled((a[0]+(b[0]-a[0])*s,a[1]+(b[1]-a[1])*s)),scaled((a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t))],fill=color,width=max(1,int(width*K)))
    else:d.line(points,fill=color,width=max(1,int(width*K)),joint='curve')
    svg.append(f'<polyline points="{" ".join(f"{x},{y}" for x,y in ps)}" fill="none" stroke="{color}" stroke-width="{width}" stroke-linejoin="round" stroke-linecap="round"'+(' stroke-dasharray="12 12"' if dash else '')+'/>')
def poly(ps,fill,stroke=None,width=2):
    d.polygon([scaled(p) for p in ps],fill=fill)
    if stroke:d.line([scaled(p) for p in ps+[ps[0]]],fill=stroke,width=max(1,int(width*K)),joint='curve')
    svg.append(f'<polygon points="{" ".join(f"{x},{y}" for x,y in ps)}" fill="{fill}" stroke="{stroke or "none"}" stroke-width="{width}"/>')
def circ(x,y,r,fill,stroke=None,width=2):
    d.ellipse(scaled((x-r,y-r,x+r,y+r)),fill=fill,outline=stroke,width=max(1,int(width*K)))
    svg.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill or "none"}" stroke="{stroke or "none"}" stroke-width="{width}"/>')
def txt(x,y,s,size=32,color=INK):
    d.text(scaled((x,y)),s,font=font(size),fill=color,anchor='lt')
    svg.append(f'<text x="{x}" y="{y+size*.88}" font-family="Noto Sans JP,Hiragino Sans,sans-serif" font-size="{size}" fill="{color}">{html.escape(s)}</text>')
def lines(x,y,ss,size=30,color=GREY,lead=None):
    for s in ss:txt(x,y,s,size,color);y+=lead or size*1.55
def arrow(ps,color=INK,width=4):
    line(ps,color,width)
    a,b=ps[-2:];angle=math.atan2(b[1]-a[1],b[0]-a[0]);r=14
    poly([b,(b[0]-r*math.cos(angle-.5),b[1]-r*math.sin(angle-.5)),(b[0]-r*math.cos(angle+.5),b[1]-r*math.sin(angle+.5))],color)
def pill(x,y,t,color=INK,size=24):
    w=d.textlength(t,font=font(size))/K+18
    rect((x,y,x+w,y+size+13),'#ffffff','#c5d3dd',7,1)
    txt(x+9,y+4,t,size,color)

P=2.54
def hole(s):return (1.49+'ABCDEFG'.index(s[0])*P,3.18+(int(s[1:])-1)*P)
holes=[cc+str(rr) for cc in 'ABCDEFG' for rr in range(1,18) if cc+str(rr) not in ['G1','G17']]
assert len(holes)==117
u1=data['u1'];u2=data['u2'];allpins=list(u1['pins'].values())+list(u2['pins'].values())
assert len(allpins)==20 and len(set(allpins))==20
assert all(s in holes for s in allpins)
for w in data['wires'][:4]:
    assert tuple(w['path'][0])==hole(w['a']) and tuple(w['path'][-1])==hole(w['b'])

txt(70,55,'配線を再現した完成図',76)
txt(73,155,'添付PDF Rev S1 準拠  /  内部4本 + 外部6本を接続表・穴番号で照合',37,GREY)
txt(73,216,'主基板 18 × 47mm   部品外形 約19.05 × 50.15mm   ／   部品の細部は簡略表示・実機未検証',29,GREY)
for b in [(60,290,1350,1610),(1390,290,2290,1610),(2330,290,3540,1610),(60,1660,3540,2375)]:rect(b,'#ffffff','#d5e1e8',22,2)
txt(95,324,'01  部品面の完成状態',43)
txt(1425,324,'02  はんだ面の正確な配線',38)
txt(2365,324,'03  外部部品との接続',40)

# Exact plan coordinates projected into an isometric view.
def iso(x,y,z=0):return (835+23*x-6.5*y,550+6.5*x+15*y-17*z)
def plane(b,z,fill,stroke=None):
    x0,y0,x1,y1=b
    poly([iso(x0,y0,z),iso(x1,y0,z),iso(x1,y1,z),iso(x0,y1,z)],fill,stroke)
def slab(b,z0,z1,fill,side='#184c53'):
    x0,y0,x1,y1=b
    poly([iso(x1,y0,z0),iso(x1,y1,z0),iso(x1,y1,z1),iso(x1,y0,z1)],side)
    poly([iso(x0,y1,z0),iso(x1,y1,z0),iso(x1,y1,z1),iso(x0,y1,z1)],side)
    plane(b,z1,fill,'#234c57')
def ring(x,y,r,z,fill,stroke=None):
    poly([iso(x+r*math.cos(i*math.tau/40),y+r*math.sin(i*math.tau/40),z) for i in range(40)],fill,stroke,1.5)

# Base silhouette has the exact two half-circle notches, not fictitious holes.
outline=[(0,0),(18,0),(18,.9)]
outline += [(18+1.6*math.cos(-math.pi/2-i*math.pi/24),2.5+1.6*math.sin(-math.pi/2-i*math.pi/24)) for i in range(25)]
outline += [(18,42.9)]
outline += [(18+1.6*math.cos(-math.pi/2-i*math.pi/24),44.5+1.6*math.sin(-math.pi/2-i*math.pi/24)) for i in range(25)]
outline += [(18,47),(0,47)]
poly([iso(x+0.6,y+.6,0) for x,y in outline],'#dce4e8')
slab([0,0,18,47],0,1.6,'#5b9f7c','#386b58')
poly([iso(x,y,1.61) for x,y in outline],'#6bab88','#285d49')
for s in holes:
    x,y=hole(s);ring(x,y,.7,1.63,'#c8bb81');ring(x,y,.36,1.65,'#315747')

# Neutral insulated supports; their exact mechanical details are not specified by the PDF.
for x,y in [(2,5),(15,6),(2,17),(15,18),(2,29),(14,30),(2,43),(14,43)]:
    slab([x-.55,y-.55,x+.55,y+.55],1.6,4.6,'#dfe9ee','#a7bac4')

for module,fill in [(u1,'#263d45'),(u2,'#175474')]:
    for s in module['pins'].values():
        x,y=hole(s);line([iso(x,y,1.6),iso(x,y,4.6)],'#c1a962',8)
    slab(module['bounds'],4.6,6.2,fill,'#173a48')
    for s in module['pins'].values():
        x,y=hole(s);ring(x,y,.66,6.25,'#d8bd70');ring(x,y,.35,6.29,'#dce1e4')

# XIAO solder pad at VBUS exists on the module but no G1 header is fitted.
x,y=hole('G1');ring(x,y,.65,6.25,'#d8bd70');ring(x,y,.33,6.29,'#223842')
slab([2.3,6.0,15.8,16.2],6.2,8.0,'#d4dee1','#859ba4')
for y in [7.2,8.0,8.8]:line([iso(4,y,8.01),iso(12,y,8.01)],'#b1bfc5',2)
slab([4.605,-1.251,13.615,4.50],6.2,9.0,'#bcc9cf','#70858f')
poly([iso(5.4,-1.26,6.9),iso(12.8,-1.26,6.9),iso(12.8,-1.26,8.3),iso(5.4,-1.26,8.3)],'#283e49')
for xx in [6,7.4,8.8,10.2,11.6]:line([iso(xx,-1.28,7.3),iso(xx+.6,-1.28,7.3)],'#c7bb89',2)
line([iso(x,y,6.3) for x,y in [(2.2,18),(5,18),(5,19.7),(8,19.7),(8,18),(11,18),(11,19.7),(14,19.7)]],'#c0a24d',5)

# DRV mount holes: four large 2.5 mm mechanical holes. Electrical pins are elsewhere.
q=u2['bounds']
for x in [q[0]+2.54,q[0]+15.24]:
    for y in [q[1]+2.54,q[1]+22.86]:
        ring(x,y,1.6,6.23,'#d0aa54');ring(x,y,1.25,6.25,'#eaf0f4')
for y in [26.167,46.233]:
    slab([5.2,y-1.25,10.5,y+1.25],6.2,8.5,'#f4f4e9','#b5c2c4')
    plane([6.0,y-.55,9.8,y+.55],8.51,'#c7d0cb')
slab([5.8,33.4,10.0,37.5],6.2,7.2,'#283e4b','#152a34')
for y in [31.0,32.3,39.3,40.6]:
    for x in [4.5,11.0]:slab([x,y,x+1.0,y+.5],6.2,6.55,'#c8c5b1','#868b88')

# Top-side W06: the only button return depicted on the component surface.
g=iso(*hole('G2'),6.35)
line([g,(g[0]+30,g[1]-20),(g[0]+65,g[1]-55)],C['GND'],7,halo=True)
pill(125,580,'G2 上面：W06 → ボタンb',C['GND'],25)
arrow([(615,610),(g[0]+50,g[1]-42)],'#738b99',2)
a2=iso(*hole('A2'),6.35)
line([a2,(a2[0]-60,a2[1]-20)],C['BUTTON'],7,halo=True)
pill(160,458,'A2 / D1：W05 → ボタンa',C['BUTTON'],25)
arrow([(615,480),(a2[0]-65,a2[1]-20)],'#738b99',2)

for label,pos,xy in [
 ('XIAO nRF52840',iso(9,10,8),(125,710)),
 ('DRV2605L / STEMMA QT',iso(8,35,7),(125,1030)),
 ('USB-C',iso(9,-1.25,8),(1030,385)),
]:
    txt(*xy,label,32)
    start=(xy[0]+(400 if xy[0]<500 else 100),xy[1]+40)
    arrow([start,(pos[0]-20,pos[1])],GREY,2)
pill(150,1302,'ピンは XIAO 13本 / DRV 7本',INK,27)
lines(110,1390,[
 'XIAO：A1-A7 / G2-G7。G1はピンなし。',
 'DRV：A12-A16 / F12・F16。大穴は固定用。',
 '白いQTコネクターは2個とも未使用。',
 '内部4線は主基板の裏面 → 右図で確認。',
],29,GREY,45)

# Back view is an exact mirror of the PDF's plan coordinates, no auto-routing.
BX,BY,S=1515,430,23
def back(p):return (BX+(18-p[0])*S,BY+p[1]*S)
rect((BX,BY,BX+18*S,BY+47*S),'#e5f1e8','#5b8a6b',0,3)
for yy in [2.5,44.5]:
    ps=[back((18+1.6*math.cos(-math.pi/2-i*math.pi/30),yy+1.6*math.sin(-math.pi/2-i*math.pi/30))) for i in range(31)]
    line(ps,'#b77859',3)
for col in 'ABCDEFG':
    x,_=back(hole(col+'1'));txt(x-13,BY-50,col,30)
for rr in range(1,18):
    _,y=back(hole('A'+str(rr)));txt(BX+18*S+15,y-15,str(rr),25,GREY)
for s in holes:
    x,y=back(hole(s));circ(x,y,.53*S,'#fffdf7','#aebfae',1.5)
for s in allpins:
    x,y=back(hole(s));circ(x,y,.66*S,'#eeddb6','#9c7b42',2);circ(x,y,.37*S,'#bcc7cf','#86939c',1)

for w in data['wires']:
    if 'path' in w:
        line([back(p) for p in w['path']],C[w['net']],8,halo=True)
        if w['id']=='W10':
            a,b=back(w['path'][-2]),back(w['path'][-1]);t=.75
            xx=a[0]+(b[0]-a[0])*t;yy=a[1]+(b[1]-a[1])*t
            line([(xx,yy-7),(xx,yy+7)],'#ffffff',12)
for w in data['wires'][:4]+data['wires'][8:]:
    for s in [w['a']]+([w['b']] if w['id'] in ['W01','W02','W03','W04'] else []):
        x,y=back(hole(s));circ(x,y,10,C[w['net']],'#ffffff',2)
for n,t,col in [('G3','G3 3V3','3V3'),('G2','G2 GND','GND')]:
    x,y=back(hole(n));pill(1410,y-48,t,C[col],22)
for n,t,col in [('A5','A5 / D4','SDA'),('A6','A6 / D5','SCL'),('A12','A12 / VIN','3V3'),('A13','A13 / GND','GND'),('A14','A14 / SCL','SCL'),('A15','A15 / SDA','SDA')]:
    x,y=back(hole(n));pill(BX+18*S+70,y-17,t,C[col],22)
for n,t,col in [('F12','F12 / OUT-','OUT-'),('F16','F16 / OUT+','OUT+')]:
    x,y=back(hole(n));pill(x+22,y-37,t,C[col],21)
# W05 leaves A2 on the back; W06 explicitly belongs to the other surface.
a=back(hole('A2'));line([a,(a[0]+65,a[1]),(a[0]+65,a[1]+40)],C['BUTTON'],7,halo=True)
circ(*a,10,C['BUTTON'],'#ffffff',2)
pill(1995,550,'W05 → ボタンa',C['BUTTON'],22)
txt(1450,1545,'USB側が上 / 左から G F E D C B A',26,GREY)

# External topology cards. Shapes are symbolic, not invented pad placements.
rect((2360,414,3510,735),'#f5f8fa','#d8e3ea',16)
txt(2385,438,'電池  /  PH 2極コネクター',35)
rect((2400,508,2550,675),'#d8e0e5','#91a2ac',12)
rect((2400,508,2550,535),'#e3bd51',None,8)
txt(2415,555,'LiPo',29);txt(2405,606,'3.7V',27)
line([(2550,565),(2590,565)],C['BAT+'],7)
line([(2550,620),(2590,620)],C['BAT-'],7)
rect((2580,548,2630,641),'#ffffff','#95a7b3',6)
lines(2660,506,['W07 赤：BAT+底面 → PH +','W08 黒：BAT-底面 → PH -','PH極性は電池側を実測照合。','BAT端子の実物位置はPDF未指定。'],27,GREY,46)

rect((2360,765,3510,1100),'#f5f8fa','#d8e3ea',16)
txt(2385,790,'操作ボタン  /  2接点の接続',35)
rect((2410,873,2540,1003),'#293c45','#1d2d35',10)
circ(2475,938,40,'#dc4149','#a01d29',3)
for xx,yy in [(2427,890),(2523,890),(2427,986),(2523,986)]:circ(xx,yy,8,'#85949b')
lines(2620,858,['W05 緑：A2 [D1] → 接点a','W06 黒：G2 上面 → 接点b','離すと開放、押すと導通。','PDFの指定どおりGNDは上面から。'],28,GREY,47)

rect((2360,1130,3510,1484),'#f5f8fa','#d8e3ea',16)
txt(2385,1155,'LRA振動子  /  LD14-002',35)
rect((2405,1233,2550,1365),'#cbd5dc','#8d9fa9',12)
rect((2420,1248,2535,1350),'#dce4e9','#a7b5bd',8)
lines(2610,1223,['W09 紫：F16 [OUT+] → ①','W10 紫・印付き：F12 [OUT-] → ②','OUT+ / OUT-はGNDへ接続しない。','⑤⑥ケース端子は未接続。'],27,GREY,47)
lines(2385,1510,['外部部品の固定位置・電線長・BAT端子座標はPDF未指定。','この欄は接続関係を示す。形状・縮尺・取付位置は概略。'],25,GREY,40)

# Ten exact endpoint records, including the top-surface GND exception.
txt(100,1695,'接続照合  10 / 10',43)
txt(570,1704,'交差部は非接続。被覆付きAWG26の両端だけをはんだづけ。',31,GREY)
rows=[
 ('W01','3V3','G3  XIAO 3V3','A12  DRV VIN'),
 ('W02','GND','G2  XIAO GND','A13  DRV GND'),
 ('W03','SDA','A5  XIAO D4','A15  DRV SDA'),
 ('W04','SCL','A6  XIAO D5','A14  DRV SCL'),
 ('W05','BUTTON','A2  XIAO D1','ボタン接点a'),
 ('W06','GND','G2 上面  XIAO GND','ボタン接点b'),
 ('W07','BAT+','XIAO BAT+ 底面','PH 電池+実測側'),
 ('W08','BAT-','XIAO BAT- 底面','PH 電池-実測側'),
 ('W09','OUT+','F16  DRV OUT+','LRA ①'),
 ('W10','OUT-','F12  DRV OUT-','LRA ②'),
]
for k,(ident,net,src,dst) in enumerate(rows):
    xx=100 if k<5 else 1840;yy=1795+(k%5)*99
    line([(xx,yy+21),(xx+62,yy+21)],C[net],9)
    txt(xx+83,yy,ident,31,C[net]);txt(xx+210,yy,src+'  →  '+dst,29)
    line([(xx,yy+72),(xx+1580,yy+72)],'#e3eaf0',2)
txt(75,2414,'PDFで指定された穴・接続・内部配線経路を再現。部品のSMD細部・支持具・外部部品の配置は簡略表示。',30,GREY)
txt(75,2464,'資料の再現図であり、組立・充電・LRA駆動・収納の実機検証を示すものではありません。',28,GREY)

png=HERE/'完成図_PDF配線準拠_2026-10-28.png'
im.resize((WIDTH,HEIGHT),Image.Resampling.LANCZOS).save(png,dpi=(300,300))
(HERE/'完成図_PDF配線準拠_2026-10-28.svg').write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" viewBox="0 0 {WIDTH} {HEIGHT}"><rect width="100%" height="100%" fill="#f3f6f8"/>'+''.join(svg)+'</svg>')
checks={'source_pdf':str(SOURCE),'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'pdf_matches_geometry_source':True,'wire_count':10,'internal_route_count':4,'usable_holes':117,'header_pins':20,'mirrored_view':'x_back = 18.0 - x_front; row numbers unchanged','all_wire_endpoints_match_pdf':True,'all_internal_paths_reused_without_rerouting':True,'not_specified_in_pdf':['BAT bottom pad coordinates','external component mounting positions and wire lengths','exact SMD body details and support shapes'],'physical_verification':False,'output_png':str(png)}
(HERE/'照合記録.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2))
print(json.dumps(checks,ensure_ascii=False))
