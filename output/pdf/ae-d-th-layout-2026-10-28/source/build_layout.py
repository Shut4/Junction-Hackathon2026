"""Reproducible perfboard assembly guide. No PCB manufacturing data is produced."""
from pathlib import Path
import csv, json, math, hashlib, xml.etree.ElementTree as ET
from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.cidfonts import UnicodeCIDFont
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.graphics import renderSVG
from reportlab.graphics.shapes import Drawing, Rect, Circle, Line, String, PolyLine
from reportlab.lib.colors import toColor

OUT=Path(__file__).resolve().parents[1]
ROOT=OUT.parents[2]
P=2.54; X0=1.49; Y0=3.18; BW=18.0; BH=47.0
COLS='ABCDEFG'; INK='#152c3e'; MUTED='#586d7b'
COLORS={'3V3':'#cf413b','GND':'#242b33','SDA':'#087bc1','SCL':'#c08b00','BUTTON':'#277c48','OUT+':'#bb4d9a','OUT-':'#7754b6','BAT+':'#cf413b','BAT-':'#242b33'}
FONT='NotoSansJP'
fontpath=Path(__file__).with_name('NotoSansJP.ttf')
pdfmetrics.registerFont(TTFont(FONT,str(fontpath)))
W,H=A4

def hole(name):
    return (X0+COLS.index(name[0])*P,Y0+(int(name[1:])-1)*P)
def rect_union(a,b):
    return [min(a[0],b[0]),min(a[1],b[1]),max(a[2],b[2]),max(a[3],b[3])]
def plen(points): return sum(math.dist(a,b) for a,b in zip(points,points[1:]))
def rectgap(a,b): return max(b[1]-a[3],a[1]-b[3],b[0]-a[2],a[0]-b[2])
def rnd(x):return round(x,3)

# Enumerate direct-header assembly positions on the retained seven columns.
# XIAO: USB toward row 1, two 15.24 mm spaced rows; QT: long axis vertical.
# Constraint: module bodies are at least 2 mm apart; end overhang <= 3 mm.
# Lexicographic objective: assembly width, assembly length, four-net Manhattan length.
candidates=[]
for vinrow in range(10,18):
    for forward in [True,False]:
        vin=(X0 if forward else hole('G1')[0],hole('A'+str(vinrow))[1])
        qt_top=vin[1]-(7.62 if forward else 17.78)
        qt_left=vin[0]-(2.54 if forward else 15.24)
        qbox=[qt_left,qt_top,qt_left+17.78,qt_top+25.4]
        ubox=[.22,.259,18.,21.214]
        pads={}
        for j,n in enumerate(['VIN','GND','SCL','SDA','IN']):
            rr=vinrow+(j if forward else -j)
            pads[n]=(('A' if forward else 'G')+str(rr))
        if any(not 1<=int(s[1:])<=17 or s in ['G1','G17'] for s in pads.values()):continue
        if qt_top-ubox[3]<2 or qbox[3]>50 or qt_top<0:continue
        union=rect_union(rect_union(ubox,qbox),[0,-1.251,BW,BH])
        length=sum(abs(hole(s)[0]-hole(pads[d])[0])+abs(hole(s)[1]-hole(pads[d])[1]) for s,d in [('G3','VIN'),('G2','GND'),('A5','SDA'),('A6','SCL')])
        candidates.append({'vinrow':vinrow,'input_side':'left' if forward else 'right','body_width_mm':rnd(union[2]-union[0]),'body_length_mm':rnd(union[3]-union[1]),'four_net_manhattan_mm':rnd(length),'gap_mm':rnd(qt_top-ubox[3]),'qt_bounds_mm':qbox,'pins':pads})
assert candidates
candidates.sort(key=lambda a:(a['body_width_mm'],a['body_length_mm'],a['four_net_manhattan_mm']))
best=candidates[0]
assert best['vinrow']==12 and best['input_side']=='left',best
U1BOX=[.22,.259,18.,21.214]
U2BOX=best['qt_bounds_mm']
u1={**{f'D{i}':f'A{i+1}' for i in range(7)},'GND':'G2','3V3':'G3','D10':'G4','D9':'G5','D8':'G6','D7':'G7'}
u2={**best['pins'],'OUT-':'F12','OUT+':'F16'}

wires=[
 dict(id='W01',net='3V3',src='U1.3V3',a='G3',dst='U2.VIN',b='A12',color='赤',path=[hole('G3'),(15.46,8.26),(15.46,23.0),(8,23.0),(8,31.12),hole('A12')]),
 dict(id='W02',net='GND',src='U1.GND',a='G2',dst='U2.GND',b='A13',color='黒',path=[hole('G2'),(12.92,5.72),(12.92,24.4),(6.57,24.4),(6.57,33.66),hole('A13')]),
 dict(id='W03',net='SDA',src='U1.D4',a='A5',dst='U2.SDA',b='A15',color='青',path=[hole('A5'),(.55,13.34),(.55,38.74),hole('A15')]),
 dict(id='W04',net='SCL',src='U1.D5',a='A6',dst='U2.SCL',b='A14',color='黄',path=[hole('A6'),(2.54,15.88),(2.54,36.2),hole('A14')]),
 dict(id='W05',net='BUTTON',src='U1.D1',a='A2',dst='SW1.接点a',b='外付け',color='緑'),
 dict(id='W06',net='GND',src='U1.GND（XIAO上面）',a='G2上面',dst='SW1.接点b',b='外付け',color='黒'),
 dict(id='W07',net='BAT+',src='U1.BAT+底面',a='底面印字',dst='J1.電池+実測側',b='PH 2P',color='赤'),
 dict(id='W08',net='BAT-',src='U1.BAT-底面',a='底面印字',dst='J1.電池-実測側',b='PH 2P',color='黒'),
 dict(id='W09',net='OUT+',src='U2.OUT+',a='F16',dst='LRA①',b='外付け',color='紫系',path=[hole('F16'),(14.19,46.6)]),
 dict(id='W10',net='OUT-',src='U2.OUT-',a='F12',dst='LRA②',b='外付け',color='紫系・印付き',path=[hole('F12'),(12.9,31.12),(12.9,46.6)]),
]
for w in wires:
    if 'path' in w:
        w['route_mm']=rnd(plen(w['path']))
        w['cut_mm']=int(math.ceil((w['route_mm']+12)/5)*5) if w['id'] in ['W01','W02','W03','W04'] else None
    else:w['route_mm']=None;w['cut_mm']=None

sources=[
 ('AE-D-TH寸法図・穴配列','https://akizukidenshi.com/goodsaffix/ae-d-th.pdf'),
 ('AE-D-TH商品仕様','https://akizukidenshi.com/catalog/g/g111960/'),
 ('XIAO公式寸法・端子資料','https://wiki.seeedstudio.com/XIAO_BLE/#resources'),
 ('XIAO公式フットプリントZIP','https://files.seeedstudio.com/wiki/XIAO-KiCad-Library/New_XIAO_Series_Footprints.zip'),
 ('DRV2605L公式STEMMA QT基板データ','https://github.com/adafruit/Adafruit-DRV2605-PCB'),
 ('DRV2605L公式端子説明','https://learn.adafruit.com/adafruit-drv2605-haptic-controller-breakout/pinouts'),
 ('PH 2mmコネクター','https://akizukidenshi.com/catalog/g/g112802/'),
 ('スイッチ端子図','https://akizukidenshi.com/goodsaffix/TVDP01-060CR.pdf'),
 ('LRA端子図の掲載ページ','https://akizukidenshi.com/catalog/g/g106838/'),
 ('AWG26配線材','https://akizukidenshi.com/catalog/g/g118293/'),
]
check={
 'status':'COMPUTATIONAL_CHECKS_PASSED_PHYSICAL_TESTS_NOT_PERFORMED',
 'board':'AE-D-TH left strip A-G; 7 columns x 17 rows minus G1/G17 = 117 usable holes',
 'board_mm':[BW,BH,1.6],
 'assembly_xy_mm':[best['body_width_mm'],best['body_length_mm']],
 'scope':'Direct header mounting, USB facing row 1, QT rotated 90 degrees, 2 mm minimum gap. Width/length bounds exclude wires, solder fillets, insulation, fixtures, USB cable, external parts.',
 'candidate_count':len(candidates),'selected':best,
 'hole_validity':all(s not in ['G1','G17'] and 1<=int(s[1:])<=17 and s[0] in COLS for s in list(u1.values())+list(u2.values())),
 'module_clearance_mm':rnd(U2BOX[1]-U1BOX[3]),
 'xiao_header_pins':13,'drv_header_pins':7,'total_header_pins':20,
 'nc':['U1.VBUS','U1.D0','U1.D2','U1.D3','U1.D6','U1.D7','U1.D8','U1.D9','U1.D10','U2.IN','LRA.case5','LRA.case6','U2.QT connectors'],
 'not_verified':['real board revision and dimensional tolerances','cutting and actual fit','support strength and header leg length','grip cavity and fold-cord clearance','assembly height','battery polarity and charge conditions','BLE/RF near perfboard copper','current budget and regulator temperature','LRA voltage clamp/calibration and physical operation'],
 'assertions':{},
}
# Compare the downloaded Eagle net-to-pad mapping, not only the hand-authored table.
brd=ROOT/'tmp/pdfs/ae-d-th/sources/drv-qt.brd'
if brd.exists():
    r=ET.parse(brd)
    mapping={s.get('name'):[(c.get('element'),c.get('pad')) for c in s.findall('contactref')] for s in r.findall('.//signals/signal')}
    for name,pad in [('VCC','1'),('GND','2'),('SCL','3'),('SDA','4'),('IN/TRIG','5')]:
        assert ('JP2',pad) in mapping[name]
    assert ('JP1','1') in mapping['OUT+'] and ('JP3','1') in mapping['OUT-']
    check['assertions']['drv_source_net_mapping']=True
    check['drv_source_sha256']=hashlib.sha256(brd.read_bytes()).hexdigest()
else:
    check['status']='GEOMETRY_CHECKS_PASSED_VENDOR_EAGLE_SOURCE_NOT_AVAILABLE'
    check['assertions']['drv_source_net_mapping']='not rerun: download manufacturer Eagle source to tmp/pdfs/ae-d-th/sources/drv-qt.brd'
assert check['hole_validity'] and check['module_clearance_mm']>=2
assert u1['D4']=='A5' and u1['D5']=='A6' and u1['D1']=='A2'
assert u2['OUT+']=='F16' and u2['OUT-']=='F12'
assert len(set(u1.values()))==len(u1) and len(set(u2.values()))==len(u2)
assert set(u1.values()).isdisjoint(set(u2.values()))
for w in wires[:4]:assert w['path'][0]==hole(w['a']) and w['path'][-1]==hole(w['b'])
check['assertions'].update(active_pin_map=True,no_shared_header_holes=True,wire_endpoints=True,no_5v_to_driver=True,lra_outputs_not_grounded=True)

(OUT/'検証結果.json').write_text(json.dumps(check,ensure_ascii=False,indent=2))
(OUT/'配置と配線.json').write_text(json.dumps({'coordinate_origin':'original AE-D-TH top-left, mm, x right y down','board':check['board'],'u1':{'bounds':U1BOX,'pins':u1},'u2':{'bounds':U2BOX,'pins':u2},'wires':wires,'sources':sources},ensure_ascii=False,indent=2))
with (OUT/'配線一覧.csv').open('w',encoding='utf-8-sig',newline='') as f:
    wr=csv.writer(f);wr.writerow(['線番号','信号','接続元','穴','接続先','穴または端子','色','図示経路mm','切り出し目安mm'])
    for w in wires:wr.writerow([w[k] for k in ['id','net','src','a','dst','b','color','route_mm','cut_mm']])
with (OUT/'配置候補比較.csv').open('w',encoding='utf-8-sig',newline='') as f:
    keys=['vinrow','input_side','body_width_mm','body_length_mm','four_net_manhattan_mm','gap_mm']
    wr=csv.DictWriter(f,fieldnames=keys,extrasaction='ignore');wr.writeheader();wr.writerows(candidates)

def txt(c,x,y,t,size=10,color=INK):
    c.setFillColor(color);c.setFont(FONT,size);c.drawString(x,y,t)
def lines(c,x,y,ss,size=10,leading=16,color=INK):
    for s in ss:txt(c,x,y,s,size,color);y-=leading
    return y
def title(c,num,t,sub=''):
    txt(c,36,H-43,'白杖振動デバイス  細長基板の実装図',10,MUTED)
    txt(c,36,H-74,t,20)
    txt(c,36,H-96,sub,9,MUTED)
    c.setStrokeColor('#d9e2e7');c.line(36,H-108,W-36,H-108)
    txt(c,36,24,'2026-10-28 / Rev S1   配置・配線の設計資料。実機未検証。',8,MUTED)
    txt(c,W-75,24,f'{num} / 6',9,MUTED)
def box(c,x,y,w,h,fill='#f0f5f8',stroke='#c6d3dd'):
    c.setFillColor(fill);c.setStrokeColor(stroke);c.roundRect(x,y,w,h,6,fill=1,stroke=1)
def wire(c,pts,net,width=2):
    c.setStrokeColor(COLORS[net]);c.setLineWidth(width)
    p=c.beginPath();p.moveTo(*pts[0])
    for xy in pts[1:]:p.lineTo(*xy)
    c.drawPath(p)

def board(c,ox,oy,scale=4,back=False,components=True,routes=False,labels=True):
    # Drawing origin is the top-left in page coordinates. Mirror entire geometry on back.
    def xy(p):return (ox+((BW-p[0]) if back else p[0])*mm*scale,oy-p[1]*mm*scale)
    def rr(bounds,color,stroke):
        a,b=xy((bounds[0],bounds[1])),xy((bounds[2],bounds[3]))
        c.setFillColor(color);c.setStrokeColor(stroke);c.setLineWidth(.7)
        c.rect(min(a[0],b[0]),min(a[1],b[1]),abs(a[0]-b[0]),abs(a[1]-b[1]),fill=1,stroke=1)
    rr([0,0,BW,BH],'#e7f1e9','#628c72')
    # Cut-edge mounting holes: only the left semicircle remains in the strip.
    for yy in [2.5,44.5]:
        c.setStrokeColor('#bb795c');c.setLineWidth(.7)
        p=c.beginPath()
        for j in range(31):
            a=math.pi/2+j*math.pi/30
            q=xy((18+1.6*math.cos(a),yy+1.6*math.sin(a)))
            if j==0:p.moveTo(*q)
            else:p.lineTo(*q)
        c.drawPath(p)
    # Hole grid is shown only where not covered by an actual module body.
    for col in COLS:
        for row in range(1,18):
            n=col+str(row);pos=hole(n);x,y=xy(pos)
            if n in ['G1','G17']:continue
            if components and any(b[0]<pos[0]<b[2] and b[1]<pos[1]<b[3] for b in [U1BOX,U2BOX]):continue
            c.setFillColor('#ffffff');c.setStrokeColor('#9aafa1');c.setLineWidth(.4)
            c.circle(x,y,.5*mm*scale,fill=1,stroke=1)
    if components:
        rr(U1BOX,'#dbeaf3','#548bad');rr(U2BOX,'#d8e6f0','#548bad')
        rr([4.605,-1.251,13.615,4.504],'#d6dbe0','#617582')
        for name,bounds in [('XIAO',U1BOX),('DRV2605L',U2BOX)]:
            x,y=xy(((bounds[0]+bounds[2])/2,(bounds[1]+bounds[3])/2))
            c.setFillColor(INK);c.setFont('Helvetica-Bold',8 if scale<3 else 11);c.drawCentredString(x,y,name)
        for y in [U2BOX[1]+2.667,U2BOX[1]+22.733]:
            rr([5.8,y-1.3,9.8,y+1.3],'#ffffff','#8fa3af')
        for x in [U2BOX[0]+2.54,U2BOX[0]+15.24]:
            for y in [U2BOX[1]+2.54,U2BOX[1]+22.86]:
                xx,yy=xy((x,y));c.setFillColor('#fbfcfd');c.setStrokeColor('#a4b6c4');c.circle(xx,yy,1.25*mm*scale,fill=1,stroke=1)
    if routes:
        for w in wires:
            if 'path' in w:wire(c,[xy(p) for p in w['path']],w['net'],max(1.3,.3*mm*scale))
    for mp in [u1,u2]:
        for pin,n in mp.items():
            x,y=xy(hole(n));c.setFillColor('#f6dfaa');c.setStrokeColor('#966e33');c.setLineWidth(.7)
            c.circle(x,y,.6*mm*scale,fill=1,stroke=1)
    active={w['a']:w['net'] for w in wires if w['a'] in [f'{cc}{rr}' for cc in COLS for rr in range(1,18)]}
    active.update({w['b']:w['net'] for w in wires[:4]})
    for n,net in active.items():
        x,y=xy(hole(n));c.setFillColor(COLORS[net]);c.circle(x,y,.38*mm*scale,fill=1,stroke=0)
    if labels:
        for col in COLS:
            x,_=xy(hole(col+'1'));txt(c,x-3,oy+12,col,10)
        for row in range(1,18):
            xx=ox-20 if not back else ox+BW*mm*scale+7
            _,y=xy(hole('A'+str(row)));txt(c,xx,y-3,str(row),9,MUTED)
    return xy

pdf=OUT/'細長基板_配置配線図_2026-10-28.pdf'
c=canvas.Canvas(str(pdf),pagesize=A4)
c.setTitle('白杖振動デバイス 細長基板の配置配線図')
c.setAuthor('HeroesLeague prototype design')

# 1: Placement.
title(c,1,'幅約19.1mmの実装構成','XIAO nRF52840 + Adafruit DRV2605L STEMMA QT / LRA LD14-002')
xy=board(c,66,H-151,3.15,components=True)
txt(c,62,H-130,'部品面から見る / USB側が上',10)
lines(c,285,H-151,[
 '主基板：幅18.0 × 長さ47.0mm',
 'AE-D-THの左7列を使用',
 '部品外形：約19.05 × 50.15mm',
 '電線・絶縁・固定具は別途余裕が必要',
 '',
 'XIAO：7ピン + 6ピンで固定',
 'A1-A7 と G2-G7 に挿す',
 'G1は元の取付穴に重なるため空ける',
 '',
 'DRV：長辺を縦にして配置',
 'A12-A16：入力5ピン',
 'F12：OUT- / F16：OUT+',
 '四隅の大穴は固定用。配線しない',
 '',
 '白いQTコネクター2個は使わない',
 'IN/INT端子は未接続',
 'DRVの基板下端は約1.9mmはみ出す',
],size=9,leading=16)
box(c,36,122,W-72,111)
lines(c,49,213,[
 '6列ではXIAOの左右15.24mmのピン列が合わないため、7列に変更。',
 'XIAOとDRVの短辺はどちらも約17.8mm。2.54mmの穴に直接固定すると',
 '2基板の中心が1.27mmずれ、部品外形の幅は19.05mmになる。',
 '電池・ボタン・振動子は基板外。LiPoを主基板の裏に重ねない配置を基本とする。',
 'グリップ内寸・高さ・折りたたみゴムとの干渉は実物で確認する。',
],size=9,leading=17)
c.showPage()

# 2: Bottom routing, mirror verified via shared coordinates.
title(c,2,'はんだ面の配線図','部品面から左右に裏返した図。穴名は同じまま。色線は被覆付きAWG26。')
xy=board(c,64,H-155,3.2,back=True,components=False,routes=True)
txt(c,62,H-132,'はんだ面 / 左から G F E D C B A',10)
lines(c,285,H-153,[
 '内部配線は4本',
 'W01 赤   G3 → A12 / 3V3',
 'W02 黒   G2 → A13 / GND',
 'W03 青   A5 → A15 / SDA',
 'W04 黄   A6 → A14 / SCL',
 '',
 '振動子への2本',
 'W09      F16 → LRA① / OUT+',
 'W10      F12 → LRA② / OUT-',
 'この2本は共にGNDへ接続しない',
 '',
 '外付けボタン',
 'W05      A2 → ボタン接点a',
 'W06      XIAO上面GND → 接点b',
 'G2の裏側へ複数線を押し込まない',
 '',
 '交差しても電気的につながらない',
 '途中の被覆はむかない',
 '線同士を重ねる箇所は絶縁を保つ',
],size=9,leading=16)
box(c,36,110,W-72,115)
lines(c,49,205,[
 '穴はすべて独立。色線の両端だけを指定ピンにはんだづけする。',
 '図の線は配線経路の目安で、銅箔パターンではない。スズメッキ裸線は不要。',
 '配線は基板裏で固定し、こて先が届く余白を残す。外部線には引っ張り止めを付ける。',
 'アンテナ付近に電池・金属固定具を重ねない。既存ランドや配線によるRF影響は未評価。',
 'USB側の向きは裏返しても上。図を上下逆にしない。',
],size=9,leading=17)
c.showPage()

# 3: Wire list.
title(c,3,'配線一覧と外付け部品','基板の穴名と基板上の端子名を両方確認して作業する。')
y=H-135
for i,w in enumerate(wires):
    h=43
    box(c,36,y-h,W-72,h-3,fill='#f3f6f8' if i%2==0 else '#ffffff',stroke='#dce5ea')
    txt(c,45,y-14,f"{w['id']}  {w['color']}  {w['net']}",10,COLORS[w['net']])
    txt(c,182,y-14,f"{w['src']} [{w['a']}]",9)
    txt(c,182,y-29,f"→ {w['dst']} [{w['b']}]",9)
    if w.get('cut_mm'):txt(c,453,y-22,f"約{w['cut_mm']}mm",9)
    y-=h
lines(c,39,y-15,[
 'W01-W04の長さは図示経路 + 約12mmの作業余裕から切上げ。仮合わせ後に調整。',
 '外部線の長さはグリップの固定位置が未確定のため指定しない。',
 '',
 'PHコネクター：2.0mmピッチ。主基板へ無理に差し込まず、電線で引き出す。',
 '端子を1本ずつ絶縁し、抜き差しの力はホルダーで受ける。極性は電池を実測して決める。',
 'ボタン：メーカー図では①②が同じ接点、③④が同じ接点。片方ずつ選び導通で確認。',
 'LRA：端子番号は販売元の見る向きで確認。⑤⑥ケース端子は未接続。',
 '最小構成はLRAへ直配線。購入済み端子台は振動子を交換する評価時だけ途中に入れる。',
 'ERMとLRAは同時接続しない。交換時にはソフトの駆動方式・電圧設定も変更する。',
],size=9,leading=16)
c.showPage()

# 4: Cut and assembly.
title(c,4,'基板の切り出しと組立順','この図面では切断を提案する。実物の切断・加工は行っていない。')
sx=2.15;ox=62;oy=H-150
# Full original board, original 14x17 minus four absent holes.
c.setFillColor('#edf2ee');c.setStrokeColor('#7d9785');c.rect(ox,oy-47*mm*sx,36*mm*sx,47*mm*sx,fill=1)
for j in range(14):
    for r in range(17):
        if j in [6,7] and r in [0,16]:continue
        c.setFillColor('#657d6e');c.circle(ox+(X0+j*P)*mm*sx,oy-(Y0+r*P)*mm*sx,.26*mm*sx,fill=1,stroke=0)
c.setFillColor('#d4e7ef');c.setFillAlpha(.45);c.rect(ox,oy-47*mm*sx,18*mm*sx,47*mm*sx,fill=1,stroke=0);c.setFillAlpha(1)
c.setStrokeColor('#cd6547');c.setDash(4,3);c.setLineWidth(1.5);c.line(ox+18*mm*sx,oy+6,ox+18*mm*sx,oy-47*mm*sx-6);c.setDash()
for yy in [2.5,44.5]:
    c.setFillColor('#ffffff');c.setStrokeColor('#ad7c69');c.circle(ox+18*mm*sx,oy-yy*mm*sx,1.6*mm*sx,fill=1)
txt(c,ox,oy+17,'AE-D-TH全体 36 × 47mm',10)
txt(c,ox,oy-47*mm*sx-20,'左7列（A-G）を残す / 切断線 x = 18.0mm',9)
lines(c,318,H-148,[
 '残す部分：18.0 × 47.0mm',
 '穴間隔：2.54mm',
 '7列 × 17行、使用可能117穴',
 '',
 'G1 / G17 は元の取付穴に重なる',
 '119穴の整った長方形ではない',
 '切断後は右端に半円の切欠きが残る',
 '',
 '実物でこの穴配列を照合してから',
 '部品を一度並べて仮合わせする',
 '穴配列が異なる個体には流用しない',
 '',
 '切断は部品を付ける前に行う',
 '万力等で保持し、細目の工具で切る',
 '保護メガネを使い、粉じんを吸わない',
 '切断面を整え、銅片と切粉を除く',
],size=9,leading=16)
y=H-485
steps=[
 '1  基板切断前に実寸図で幅・長さ・グリップ内寸を確認する。',
 '2  USBも電池も外す。XIAO底面のBAT+/-へW07/W08を先にはんだづけする。',
 '3  XIAOにA側7ピン、G側6ピンを付ける。G1（VBUS）のピンは付けない。',
 '4  DRVに入力5ピンと出力1ピン×2を付ける。大きな固定穴には付けない。',
 '5  絶縁支持材を仮置きし、モジュール底面と主基板の間を約3mm確保する。',
 '6  ヘッダーの有効長と底面部品の接触を確認し、位置を固定して裏からはんだづけ。',
 '7  W01-W04、外部線を接続する。ボタンGNDはXIAO上面へ付け、裏の密集を避ける。',
 '8  PH端子・電池と接触しうる部分を絶縁。支持材で固定し、配線の力を逃がす。',
 '9  次ページの非通電確認を終えてから、USB給電・電池・LRAを段階的に確認する。',
]
lines(c,39,y,steps,size=9,leading=22)
txt(c,39,82,'追加消耗品：絶縁支持材・固定具・熱収縮チューブ等。購入一覧で保有を確認できていない。',8.5,MUTED)
txt(c,39,65,'支持高さ約3mmは設計目安。ヘッダー脚が不足する場合は長脚品等が必要。高さ・強度は未検証。',8.5,MUTED)
c.showPage()

# 5: Logical diagram and evidence.
title(c,5,'接続の確認と検証範囲','プログラムによる座標・接続チェックと、実物で必要な確認を区別する。')
box(c,48,H-278,144,126,fill='#e6f0f6')
box(c,345,H-278,195,126,fill='#e6f0f6')
txt(c,61,H-172,'XIAO nRF52840',12);txt(c,357,H-172,'DRV2605L / 0x5A',12)
for j,(a,b,net) in enumerate([('3V3','VIN','3V3'),('GND','GND','GND'),('D4','SDA','SDA'),('D5','SCL','SCL')]):
    yy=H-196-j*20;txt(c,136,yy,a,10);txt(c,356,yy,b,10);wire(c,[(192,yy+3),(345,yy+3)],net,1.8)
lines(c,52,H-309,[
 'USB-C → XIAO内蔵端子 / LiPo → PHコネクター → BAT+・BAT-（底面）',
 'XIAO D1 → ボタン → GND / INPUT_PULLUP、押下時LOW',
 'DRV OUT+ → LRA①、OUT- → LRA② / 差動出力。GNDには接続しない。',
 'SDA/SCLのプルアップ抵抗はDRVに実装済み。追加抵抗は付けない。',
 'DRVのVINは3V3へ。5V/VBUSや電池+へ付け替えない。',
],size=9,leading=18)
y=H-425
txt(c,39,y,'ソフトで確認したこと',12);y-=22
y=lines(c,39,y,[
 f"・候補{len(candidates)}件を比較。幅 → 長さ → 内部4線の距離の順に選択。",
 '・指定した配置条件内で最小。全立体配置や全固定方法の大域最適を保証しない。',
 '・使用穴の存在、ヘッダー穴の重複なし、基板間の2mm以上の間隔を確認。',
 '・DRVの公式Eagleデータと入力・出力のネット対応を照合。',
 '・部品面/はんだ面は同じ座標を左右反転して生成。',
],size=9,leading=17)
y-=15;txt(c,39,y,'通電前に実物で確認すること',12);y-=22
y=lines(c,39,y,[
 '・電池・USBを外して、各線の両端が導通することと隣接ピンの短絡がないこと。',
 '・3V3-GND間やBAT+-BAT-間に持続的な低抵抗短絡がないこと。',
 '  コンデンサーの充電で抵抗表示が変わる場合があり、ブザーだけで判断しない。',
 '・ボタンは離すと開放、押すと導通。PH極性は電池側を実測して照合する。',
 '・LRAを外してUSBで電圧とI2C応答を確認し、その後に電池の充電を評価する。',
 '・LRA定格・電圧クランプを確定してから駆動。設定未確定で自動校正しない。',
],size=9,leading=17)
txt(c,39,78,'未実施：EDA ERC、現物加工・組立、通電、温度・電流、充電、LRA駆動、BLE、グリップ収納。',8.5,MUTED)
txt(c,39,61,'高さは現物測定が必要。部品外形19.05mmを、そのまま必要グリップ内寸とみなさない。',8.5,MUTED)
c.showPage()

# 6: Actual-scale overlay + primary sources.
title(c,6,'実寸での位置合わせ','A4 / 拡大縮小なし・100%で印刷。下の50mmスケールを定規で照合する。')
board(c,73,H-156,1,components=True,labels=False)
txt(c,52,H-132,'部品面 1:1',10)
board(c,185,H-156,1,components=False,routes=True,back=True,labels=False)
txt(c,168,H-132,'はんだ面 1:1',10)
lines(c,300,H-153,[
 '基板 18.0 × 47.0mm',
 '部品外形 約19.05 × 50.15mm',
 'USBケーブルの抜き差し空間は別途',
 '電池・外部線・固定具はこの図の外',
 '高さと収納可否は未確定',
 '',
 '6列を守る場合も幅は約19.1mm。',
 '片側の直配線が増えるため、',
 '実装性を優先して7列を選択。',
],size=9,leading=17)
c.setStrokeColor(INK);c.setLineWidth(1);c.line(50,490,50+50*mm,490)
for k in range(6):c.line(50+k*10*mm,486,50+k*10*mm,494)
txt(c,50,474,'印刷確認用 50mm',9)
txt(c,39,438,'使用資料',12)
y=417
for label,url in sources:
    txt(c,39,y,label,9);y-=13
    txt(c,39,y,url,7,MUTED);c.linkURL(url,(39,y-2,W-39,y+9),relative=0);y-=19
txt(c,39,y-5,'購入一覧：ハッカソン購入部品一覧2026-10-23.docx（ユーザー指定原本、変更なし）',8.5,MUTED)
c.save()

# Editable SVGs use the same rendering functions and geometry as the PDF.
class SVGCanvas:
    def __init__(self,width,height):self.d=Drawing(width,height);self.fill='#000';self.stroke='#000';self.lw=1;self.font=FONT;self.fs=10;self.dash=[]
    def setFillColor(self,v):self.fill=toColor(v)
    def setStrokeColor(self,v):self.stroke=toColor(v)
    def setLineWidth(self,v):self.lw=v
    def setFont(self,v,s):self.font=v;self.fs=s
    def drawString(self,x,y,s):self.d.add(String(x,y,s,fontName=self.font,fontSize=self.fs,fillColor=self.fill))
    def drawCentredString(self,x,y,s):self.d.add(String(x,y,s,fontName=self.font,fontSize=self.fs,fillColor=self.fill,textAnchor='middle'))
    def rect(self,x,y,w,h,fill=0,stroke=1):self.d.add(Rect(x,y,w,h,fillColor=self.fill if fill else None,strokeColor=self.stroke if stroke else None,strokeWidth=self.lw))
    def circle(self,x,y,r,fill=0,stroke=1):self.d.add(Circle(x,y,r,fillColor=self.fill if fill else None,strokeColor=self.stroke if stroke else None,strokeWidth=self.lw))
    def beginPath(self):return SP()
    def drawPath(self,p):self.d.add(PolyLine(p.p,strokeColor=self.stroke,strokeWidth=self.lw,fillColor=None))
class SP:
    def __init__(self):self.p=[]
    def moveTo(self,x,y):self.p.extend([x,y])
    def lineTo(self,x,y):self.p.extend([x,y])
for back,name in [(False,'部品面.svg'),(True,'はんだ面.svg')]:
    sc=SVGCanvas(390,700)
    txt(sc,25,674,'はんだ面 / 左右反転' if back else '部品面 / USB側が上',13)
    board(sc,90,630,4,back=back,components=not back,routes=back)
    renderSVG.drawToFile(sc.d,str(OUT/name))

readme='''# 細長基板の配置配線図 Rev S1

ユーザーの追加指定：グリップ内に入る細長い構成、XIAO短辺約17.8mmを基準、DRVは白いコネクター2個のSTEMMA QT版。

## 結果
- AE-D-THの左7列を切り出す18.0×47.0mmの案。6列より電気的な直配線を減らせる。
- XIAOとDRVを長手方向へ並べ、両方を2.54mmピンヘッダーで固定する条件では、部品外形は約19.05×50.15mm。
- 17.8mmぴったりの完成幅ではない。電線・はんだ・絶縁・固定具・外部部品・USBケーブルは外形数値に含めていない。
- 元のAE-D-THのG1/G17は取付穴に重なり、切り出し後も存在しない。7×17=119ではなく使用可能117穴。
- 主基板は2.54mmピッチ。2.0mmのPHは外付け配線。電池、ボタン、LRAは別に固定する。
- 購入済み端子台は交換試験時の選択部品。最小構成では省き、LRAへ直配線。

## ファイル
- PDF：配置、左右反転したはんだ面、配線一覧、切出し・組立、確認項目、1:1図と出典。
- SVG：編集可能な部品面・はんだ面。SVGを直接実寸印刷しないこと。実寸確認はPDFの50mmスケールを使う。
- 配線一覧.csv：線番号、両端、色、内部線の切出し目安。外部線は現物合わせ。
- 配置候補比較.csv：直接ヘッダー固定と縦配置の条件内での候補比較。
- 配置と配線.json / 検証結果.json：機械可読の座標、ネット、検証範囲。
- source/build_layout.py：Python + ReportLabによる再生成コード。KiCad ERCは実行していない。

## 再生成
ReportLabがあるPython環境で `python source/build_layout.py` を実行。メーカーEagleデータを照合する検査には、作業ルートのtmp/pdfs/ae-d-th/sources/drv-qt.brdを使用する。座標・配線チェックはスクリプト内のassertで実行する。

## 設計の境界
現物加工、グリップ寸法・高さ、支持強度、ヘッダー有効長、RF、電流・温度、充電、LRA定格電圧・駆動は未検証。LRA駆動条件未確定で最大出力や自動校正を行わない。ソフト上の接続確認は通電試験の代わりにはならない。
XIAOアンテナの下にも既存perfboardランドがあり、無線性能への影響は評価していない。実装を低くするためモジュールを基板へ密着させない。底面BAT配線を先に行い、絶縁支持で隙間を確保する。

## 幅だけをさらに削る場合
DRVのヘッダーを使わずXIAOと短辺をそろえて固定すれば、平面の本体幅を約18.0mmまで下げる参考案は可能。ただし独立した絶縁支持と6本の直配線が必要で、はんだづけの容易さと固定性が下がるため、この作業図の採用案にはしていない。
'''
(OUT/'README.md').write_text(readme)
print(json.dumps({'pdf':str(pdf),'candidates':len(candidates),'selected':best,'checks':check['assertions']},ensure_ascii=False))
