"""Coordinate-based, perfboard-specific soldering guide. Not a manufacturing PCB."""
from pathlib import Path
import json,csv,math,hashlib
from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import A3,landscape
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.graphics.shapes import Drawing,Rect,Line,Circle,String,PolyLine,Polygon
from reportlab.graphics import renderPDF,renderSVG
from reportlab.lib.colors import toColor

OUT=Path(__file__).resolve().parents[1];ROOT=OUT.parents[2]
BASE=ROOT/'output/pdf/ae-d-th-layout-2026-10-28'
data=json.loads((BASE/'配置と配線.json').read_text())
latest=ROOT/'output/pdf/purchased-circuit-2026-10-28'
with (latest/'配線一覧_端子台あり.csv').open(encoding='utf-8-sig') as f:rows=list(csv.reader(f))
assert len(rows)==13
W,H=landscape(A3);FONT='NotoSansJP'
pdfmetrics.registerFont(TTFont(FONT,str(BASE/'source/NotoSansJP.ttf')))
INK='#183448';GREY='#556d7d';EDGE='#c9d8e2'
COL={'3V3':'#cc3c36','GND':'#27343f','SDA':'#0c7dbc','SCL':'#b28600','BUTTON':'#248a50','OUT+':'#b94c9c','OUT-':'#7551ac'}
def hole(n):return (1.49+'ABCDEFG'.index(n[0])*2.54,3.18+(int(n[1:])-1)*2.54)
HOLES=[c+str(r) for c in 'ABCDEFG' for r in range(1,18) if c+str(r) not in ['G1','G17']]
PINS=list(data['u1']['pins'].values())+list(data['u2']['pins'].values())
assert len(HOLES)==117 and len(PINS)==20 and len(set(PINS))==20
assert set(PINS)<=set(HOLES)
for w in data['wires'][:4]:assert tuple(w['path'][0])==hole(w['a']) and tuple(w['path'][-1])==hole(w['b'])

class Page:
 def __init__(self):self.d=Drawing(W,H)
 def rect(self,x,y,w,h,fill='#ffffff',stroke=EDGE,r=5,lw=1):
  self.d.add(Rect(x,H-y-h,w,h,rx=r,ry=r,fillColor=toColor(fill) if fill else None,strokeColor=toColor(stroke) if stroke else None,strokeWidth=lw))
 def text(self,x,y,s,size=11,color=INK,anchor='start'):
  self.d.add(String(x,H-y,s,fontName=FONT,fontSize=size,fillColor=toColor(color),textAnchor=anchor))
 def lines(self,x,y,ss,size=11,lead=19,color=GREY):
  for s in ss:self.text(x,y,s,size,color);y+=lead
 def line(self,ps,color=INK,lw=1.5,dash=False,halo=False):
  if halo:self.line(ps,'#ffffff',lw+2.5)
  self.d.add(PolyLine([v for x,y in ps for v in (x,H-y)],strokeColor=toColor(color),strokeWidth=lw,strokeDashArray=[4,3] if dash else None,fillColor=None))
 def circle(self,x,y,r,fill='#ffffff',stroke=INK,lw=1):
  self.d.add(Circle(x,H-y,r,fillColor=toColor(fill) if fill else None,strokeColor=toColor(stroke) if stroke else None,strokeWidth=lw))
 def cross(self,x,y,r=3,color='#bd5c45'):
  self.line([(x-r,y-r),(x+r,y+r)],color,1.2);self.line([(x-r,y+r),(x+r,y-r)],color,1.2)
 def header(self,num,title,sub):
  self.text(36,31,'HeroesLeague / AE-D-TH はんだづけ用実装配線図',10,GREY)
  self.text(36,61,title,23);self.text(36,84,sub,10,GREY)
  self.line([(36,95),(W-36,95)],EDGE,1)
  self.text(36,H-22,'2026-10-28 / Rev S2   電池・USBを外して作業する。実機の組立・通電・収納は未検証。',9,GREY)
  self.text(W-75,H-22,f'{num} / 4',10,GREY)

def board(p,ox,oy,scale=3.3,back=False,parts=False,wires=True,only=None,axis=True):
 k=2.834645669*scale
 def xy(q):return (ox+((18-q[0]) if back else q[0])*k,oy+q[1]*k)
 def rr(b,fill,stroke=EDGE):
  a=xy(b[:2]);z=xy(b[2:]);p.rect(min(a[0],z[0]),min(a[1],z[1]),abs(a[0]-z[0]),abs(a[1]-z[1]),fill,stroke,r=0)
 rr([0,0,18,47],'#e8f1e9','#659276')
 for yy in [2.5,44.5]:
  p.line([xy((18+1.6*math.cos(-math.pi/2-j*math.pi/30),yy+1.6*math.sin(-math.pi/2-j*math.pi/30))) for j in range(31)],'#b3775c',.9)
 for n in HOLES:
  pos=hole(n)
  if parts and any(b[0]<pos[0]<b[2] and b[1]<pos[1]<b[3] for b in [data['u1']['bounds'],data['u2']['bounds']]):continue
  x,y=xy(pos);p.circle(x,y,.5*k,'#ffffff','#a7bba9',.5)
 if parts:
  rr(data['u1']['bounds'],'#e2edf5','#7697ae');rr(data['u2']['bounds'],'#e2edf5','#7697ae')
  rr([4.605,-1.251,13.615,4.504],'#d8e0e4','#7e919c')
  for s,yy in [('XIAO',10.5),('DRV2605L',35.0)]:
   x,y=xy((9 if yy<20 else 7.84,yy));p.text(x,y,s,11,INK,'middle')
  for yy in [26.167,46.233]:rr([5.3,yy-1.25,10.4,yy+1.25],'#ffffff','#9cabb4')
  for xx in [1.49,14.19]:
   for yy in [26.04,46.36]:
    x,y=xy((xx,yy));p.circle(x,y,1.25*k,'#ffffff','#b3bec7',.7)
 if wires:
  for w in data['wires']:
   if 'path' not in w:continue
   color=COL[w['net']] if only is None or w['id']==only else '#c2ced6'
   p.line([xy(q) for q in w['path']],color,2.5 if color!='#c2ced6' else 1,halo=True)
 for n in PINS:
  x,y=xy(hole(n));p.circle(x,y,.62*k,'#f4dfaa','#a27c39',.7);p.circle(x,y,.22*k,'#9aa9b2',None)
 active=[w for w in data['wires'] if w['id'] in ['W01','W02','W03','W04','W05','W09','W10']]
 for w in active:
  if only and w['id']!=only:continue
  ends=[w['a']]+([w['b']] if w['id'] in ['W01','W02','W03','W04'] else [])
  for n in ends:
   x,y=xy(hole(n));p.circle(x,y,.72*k,None,COL[w['net']],1.6)
 if axis:
  for cc in 'ABCDEFG':
   x,_=xy(hole(cc+'1'));p.text(x,oy-14,cc,10,INK,'middle')
  for rrn in range(1,18):
   _,y=xy(hole('A'+str(rrn)));p.text(ox+18*k+7 if back else ox-15,y+3,str(rrn),8.5,GREY)
 return xy

pages=[]
p=Page();p.header(1,'穴番号で作る実装配線図','細長い7列案を継承 / 部品面と裏面を同じUSB側の向きで並べた図 / 端子台あり12本の構成')
p.rect(36,110,354,550);p.rect(410,110,395,550);p.rect(825,110,330,550)
p.text(50,132,'部品面：部品を載せる側',13)
p.text(424,132,'はんだ面：左右に裏返した側',13)
front=board(p,125,175,parts=True,wires=False)
back=board(p,490,175,back=True,parts=False,wires=True)
for pin,n in data['u1']['pins'].items():
 xx,yy=front(hole(n))
 s=n+' '+({'D4':'D4/SDA','D5':'D5/SCL'}.get(pin,pin))
 p.text(48 if n[0]=='A' else 302,yy+3,s,9.2)
xx,yy=front(hole('G1'));p.cross(xx,yy);p.text(302,yy+3,'G1：ピンなし',8.5,'#b05743')
for pin,n in data['u2']['pins'].items():
 xx,yy=front(hole(n))
 if n[0]=='A':p.text(48,yy+3,n+' '+pin,9.2)
 else:p.text(302,yy+3,n+' '+pin,9.2)
# External button lead: source A2 on the back, return is explicitly front-side G2.
a=back(hole('A2'));p.line([a,(690,a[1]),(690,a[1]+9)],COL['BUTTON'],2.5,halo=True)
p.text(697,a[1]+4,'W05 → ボタンa',9.2,COL['BUTTON'])
g=front(hole('G2'));p.line([g,(g[0]+10,g[1]-10)],COL['GND'],2)
p.text(302,g[1]-11,'W06：上面からbへ',8.2,COL['GND'])
for n,net in [('G2','GND'),('G3','3V3')]:
 xx,yy=back(hole(n));p.text(426,yy+3,n,10,COL[net])
for n,net in [('A5','SDA'),('A6','SCL'),('A12','3V3'),('A13','GND'),('A14','SCL'),('A15','SDA')]:
 xx,yy=back(hole(n));p.text(702,yy+3,n,10,COL[net])
for n,lab,net in [('F12','F12 -','OUT-'),('F16','F16 +','OUT+')]:
 xx,yy=back(hole(n));p.text(xx+10,yy-6,lab,8.5,COL[net])
p.text(442,641,'W09 / W10 → 基板外のJ2端子台へ（3頁）',10)
p.text(50,643,'上：USB-C / 下：DRVの白いQTコネクター',9.5,GREY)

p.text(840,137,'丸印の意味',13)
p.circle(850,158,5,'#f4dfaa','#a27c39');p.text(866,162,'ヘッダーを固定する20箇所',10)
p.circle(850,184,6,None,COL['SDA'],1.8);p.text(866,188,'色付きの輪：電線を追加する箇所',10)
p.lines(840,222,['ヘッダーを基板に固定してから、','電線のむいた先を裏へ出た足に添える。','同じ穴へ足と電線を無理に押し込まない。'],10.5,19)
p.text(840,298,'内部4本の接続',13)
for i,w in enumerate([data['wires'][1],data['wires'][0],data['wires'][2],data['wires'][3]]):
 yy=328+i*43;p.line([(842,yy-4),(864,yy-4)],COL[w['net']],3)
 p.text(875,yy,w['id']+'  '+w['a']+' → '+w['b'],12,COL[w['net']])
 p.text(875,yy+16,w['net']+' / 切出し目安 '+str(w['cut_mm'])+'mm',9,GREY)
p.lines(840,530,['交差部は非接続。途中の被覆はむかない。','色線は電線であり、銅箔パターンではない。','USB・電池を外して作業する。','G1 / G17は元の取付穴に重なり使えない。','BAT端子は主基板の穴とは別（3頁）。'],10,20)

p.rect(36,684,1119,105,'#f1f6f9')
p.lines(50,706,[
 '主基板：AE-D-THの左7列を切り出す18×47mm案。7列×17行からG1/G17を除いた117穴。切断前に実物を仮合わせする。',
 '部品外形：約19.05×50.15mm。DRVの一部は基板からはみ出す。外部部品・電線・絶縁・固定具・収納高さはこの寸法に含めない。',
 '金色の20箇所は、モジュール側と主基板側の両方をはんだづけ。G2は裏面W02とXIAO上面W06で同じGNDを使う。',
 '追加抵抗や裸スズメッキ線は不要。配線・支持・絶縁の設計案であり、通電・充電・LRA駆動を確認した実装図ではない。',
],10.5,21)
pages.append(p)

# Page 2: four independent soldering operations, same mirrored coordinates.
p=Page();p.header(2,'内部4本を1本ずつはんだづけする','各図の色付き線だけを作業する。薄い線は全体図の他の配線。電源を外した状態で導通を確認する。')
for idx,w in enumerate([data['wires'][1],data['wires'][0],data['wires'][2],data['wires'][3]]):
 x=36+idx*282;p.rect(x,115,273,673)
 p.text(x+13,140,f'{idx+1}  {w["id"]}  {w["net"]}',15,COL[w['net']])
 board(p,x+55,180,3.1,back=True,wires=True,only=w['id'])
 p.text(x+13,624,w['a']+' → '+w['b'],14,COL[w['net']])
 p.text(x+13,649,'電線の切出し目安：約'+str(w['cut_mm'])+'mm',11)
 p.lines(x+13,681,[
  '両端だけ2-3mm程度むく。',
  '両端に薄く予備はんだを付ける。',
  '色輪のピン足へ端を添えて接合。',
  '固まるまで動かさない。',
  '両端の導通と隣接部の短絡を確認。',
 ],9.5,19)
pages.append(p)

# Page 3: external components, with verified classic-XIAO bottom orientation.
p=Page();p.header(3,'基板外の配線とXIAO底面の電池端子','W05-W12 / BAT端子はXIAO単体の裏面へ先に接合する / コネクターは抜き差しの力を受けるよう別途保持する')
p.rect(36,116,545,330);p.rect(602,116,553,330)
p.text(50,141,'電池：XIAO底面 → J1 PHコネクター',14)
# XIAO bottom view: USB on top, D0-D6 on right. Based on official v1.0 silk/footprint.
ox,oy,k=66,194,7.1
p.rect(ox,oy,17.78*k,20.955*k,'#e4edf3','#8199a9',5)
p.rect(ox+4.3*k,oy-2.2*k,9*k,4*k,'#dce3e7','#81949e',2)
p.text(ox+6,oy-23,'XIAO単体の裏 / USBが上',9.5)
for i in range(7):
 yy=oy+(2.921+i*2.54)*k
 for xx in [ox+1.27*k,ox+16.51*k]:p.circle(xx,yy,3.2,'#dabb75','#9f844d',.6)
 p.text(ox+17.78*k+4,yy+3,str(i),8,GREY)
p.text(ox+8,oy+15,'5V',7.5,GREY);p.text(ox+8,oy+34,'GND',7.5,GREY)
# Coordinates projected from official classic-XIAO footprint; physical revision must match.
bx=ox+12.9*k;batminus=oy+8.3225*k;batplus=oy+10.2275*k
for yy,sign,col in [(batminus,'-',COL['GND']),(batplus,'+',COL['3V3'])]:
 p.rect(bx-1.25*k,yy-.55*k,2.5*k,1.1*k,'#e8c676','#a1874c',0)
 p.text(bx-17,yy+3,sign,10,col)
p.line([(bx,batminus),(229,batminus),(229,238),(340,238)],COL['GND'],2)
p.line([(bx,batplus),(247,batplus),(247,316),(340,316)],COL['3V3'],2)
p.text(238,229,'W08 BAT-',10,COL['GND']);p.text(252,337,'W07 BAT+',10,COL['3V3'])
p.rect(340,210,95,135,'#fff7eb','#bdab8d',4);p.text(350,202,'J1 PH 2P',11)
for yy,sign,col in [(238,'-対応側',COL['GND']),(316,'+対応側',COL['3V3'])]:
 p.circle(340,yy,3,'#ffffff',col);p.text(350,yy-8,sign,9,col)
 p.line([(340,yy),(480,yy)],col,2)
p.rect(480,212,70,132,'#e7edf1','#a3b3bd',5);p.text(488,264,'LiPo',12);p.text(486,285,'3.7V',10)
p.lines(50,378,[
 'メーカーv1.0の裏面図を簡略化。BAT-が上、BAT+が下の小さな2パッド。',
 '実物のBAT+/-印字と向きが一致することを確認。主基板の穴へは接合しない。',
 'J1の+/-は極性実測で確定する管理名。図の上下はピン番号指定ではない。',
],9.5,20)

p.text(617,141,'ボタン：W05は裏、W06はXIAO上面から',14)
p.rect(625,184,190,150,'#eef4f8');p.text(641,207,'XIAO / 主基板の取出し',11)
p.text(642,252,'A2 / D1（裏面）',11,COL['BUTTON']);p.text(642,303,'G2 / GND（上面）',11,COL['GND'])
p.line([(815,247),(916,247)],COL['BUTTON'],2);p.text(842,237,'W05',10,COL['BUTTON'])
p.line([(815,298),(1060,298),(1060,247)],COL['GND'],2);p.text(842,288,'W06',10,COL['GND'])
p.circle(916,247,4,'#ffffff',COL['BUTTON']);p.circle(1060,247,4,'#ffffff',COL['GND'])
p.line([(916,247),(1005,224)],COL['BUTTON'],2)
p.text(892,271,'接点a',10);p.text(1038,271,'接点b',10)
p.lines(617,369,[
 'スイッチの①②は同じ接点、③④は同じ接点。片方ずつ選んで導通確認。',
 'ボタンを離すと開放、押すと導通。G2裏へW02とW06をまとめて押し込まない。',
 '電池本体や電池付属線の切断・直接はんだづけは不要。',
],9.5,20)

p.rect(36,467,1119,320);p.text(50,492,'振動子：F16 / F12 → J2端子台 → LRA',14)
# Separate terminal channels: solder side is pins, actuator leads are screw-clamped.
p.rect(245,533,160,120,'#e3efe7','#7d9c88',5)
p.text(260,552,'J2 / 2.54mm端子台',11)
for yy,col,src,lab,wa,wb,mterm in [(580,COL['OUT+'],'F16','A (+)','W09','W11','①'),(628,COL['OUT-'],'F12','B (-)','W10','W12','②')]:
 p.text(60,yy-7,src+' / OUT'+('+' if src=='F16' else '-'),11,col)
 p.line([(152,yy),(245,yy)],col,2);p.text(172,yy-8,wa,10,col)
 p.circle(245,yy,4,'#ffffff',col);p.line([(245,yy),(395,yy)],col,2)
 p.circle(395,yy,7,'#f0f3f1',col);p.line([(391,yy-3),(399,yy+3)],col,1)
 p.text(272,yy-8,lab,10,col)
 p.line([(405,yy),(560,yy)],col,2);p.text(465,yy-8,wb,10,col)
 p.circle(560,yy,4,'#ffffff',col);p.text(576,yy+4,'LRA '+mterm,12,col)
p.text(190,680,'左：基板用の脚へはんだづけ',10)
p.text(390,701,'右：ねじ端子で振動子の線を固定',10)
p.lines(700,535,[
 'J2のA/Bはこの図の管理名。接続先を+/-で表示する。',
 'LRA①へOUT+、②へOUT-。両方ともGNDへつながない。',
 '⑤⑥ケースパッドは未接続。①③、②④はそれぞれ内部接続。',
 '実物の向きと端子図を確認して①②へ接合する。',
 '',
 '最小構成：J2とW11/W12を省き、W09を①、W10を②へ直結。',
 'DRVのINと白いQTコネクター2個は使わない。',
 'LRA駆動条件は未確定。設定前に最大出力や自動校正をしない。',
],10,22)
p.text(50,751,'XIAO裏面参照：https://files.seeedstudio.com/wiki/XIAO-BLE/XIAO_nRF52840_back_pinout.png',8.5,GREY)
p.text(50,770,'LRA端子参照：https://akizukidenshi.com/goodsaffix/LD14-002.png',8.5,GREY)
pages.append(p)

# Page 4: solder cross-section, exact-scale footprint, and meaningful checks.
p=Page();p.header(4,'接合の断面と作業前後の確認','実装図ははんだ位置の参照用。支持高さ・ヘッダー脚長・配線固定・グリップ収納は現物で確認する。')
p.rect(36,117,555,337);p.rect(612,117,543,337)
p.text(50,143,'ヘッダーの足に電線を添える接合',14)
# Cross-section: electrical connection is exposed pin + isolated bottom pad.
p.rect(104,202,355,20,'#d7e5ee','#8fa4b2',0);p.text(118,194,'XIAO または DRV の基板',11)
p.rect(104,308,355,25,'#cde3d2','#7e9b84',0);p.text(118,357,'AE-D-TH（主基板）',11)
p.rect(263,209,14,173,'#bba369','#8d7744',0)
p.rect(247,237,46,48,'#333f47','#202e36',2)
p.circle(270,222,15,'#aebdc6','#84949d',1);p.circle(270,333,15,'#aebdc6','#84949d',1)
p.line([(270,360),(352,375),(455,375)],COL['SDA'],9)
p.line([(270,360),(312,368)],'#c0cbd1',5)
p.text(335,394,'被覆を残す',10,COL['SDA'])
p.text(50,417,'むいた端だけを足へ添える。こてでピン足とパッドを一緒に温める。',10)
p.text(50,438,'はんだを少量足し、はんだ → こての順に離して固まるまで保持する。',10)
p.lines(627,166,[
 '組立順',
 '1  USB・電池を外す。切断前に実物を配置して仮合わせする。',
 '2  XIAO底面BAT端子のW07/W08を先に接合し、各部を絶縁する。',
 '3  ヘッダーをモジュールへ接合する。XIAOは7本+6本、DRVは7本。',
 '4  絶縁支持で隙間を確保し、主基板裏の金色20箇所を接合する。',
 '5  内部4本（2頁）→ ボタン・PH・J2・LRA（3頁）の順に配線する。',
 '6  線を保持して、抜き差しや収納の力が接合部へかからないようにする。',
 '',
 'こてを長時間押し当てない。溶けない場合は離して、こて先と接触を確認。',
 '熱収縮チューブ・支持具・固定材の保有は未確認。必要な分を用意する。',
 '図の隙間は説明用。実装では約3mmを目安に仮合わせし、脚長を確認。',
],10.5,24)
p.rect(36,477,555,310);p.text(50,503,'実寸での仮合わせ（A3 / 100%印刷）',14)
board(p,84,546,1,parts=True,wires=False,axis=False)
board(p,205,546,1,back=True,parts=False,wires=True,axis=False)
p.text(72,528,'部品面 1:1',9.5);p.text(193,528,'はんだ面 1:1',9.5)
p.line([(75,728),(75+50*2.834645669,728)],INK,1)
for i in range(6):p.line([(75+i*10*2.834645669,724),(75+i*10*2.834645669,732)],INK,1)
p.text(75,750,'印刷確認用 50mm',10)
p.lines(320,552,[
 '主基板18×47mm。部品外形約19.05×50.15mm。',
 'A3の100%で印刷し、50mm線を定規で確認。',
 'PDFを用紙へ自動縮小すると実寸ではなくなる。',
 '',
 '実物の基板にG1/G17がないことを確認する。',
 '支持・電線・絶縁・収納高さは別途余裕が必要。',
 'USBケーブルの抜き差し空間も確保する。',
],9.5,22)
p.rect(612,477,543,310);p.text(627,503,'非通電で確認してから、段階的に電源確認',14)
p.lines(627,538,[
 '・各線の両端が導通すること、隣接ピンとの短絡がないこと。',
 '・3V3-GND、BAT+-BAT-に持続的な低抵抗短絡がないこと。',
 '  コンデンサーで表示が変わるため、ブザーだけで判断しない。',
 '・ボタンは離すと開放、押すと導通。電池とJ1の極性を照合する。',
 '・DRV VINが3V3に接続され、5Vや電池+へ接続されていないこと。',
 '・初回の電源・充電確認ではDRV/LRAを外し、XIAOと電池で確認。',
 '',
 'ソフト照合：117穴、20ヘッダー位置、12本の接続、左右反転。',
 '未実施：加工・組立・通電、EDA ERC、電流/温度、充電、LRA、BLE。',
 'メーカー資料は個体の版と照合し、異なる場合は作業を止めて確認する。',
],10.5,23)
pages.append(p)

pdf=OUT/'AE-D-TH_はんだ付け実装配線図_2026-10-28.pdf'
c=canvas.Canvas(str(pdf),pagesize=(W,H));c.setTitle('AE-D-TH はんだ付け実装配線図 Rev S2')
for p in pages:renderPDF.draw(p.d,c,0,0);c.showPage()
c.save()
renderSVG.drawToFile(pages[0].d,str(OUT/'実装配線図_表裏.svg'))
(OUT/'配線一覧_端子台あり.csv').write_bytes((latest/'配線一覧_端子台あり.csv').read_bytes())
checks={
 'holes':117,'headers':20,'wire_rows':12,'orientation':'USB up in both views; x_back = 18 - x_front',
 'assertions':{'all_header_holes_exist':True,'unique_header_holes':True,'internal_path_endpoints_match':True,'latest_12_wire_table_reused':True},
 'battery_reference':'Seeed official classic XIAO nRF52840 v1.0 bottom silk, footprint, and back pinout image; confirm physical revision and marks',
 'bat_positions_in_inset':'USB up, BAT- above BAT+ on right inner area; not perfboard hole addresses',
 'source_layout_sha256':hashlib.sha256((BASE/'配置と配線.json').read_bytes()).hexdigest(),
 'source_wire_table_sha256':hashlib.sha256((latest/'配線一覧_端子台あり.csv').read_bytes()).hexdigest(),
 'physical_test_performed':False,'eda_erc_performed':False,
}
(OUT/'照合記録.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2))
print(json.dumps({'pdf':str(pdf),'pages':4,'checks':checks},ensure_ascii=False))
