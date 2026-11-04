"""LRA-only complete pin/wire schedule, with measured-polarity branches for J1."""
from pathlib import Path
import ast,json,csv,math,hashlib,xml.etree.ElementTree as ET
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
W,H=landscape(A3);FONT='NotoSansJP';INK='#183448';GREY='#556d7d';EDGE='#c9d8e2'
COL={'3V3':'#cc3c36','GND':'#27343f','SDA':'#0c7dbc','SCL':'#b28600','BUTTON':'#248a50','OUT+':'#b94c9c','OUT-':'#7551ac','VBAT':'#cc3c36'}
pdfmetrics.registerFont(TTFont(FONT,str(BASE/'source/NotoSansJP.ttf')))
def hole(n):return (1.49+'ABCDEFG'.index(n[0])*2.54,3.18+(int(n[1:])-1)*2.54)
HOLES=[c+str(r) for c in 'ABCDEFG' for r in range(1,18) if c+str(r) not in ['G1','G17']]
PINS=list(data['u1']['pins'].values())+list(data['u2']['pins'].values())
# Reuse the drawing primitives and exact board-coordinate function without running the older script.
old=ROOT/'output/pdf/perfboard-solder-guide-2026-10-28/source/build_guide.py'
tree=ast.parse(old.read_text());keep=[n for n in tree.body if isinstance(n,(ast.FunctionDef,ast.ClassDef)) and n.name in ['Page','board']]
exec(compile(ast.Module(body=keep,type_ignores=[]),str(old),'exec'),globals())

def header(p,n,title,sub):
 p.text(36,31,'HeroesLeague / LRA専用 全配線・全端子指定',10,GREY)
 p.text(36,61,title,23);p.text(36,84,sub,10,GREY);p.line([(36,95),(W-36,95)],EDGE,1)
 p.text(36,H-22,'2026-10-28 / Rev J1 / 主基板一体化・ケースB   J1極性はユーザー測定報告によりケースB確定。実機試験・EDA ERCは未実施。',9,GREY)
 p.text(W-75,H-22,f'{n} / 5',10,GREY)
def table(p,x,y,widths,heads,records,rowh=29,size=9.5):
 xs=[x]
 for v in widths:xs.append(xs[-1]+v)
 for j,t in enumerate(heads):p.rect(xs[j],y,widths[j],29,'#e1ecf3',EDGE,0,.6);p.text(xs[j]+6,y+20,t,10)
 for i,row in enumerate(records):
  yy=y+29+i*rowh
  for j,t in enumerate(row):
   p.rect(xs[j],yy,widths[j],rowh,'#f6f9fb' if i%2==0 else '#ffffff',EDGE,0,.5)
   p.text(xs[j]+6,yy+rowh*.66,str(t),size)
 return y+29+len(records)*rowh

# IDs 1-14 on XIAO are module schematic U4 pins, never MCU-package pins or Arduino numbers.
schedule=[
 ['W01','赤','U1-12：3V3','S0.G3','U2 JP2-1：VIN','S0.A12','3V3','固定'],
 ['W02','黒','U1-13：GND','S0.G2 裏','U2 JP2-2：GND','S0.A13','GND','固定'],
 ['W03','青','U1-5：D4 / P0.04','S0.A5','U2 JP2-4：SDA','S0.A15','SDA','固定'],
 ['W04','黄','U1-6：D5 / P0.05','S0.A6','U2 JP2-3：SCL','S0.A14','SCL','固定'],
 ['W05','緑','U1-2：D1 / P0.03','S0.A2 裏','SW1-1','基板外','BUTTON','固定'],
 ['W06','黒','U1-13：GND','S0.G2 のXIAO上面','SW1-3','基板外','GND','固定'],
 ['W07','赤','J1-1：電池+','S0.H1 新規穴 / 表の脚','U1 BAT+（底面パッド）','S0の穴ではない','VBAT','ケースB採用済み'],
 ['W08','黒','J1-2：電池-','S0.H2 新規穴 / 表の脚','U1 BAT-（底面パッド）','S0の穴ではない','GND','ケースB採用済み'],
 ['W09','紫','U2 JP1-1：OUT+','S0.F16','J2-1 基板用の脚','S2.B2','OUT+','固定'],
 ['W10','紫・印付き','U2 JP3-1：OUT-','S0.F12','J2-2 基板用の脚','S2.C2','OUT-','固定'],
 ['W11','紫','J2-1 ねじ側','S2.B2と同一端子','M1 LD14-002 ①','振動子端子図を参照','OUT+','固定'],
 ['W12','紫・印付き','J2-2 ねじ側','S2.C2と同一端子','M1 LD14-002 ②','振動子端子図を参照','OUT-','固定'],
]
factory=[
 ['C01','付属赤線','LiPo + → PHRの+接点','J1の同じ番号へ嵌合','既設。切断・再はんだ不要'],
 ['C02','付属黒線','LiPo - → PHRの-接点','J1の同じ番号へ嵌合','既設。切断・再はんだ不要'],
]
cases={
 'A':{'positive_pin':2,'negative_pin':1,'W07':['J1-2','S1.C2','U1.BAT+'],'W08':['J1-1','S1.B2','U1.BAT-']},
 'B':{'positive_pin':1,'negative_pin':2,'W07':['J1-1','S1.B2','U1.BAT+'],'W08':['J1-2','S1.C2','U1.BAT-']},
}
for name,c in cases.items():
 assert c['positive_pin']!=c['negative_pin']
 assert c['W07'][-1]=='U1.BAT+' and c['W08'][-1]=='U1.BAT-'
 assert c['W07'][0][-1]==str(c['positive_pin']) and c['W08'][0][-1]==str(c['negative_pin'])
assert len(schedule)==12 and len({x[0] for x in schedule})==12
vendor=ET.parse(ROOT/'tmp/pdfs/ae-d-th/sources/drv-qt.brd')
vendor_nets={s.get('name'):{(c.get('element'),c.get('pad')) for c in s.findall('contactref')} for s in vendor.findall('.//signals/signal')}
for net,pad in [('VCC','1'),('GND','2'),('SCL','3'),('SDA','4'),('IN/TRIG','5')]:assert ('JP2',pad) in vendor_nets[net]
assert ('JP1','1') in vendor_nets['OUT+'] and ('JP3','1') in vendor_nets['OUT-']

# User choice B is preserved. Coordinate origin: S0 front, USB up, x right/y down in mm.
J1P={'H1':(10.11,22.23),'H2':(8.11,22.23)}
J1BOX=[6.16,20.53,12.06,25.03]
J1KEEP=[5.16,19.53,13.06,26.03]
data['wires'][0]['path']=[hole('G3'),(15.46,8.26),(15.46,27.4),(8,27.4),(8,31.12),hole('A12')]
data['wires'][1]['path']=[hole('G2'),(14.0,5.72),(14.0,29.0),(6.57,29.0),(6.57,33.66),hole('A13')]
def onj1(p,xy,back=False):
 a=xy(J1BOX[:2]);b=xy(J1BOX[2:])
 if back:
  p.rect(min(a[0],b[0]),min(a[1],b[1]),abs(a[0]-b[0]),abs(a[1]-b[1]),'#fff5d9','#ac8a4f',0,1.2)
  # keyed wall at top in the reverse-side view; pin 1 is left in this view.
  aa=xy((8.61,20.53));bb=xy((9.61,21.13))
  p.rect(min(aa[0],bb[0]),min(aa[1],bb[1]),abs(aa[0]-bb[0]),abs(aa[1]-bb[1]),'#e8f1e9','#ac8a4f',0,.7)
 for name,point in J1P.items():
  x,y=xy(point);p.circle(x,y,4.4,'#ffffff',COL['VBAT'] if name=='H1' else COL['GND'],1.8)
  
  if back:p.text(x,y+17,'1 +' if name=='H1' else '2 -',8,INK,'middle')
 if back:
  xx,yy=xy((9.11,24.9));p.text(xx,yy,'J1 / 裏面',8,INK,'middle')
checks_geo={}
assert abs(J1P['H1'][0]-J1P['H2'][0])==2.0
for n,point in J1P.items():
 near=min(math.dist(point,hole(h)) for h in HOLES)
 checks_geo[n]={'center_mm':point,'drill_mm':0.8,'nearest_existing_hole_center_mm':round(near,4)}
 assert near>.9  # two drill radii: new .4 + existing .5; no overlap of holes
 assert data['u1']['bounds'][3] < point[1]-.4 and point[1]+.4 < data['u2']['bounds'][1]
 assert 0<point[0]-.4 and point[0]+.4<18
assert 0<J1BOX[0]<J1BOX[2]<18 and 0<J1BOX[1]<J1BOX[3]<47
# Orthogonal line segments must not enter the reserved rear J1 body zone (+1mm).
for wire in data['wires'][:2]:
 path=wire['path'];wire['route_mm']=sum(math.dist(a,b) for a,b in zip(path,path[1:]))
 for a,b in zip(path,path[1:]):
  if abs(a[0]-b[0])<1e-6:
   assert not(J1KEEP[0]<a[0]<J1KEEP[2] and max(min(a[1],b[1]),J1KEEP[1])<min(max(a[1],b[1]),J1KEEP[3]))
  else:
   assert abs(a[1]-b[1])<1e-6
   assert not(J1KEEP[1]<a[1]<J1KEEP[3] and max(min(a[0],b[0]),J1KEEP[0])<min(max(a[0],b[0]),J1KEEP[2]))

pages=[]
p=Page();header(p,1,'全配線一覧：どのピンから、どのピンへ','S0＝AE-D-TH主基板。J1は裏面へ直接実装（新規穴H1/H2）。S1小基板を廃止。J2だけは従来のS2上。')
recs=[[r[0],r[1],r[2],r[3],r[4],r[5],r[7]] for r in schedule]
end=table(p,36,117,[45,68,220,158,235,180,173],['線','色','接続元の部品・ピン','接続元の穴・面','接続先の部品・ピン','接続先の穴・面','状態'],recs,32,9.3)
table(p,36,end+18,[55,85,330,320,289],['既設線','色','電池側','J1との対応','作業'],factory,31,10)
p.rect(36,667,1119,119,'#fff7e8','#d6bc8a')
p.lines(50,690,[
 'J1極性：ユーザー測定報告によりケースB採用。1番＝+、2番＝-。W07/W08の接続先を本書で確定。',
 'J1はS0裏面へ直接実装。2.0mm間隔の新規穴H1/H2を追加し、本体を樹脂の押さえで保持する。別基板S1は不要。',
 'USBは既製USB-CケーブルをXIAO内蔵端子へ挿す。VBUS端子への手配線はしない。iPhoneとの接続はBLE無線。',
 '内部・外部の手配線は12本。C01/C02は電池付属線。操作ボタンSW1は残し、LRA専用回路とする。',
],10.5,22)
pages.append(p)

p=Page();header(p,2,'XIAO・DRVの全端子対応','番号は基板/モジュールの参照ピン番号。nRF52840やDRV2605LのICパッケージの足番号へ直接配線しない。')
xrows=[]
names=['D0','D1','D2','D3','D4','D5','D6','D7','D8','D9','D10','3V3','GND','VBUS/5V']
holes=['A1','A2','A3','A4','A5','A6','A7','G7','G6','G5','G4','G3','G2','G1なし']
usage=['無配線','W05 → SW1-1','無配線','無配線','W03 → U2 JP2-4','W04 → U2 JP2-3','無配線','無配線','無配線','無配線','無配線','W01 → U2 JP2-1','裏W02 / 上面W06','ピンヘッダーを付けない']
for i,(n,h,u) in enumerate(zip(names,holes,usage),1):xrows.append([i,n,'S0.'+h,u])
xrows += [['底面','BAT+','S0穴とは別','W07 ← J1の電池+ピン'],['底面','BAT-','S0穴とは別','W08 ← J1の電池-ピン']]
table(p,36,120,[54,102,98,303],['U1番号','端子名','穴','配線先'],xrows,29,10)
p.rect(36,638,557,116,'#f2f6f9')
ox,oy,kk=55,652,4.2
p.rect(ox,oy,17.78*kk,20.955*kk,'#dfeaf2','#829bab',3)
p.rect(ox+4.3*kk,oy-2.1*kk,9*kk,3.6*kk,'#d8e1e7','#829bab',1)
for i in range(7):
 for xx in [ox+1.27*kk,ox+16.51*kk]:p.circle(xx,oy+(2.921+i*2.54)*kk,1.7,'#d8bb73','#9d844a',.5)
bx=ox+12.9*kk
for yy in [oy+8.3225*kk,oy+10.2275*kk]:p.rect(bx-1.25*kk,yy-.55*kk,2.5*kk,1.1*kk,'#e6c474','#a48a51',0,.5)
p.text(165,658,'XIAO単体裏面 / USB上（公式v1参照）',11)
p.line([(bx,oy+8.3225*kk),(158,oy+8.3225*kk),(158,676),(240,676)],COL['GND'],1.5)
p.line([(bx,oy+10.2275*kk),(182,oy+10.2275*kk),(182,708),(240,708)],COL['3V3'],1.5)
p.text(250,680,'BAT-：上の小パッド → W08',10,COL['GND'])
p.text(250,712,'BAT+：下の小パッド → W07',10,COL['3V3'])
p.text(165,741,'主基板の穴とは別。現物のBAT印字と版を照合してから接合。',9,GREY)
drv=[['JP2-1','VIN / VCC','S0.A12','W01 ← U1-12 3V3'],['JP2-2','GND','S0.A13','W02 ← U1-13 GND'],['JP2-3','SCL','S0.A14','W04 ← U1-6 D5'],['JP2-4','SDA','S0.A15','W03 ← U1-5 D4'],['JP2-5','IN / TRIG','S0.A16','無配線'],['JP1-1','OUT+','S0.F16','W09 → J2-1'],['JP3-1','OUT-','S0.F12','W10 → J2-2']]
table(p,618,120,[89,99,91,258],['U2ピン','端子名','穴','配線先'],drv,35,10)
p.rect(618,425,537,302,'#f2f6f9');p.text(633,449,'番号を混同しないための注意',14)
p.lines(633,478,[
 'U1-2はXIAOモジュール回路図のD1。MCU信号はP0.03。',
 'U1-5はD4/P0.04、U1-6はD5/P0.05。',
 'U2のJP番号はAdafruit公式Eagleデータのヘッダー番号。',
 'OUT+はJP1、OUT-はJP3。白いQTコネクターではない。',
 'QTコネクター2個、IN、DRVの4つの大きな固定穴は無配線。',
 'XIAOの未使用GPIOは短絡させず独立のまま。',
 'D0等の未使用ピンもヘッダーの機械固定に使う。',
 '主基板のG1/G17は穴がなく、VBUSは無配線。',
 'BAT-とGNDはXIAO内部で共通。別の外付け短絡線は不要。',
],10.5,24)
p.text(36,774,'XIAO 13本 + DRV 7本のヘッダーを使用。番号と端子名を基板のシルク/メーカー図で二重に確認する。',11)
pages.append(p)

p=Page();header(p,3,'J1をS0裏面へ直付けする：追加穴H1/H2','H1/H2は既存のA-G・1-17とは別の新規穴。部品実装前の裸基板に加工し、J1を裏側から差し込む。')
p.rect(36,116,540,401);p.rect(595,116,560,401)
p.text(50,141,'加工図：S0表面から見る / USB上',14)
# Detail of rows 7-11. All dimensions reference the front side, so H1 is right.
ox,oy,k=120,180,20
for cc in 'BCDEF':
 xx=hole(cc+'8')[0];p.text(ox+xx*k,oy-13,cc,10,INK,'middle')
for rr in range(7,12):
 yy=hole('D'+str(rr))[1]
 p.text(ox+30,oy+(yy-18)*k+4,str(rr),10)
 for cc in 'BCDEF':
  x,y=hole(cc+str(rr));p.circle(ox+x*k,oy+(y-18)*k,.5*k,'#ffffff','#94aa97')
for n,(x,y) in J1P.items():
 px,py=ox+x*k,oy+(y-18)*k
 p.circle(px,py,.4*k,'#fff3db',COL['VBAT'] if n=='H1' else COL['GND'],1.8)
 p.line([(px-12,py),(px+12,py)],GREY,.6);p.line([(px,py-12),(px,py+12)],GREY,.6)
 p.text(410 if n=='H1' else 65,py+4,n+(' / J1-1 +' if n=='H1' else ' / J1-2 -'),10)
 p.line([(px+(8 if n=='H1' else -8),py),(400 if n=='H1' else 148,py)],GREY,.7)

p.lines(50,448,['H1-H2間隔：2.00mm。y位置は8行目と9行目の中央。','D列から左右へ各1.00mm。既存のD8/D9等の穴は拡張しない。','φ0.8mmの非めっき穴。位置決め治具を使用し、2.00±0.05mmを目標。'],10.5,23)
p.text(609,141,'穴中心座標・本体・電池接続',14)
table(p,609,162,[65,100,100,180],['穴','x（右へ）','y（下へ）','接続'],[
 ['H1','10.11mm','22.23mm','J1-1 / W07 / BAT+'],
 ['H2','8.11mm','22.23mm','J1-2 / W08 / BAT-'],
],34,10)
p.lines(609,299,[
 '原点：切出し後S0の左上。座標は表面から見た値。',
 '裏面から見ると左右反転：H1（1+）が左、H2（2-）が右。',
 'J1の中央切り欠きのある壁を、裏面図でもUSB側へ向ける。',
 'J1本体：幅5.9 × 奥行4.5mm、単体高さ6mm。',
 'PHRを挿した嵌合高さ：基板面から8mm＋電線の曲げ余裕。',
 '端子の出る表面はXIAO/DRVの間。配線は表面側へ接合。',
 'J1の脚は曲げ広げず、穴位置を合わせる。',
 'ケースB：赤J1-2 / 黒J1-1で-3.8V（ユーザー報告）。',
],10.5,24)
p.rect(36,538,1119,248,'#fff7e8','#d6bc8a');p.text(50,563,'重要：非めっき穴には、はんだランドもスルーホールめっきもない',15)
p.lines(50,595,[
 'H1/H2へはんだを流しても基板への固定にはならない。はんだは「J1の脚とW07/W08」の電気接合にだけ使用する。',
 'J1本体の側面・底部を樹脂製の押さえで基板に保持し、グリップ側のホルダーでも支持する。保持形状・強度は現物合わせ。',
 '抜き差しの力を端子・電線・はんだ接合部で受けない。嵌合口を塞がず、ケーブルを引っ張らずハウジングを持って抜く。',
 '穴の周囲は両面とも銅箔・バリが端子へ接触しない状態にする。加工粉を除き、J1装着前に周囲との絶縁を確認する。',
 '穴中心の最寄り既存穴まで約1.62mm。銅箔ランド外径は現物未確認。銅箔が近い場合は除去・絶縁し、削り過ぎを避ける。',
 '穴あけ・絶縁・保持ができない場合、この直付け案では組み立てない。幅と長さの維持を優先した試作設計で、加工の検証は未実施。',
 '別紙「原寸加工テンプレート」は100%で印刷。50mmの確認線を定規で測り、実物の穴配列と照合してから位置を写す。',
],10.5,25)
pages.append(p)

p=Page();header(p,4,'主基板S0の穴と部品面・はんだ面','7列の幅を維持してJ1を裏面中央へ置く。W01/W02をJ1の外側へ迂回。図の上下は両面ともUSB側が上。')
p.rect(36,115,354,550);p.rect(410,115,395,550);p.rect(825,115,330,550)
p.text(50,139,'S0 部品面 / USB上',13);p.text(424,139,'S0 はんだ面 / USB上',13)
f=board(p,125,183,3.2,parts=True,wires=False)
b=board(p,490,183,3.2,back=True,parts=False,wires=True)
onj1(p,f,False);onj1(p,b,True)
# Approximate insulated-wire paths on the component side; hidden under XIAO.
# BAT pads are located from the classic-v1 back drawing; physical labels take precedence.
for net,route in [('VBAT',[(10.11,22.23),(10.11,21.7),(7.4,21.7),(7.4,10.4865),(5.1,10.4865)]),('GND',[(8.11,22.23),(8.11,21),(6,21),(6,8.5815),(5.1,8.5815)])]:
 p.line([f(q) for q in route],COL[net],1.7,dash=True,halo=True)
 xx,yy=f(route[-1]);p.circle(xx,yy,3,'#e6c474',COL[net],1)
p.text(50,635,'赤丸H1 / 黒丸H2。破線はXIAO下のW07/W08。',9)

for pin,n in data['u1']['pins'].items():
 xx,yy=f(hole(n));p.text(48 if n[0]=='A' else 302,yy+3,n+' '+pin,9)
for pin,n in data['u2']['pins'].items():
 xx,yy=f(hole(n));p.text(48 if n[0]=='A' else 302,yy+3,n+' '+pin,9)
p.text(50,649,'H1/H2：新規穴の脚へW07/W08を接合（表面側）。',9)
p.text(50,662,'金色20箇所：ヘッダー。H1/H2の位置は3頁。',9)
p.text(429,641,'J1本体：裏面中央。配線は本体の外を通す。',9)
p.text(429,659,'W01はy27.4、W02はy29.0で横切る新経路。',9)
p.text(840,141,'配線先の早見',14)
p.lines(840,173,[
 'G3 → A12：W01 / 3V3（新経路）',
 'G2 → A13：W02 / GND（新経路）',
 'A5 → A15：W03 / SDA',
 'A6 → A14：W04 / SCL',
 '',
 'A2裏 → SW1-1：W05',
 'G2のXIAO上面 → SW1-3：W06',
 '',
 'XIAO BAT+ ← J1-1 / H1：W07',
 'XIAO BAT- ← J1-2 / H2：W08',
 '',
 'F16 → S2.B2 / J2-1：W09',
 'F12 → S2.C2 / J2-2：W10',
 '',
 'S0.G1/G17は穴がなく無配線。',
 'XIAOのBAT端子は載せる前に接合。',
 '交差部は非接続。途中の被覆はむかない。',
],10.5,26)
p.rect(36,690,1119,96,'#f2f6f9');p.lines(50,714,[
 'S0：AE-D-THの左7列を切り出す18×47mm案。使用穴117。主基板上の部品外形約19.05×50.15mm。',
 'J1本体も主基板の幅・長さ内へ収納。PH嵌合高さ8mmが裏へ追加される。電池・S2・電線・支持具と収納高さは別途確認。',
 '新規穴は非めっきでランド無し。穴へはんだを流しても固定できない。本体の機械保持が必須。旧S1の図は本書で置き換える。',
],10.5,23)
pages.append(p)

p=Page();header(p,5,'SW1・J2・LRAの物理ピンと組立確認','SW1-1/3を操作入力に使用。J2-1/2は本書で付ける参照番号。LRAは①②へ接続し⑤⑥は使わない。')
p.rect(36,117,350,314);p.rect(405,117,360,314);p.rect(784,117,371,314)
p.text(50,143,'SW1：押しボタン面から見る',13)
p.rect(133,190,152,126,'#f0f4f6','#8a9eab',5);p.circle(209,253,35,'#d34c50','#9e3034')
for xx,yy,nn in [(111,210,3),(307,210,1),(111,296,4),(307,296,2)]:
 p.circle(xx,yy,5,'#ead7a9','#9b824d');p.text(xx-4,yy-13,str(nn),12)
p.line([(111,210),(111,296)],GREY,1.3,True);p.line([(307,210),(307,296)],GREY,1.3,True)
p.lines(50,354,['SW1-1 → W05（D1） / SW1-3 → W06（GND）','SW1-2とSW1-4は無配線。1-2、3-4は内部で共通。','回転すると左右は変わる。実物の導通も確認する。'],9.5,23)
p.text(419,143,'S2・J2：ねじ端子の配置を定義',13)
# S2 is a local 4-column x 3-row 2.54 mm fragment, pin 1 at B2, pin 2 at C2.
ox,oy,ks=457,190,16
p.rect(ox,oy,10.16*ks,7.62*ks,'#e6f0e7','#7fa28a',0)
for j in range(4):
 for i in range(3):p.circle(ox+(1.27+j*2.54)*ks,oy+(1.27+i*2.54)*ks,3,'#ffffff','#8fa48f')
for j,cc in enumerate('ABCD'):p.text(ox+(1.27+j*2.54)*ks-3,oy-7,cc,9)
for i in range(3):p.text(ox-13,oy+(1.27+i*2.54)*ks+3,str(i+1),9)
p.rect(ox+2.31*ks,oy+.71*ks,5.54*ks,6.2*ks,'#d4e8d9','#6e937d',0)
for xx,nn in [(3.81,1),(6.35,2)]:
 p.circle(ox+xx*ks,oy+3.81*ks,9,'#dbe2e5','#748c9b');p.text(ox+xx*ks-4,oy+3.81*ks-18,str(nn),12)
p.text(463,337,'部品面 / 電線挿入口側を下',9,GREY)
p.lines(419,354,['J2-1＝S2.B2：脚へW09、ねじ側へW11。','J2-2＝S2.C2：脚へW10、ねじ側へW12。','S2はAE-D-TH残材4列×3行（約10.16×7.62mm）の案。'],9.5,23)
p.text(798,143,'M1：LRA LD14-002',13)
p.lines(798,185,[
 '① → W11 ← J2-1 / OUT+',
 '② → W12 ← J2-2 / OUT-',
 '③：無配線（①と内部共通）',
 '④：無配線（②と内部共通）',
 '⑤⑥：無配線（ケース端子）',
 '',
 '番号の向きは販売元端子図を参照。',
 'OUT+とOUT-はGNDへ接続しない。',
 '定格・電圧クランプ・校正は未確定。',
],11,24)

p.rect(36,455,554,329,'#f2f6f9');p.text(50,482,'組立・接続前の確認',14)
p.lines(50,511,[
 '1  裸基板でH1/H2を加工し、J1を裏面から仮合わせする（3頁）。',
 '2  電池とUSBを外す。W07/W08をXIAO底面のBAT±へ先に接合する。',
 '3  J1の脚へW07/W08を表面側で接合・絶縁。J1本体を保持する。',
 '4  XIAO/DRVを固定。W01/W02は新経路で配線。残りの線を接続する。',
 '5  各線の導通、隣接ピンの短絡、電源間の持続低抵抗短絡を確認。',
 '6  充電はXIAOのUSB-Cから。5V/VBUSや3V3へ電池を直結しない。',
 '',
 'GPIOボタンはINPUT_PULLUP。充電初回はP0.13をプルなし入力で約50mA。',
 '初回の電源・充電確認はDRV/LRAを外して行う。',
 '未実施：EDA ERC、実機組立、電源余裕、温度、充電終止、LRA、BLE、収納。',
],10.5,24)
p.rect(610,455,545,329,'#f2f6f9');p.text(625,482,'参照資料と追加部品',14)
p.lines(625,511,[
 '購入原本：ハッカソン購入部品一覧2026-10-23.docx',
 'XIAO番号：公式回路図U4（モジュールピン）。BAT±は裏面印字。',
 'https://wiki.seeedstudio.com/XIAO_BLE/',
 'DRV JP番号：Adafruit公式Eagle基板データ。ICの足番号ではない。',
 'https://github.com/adafruit/Adafruit-DRV2605-PCB',
 'JST PHの1番極：メーカーPH.pdf 2頁〈2P〉の図。',
 'https://akizukidenshi.com/goodsaffix/PH.pdf',
 'LRA端子：https://akizukidenshi.com/goodsaffix/LD14-002.png',
 '必要：0.8mm穴あけ工具・位置決め治具、絶縁材、J1本体の樹脂製押さえ。',
 'S1追加基板は不要。S2・本体の固定・全高・収納は現物で仮合わせする。',
],9.5,24)
pages.append(p)

pdf=OUT/'J1主基板一体型_実装配線図_ケースB_2026-10-28.pdf'
c=canvas.Canvas(str(pdf),pagesize=(W,H));c.setTitle('LRA専用 全ピン配線表と実装図 Rev J1 / 主基板一体化・ケースB')
for p in pages:renderPDF.draw(p.d,c,0,0);c.showPage()
c.save()
renderSVG.drawToFile(pages[2].d,str(OUT/'J1追加穴_加工詳細.svg'))
head=['線番号','色','接続元の部品ピン','接続元の穴面','接続先の部品ピン','接続先の穴面','信号','確定状況']
with (OUT/'全配線一覧_J1主基板一体型.csv').open('w',encoding='utf-8-sig',newline='') as f:
 wr=csv.writer(f);wr.writerow(head);wr.writerows(schedule)
checks={
 'user_battery_polarity_status':'case B confirmed by user measurement report; red on J1-2 and black on J1-1: -3.8 V',
 'j1_pin1':'S0.H1 new drill','j1_pin2':'S0.H2 new drill','j1_front_view':'front rectangular-window face toward viewer, legs down: pin1 right, pin2 left',
 'j1_top_view':'keyed/notched wall at top: pin1 left; mirror left/right for solder side',
 'pin1_is_not_intrinsically_plus_or_minus':True,'current_case_B':{'positive_pin':1,'negative_pin':2,'W07':['J1-1','S0.H1','U1.BAT+'],'W08':['J1-2','S0.H2','U1.BAT-']},'selected_case':'B','reported_voltage_V':-3.8,'measurement_source':'user report received 2026-10-28','user_reported_battery_polarity':{'J1-1':'+','J1-2':'-'},
 'switch_pins':{'1':'W05','3':'W06','2':'NC, internally common with 1','4':'NC, internally common with 3'},
 'terminal_reference_pins':{'J2-1':'S2.B2, OUT+','J2-2':'S2.C2, OUT-'},
 'connector_fixation':'J1 on S0 reverse, two new non-plated holes H1/H2; direct wire solder on front, mechanical body restraint required; no S1',
 'physical_test_performed':False,'eda_erc_performed':False,
 'drill_geometry':checks_geo,'j1_body_mm':J1BOX,'j1_keepout_mm':J1KEEP,'rear_wire_routes':data['wires'][:2],'wires':schedule,'factory_wires':factory,'xiao_module_pin_map':xrows,'driver_pin_map':drv,
 'assertions':{'12_unique_wires':True,'selected_case_B_preserved':True,'polarity_not_assumed':True,'LRA_only':True,'existing_S0_holes_reused':True,'driver_JP_pins_match_vendor_source':True},
 'unverified':['S0 drilling, J1 mechanical restraint, S2 fabrication and fit','connector revision and actual marks','live current/charge/LRA/thermal/radio behavior'],
}
(OUT/'全ピンと接続の照合記録.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2))
(OUT/'README.md').write_text("""# J1主基板一体型 Rev J1 / ケースB

J1を同じAE-D-TH切出しS0の裏面へ直付けする試作案。別基板S1を廃止。幅優先で従来のS0 18×47mm、部品の平面外形約19.05×50.15mmを維持する。J2用S2は基板外の従来構成。

新規穴：H1=(10.11,22.23)mm→J1-1/+、H2=(8.11,22.23)mm→J1-2/-。原点はS0表面の左上、USB上。穴径0.8mm、2mm間隔。裏面で左右反転する。既存の2.54mm穴へ直挿ししない。

ユーザー測定報告：赤J1-2/黒J1-1で-3.8V、ケースB。W07はJ1-1/H1→BAT+、W08はJ1-2/H2→BAT-。追加穴は非めっき。電線と端子を表面で直接接合・絶縁し、本体を樹脂製押さえとグリップ側ホルダーで保持する。機械保持は必須で、形状・強度は未検証。はんだだけで基板に固定できない。

W01/W02をJ1の裏面占有範囲から迂回。旧図の配線経路・S1の穴名は使わない。ピン接続は同じ。全12本の接続表CSVを同梱。

裏面PHの嵌合高さは基板面から8mm＋電線曲げ余裕。全高=表面実装高さ+S0厚1.6mm+裏面8mm+絶縁/固定/電線余裕。グリップ内径と収納は未確認。電池は基板外へ保持。

原寸テンプレートは100%印刷で50mm確認線と実物の既存穴を照合する。最適化は「同じAE-D-TH・幅長さ維持・J1固定」を優先した候補比較で、数学的な全組合せの最適解や実機適合を保証しない。実機穴あけ・組立・通電・EDA ERC・保持強度・収納は未検証。
""")
print(json.dumps({'pdf':str(pdf),'pages':5,'wires':12,'polarity':'case B, integrated into S0 reverse with H1/H2'},ensure_ascii=False))

from reportlab.lib.pagesizes import A4
MM=72/25.4
pt=OUT/'J1追加穴_原寸加工テンプレート.pdf'
c=canvas.Canvas(str(pt),pagesize=A4);c.setFont(FONT,15)
c.drawString(35,805,'J1追加穴：S0表面から見る原寸テンプレート')
c.setFont(FONT,10)
for i,t in enumerate(['100%・実際のサイズで印刷。用紙に合わせる拡大縮小はOFF。','下の50mm確認線と既存穴ピッチを定規で照合してから使う。','J1を裏面へ差し込む。H1=1番+、H2=2番-（ケースB）。']):c.drawString(35,780-i*19,t)
ox,oy=70,550
c.setStrokeColor(toColor('#183448'));c.setLineWidth(.5);c.rect(ox,oy,18*MM,47*MM)
for h in HOLES:
 x,y=hole(h);c.circle(ox+x*MM,oy+(47-y)*MM,.5*MM,stroke=1,fill=0)
for n,(x,y) in J1P.items():
 px,py=ox+x*MM,oy+(47-y)*MM
 c.setStrokeColor(toColor('#cc3c36'));c.circle(px,py,.4*MM,stroke=1,fill=0)
 c.line(px-3,py,px+3,py);c.line(px,py-3,px,py+3)
 c.setFont(FONT,9);c.drawString(150,py+(9 if n=='H1' else -9),n+(' / J1-1 +   x10.11 y22.23' if n=='H1' else ' / J1-2 -   x8.11 y22.23'))
 c.line(px,py,145,py+(9 if n=='H1' else -9))
c.setStrokeColor(toColor('#183448'));c.drawString(70,oy+47*MM+14,'USB側 / 表面')
c.drawString(35,515,'S0：18×47mm。新規穴径0.8mm。穴間隔2.00±0.05mmを目標。')
c.drawString(35,493,'穴は非めっき。周囲銅箔との絶縁と、J1本体の機械保持が必要。')
c.line(70,450,70+50*MM,450)
for xx in [70,70+50*MM]:c.line(xx,444,xx,456)
c.drawString(70,430,'印刷寸法確認：この線が50.00mmであること')
c.drawString(35,390,'原点：S0表面の左上。xは右向き、yは下向き。単位mm。')
c.drawString(35,369,'H1/H2は行8と行9の中間。D列中心から左右へ各1mm。')
c.drawString(35,348,'実物の穴配置と原点が一致しない場合は、この紙で穴位置を写さない。')
c.drawString(35,305,'Rev J1 / 2026-10-28 / 実機加工・収納・強度・通電は未検証。')
c.showPage();c.save()
print('A4 drill template:',pt)

renderSVG.drawToFile(pages[3].d,str(OUT/'J1一体型_配置配線.svg'))
