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
 p.text(36,H-22,'2026-10-28 / Rev F1   J1極性は未測定。確認後に電池配線を確定する。実機試験・EDA ERCは未実施。',9,GREY)
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
 ['W07','赤','J1の電池+と導通するピン','S1.B2 または C2','U1 BAT+（底面パッド）','S0の穴ではない','VBAT','3頁の測定後に確定'],
 ['W08','黒','J1の電池-と導通するピン','S1.B2 または C2','U1 BAT-（底面パッド）','S0の穴ではない','GND','3頁の測定後に確定'],
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

pages=[]
p=Page();header(p,1,'全配線一覧：どのピンから、どのピンへ','S0＝主基板 / S1＝J1用2.0mmピッチ小基板（追加）/ S2＝J2用2.54mmピッチ小基板（AE-D-TH残材の案）')
recs=[[r[0],r[1],r[2],r[3],r[4],r[5],r[7]] for r in schedule]
end=table(p,36,117,[45,68,220,158,235,180,173],['線','色','接続元の部品・ピン','接続元の穴・面','接続先の部品・ピン','接続先の穴・面','状態'],recs,32,9.3)
table(p,36,end+18,[55,85,330,320,289],['既設線','色','電池側','J1との対応','作業'],factory,31,10)
p.rect(36,667,1119,119,'#fff7e8','#d6bc8a')
p.lines(50,690,[
 'J1の極性はユーザー回答「未測定」。1番/2番を+/-と決めつけない。3頁の測定結果A/Bを選んでW07/W08を確定する。',
 'J1はS1へ基板実装し、本体ごとグリップに固定する。J1の脚へ電線だけを付けて浮かせる旧案は本書では採用しない。',
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

p=Page();header(p,3,'J1・LiPo・S1：ピン番号と極性の確定','B2B-PH-K-Sは2.0mmピッチ基板へ実装。J1-1＝S1.B2、J1-2＝S1.C2。現物の電池極性を測定してから接続する。')
p.rect(36,116,340,266);p.rect(394,116,370,266);p.rect(782,116,373,266)
p.text(50,140,'J1正面：メーカー〈2P〉図と同じ向き',12)
p.rect(117,166,175,108,'#fffaf0','#a7926c',0)
p.rect(195,166,23,79,'#ffffff','#a7926c',0)
for x in [143,246]:p.rect(x,210,23,36,'#ffffff','#a7926c',0)
p.line([(162,274),(162,315)],'#ae965f',6);p.line([(247,274),(247,315)],'#ae965f',6)
p.text(152,336,'2',17);p.text(238,336,'1',17)
p.text(50,365,'中央の縦窓が見える面をこちら、脚を下。右が1番。',9.5)
p.text(408,140,'S1部品面：切り欠きの壁を上にする',12)
gx,gy,k=445,170,21
def smallgrid(p,ox,oy,pitch=2,back=False,cols=4,rs=4):
 width=cols*pitch
 p.rect(ox,oy,width*k,rs*pitch*k,'#e6f0e7','#7fa28a',0)
 for j in range(cols):
  for i in range(rs):
   xx=ox+((width-(1+j*pitch)) if back else (1+j*pitch))*k;yy=oy+(1+i*pitch)*k
   p.circle(xx,yy,3,'#ffffff','#8fa48f',.7)
 for j in range(cols):p.text(ox+(1+j*pitch)*k-3,oy-6,('DCBA' if back else 'ABCD')[j],9)
 for i in range(rs):p.text(ox-12,oy+(1+i*pitch)*k+3,str(i+1),9)
smallgrid(p,gx,gy)
# S1 contact assignment uses the pin-1 side at the left; rotate physical front face to far/top edge.
p.rect(gx+1.05*k,gy+1.3*k,5.9*k,4.5*k,'#fffaf0','#a7926c',0)
p.rect(gx+3.5*k,gy+1.3*k,1*k,.6*k,'#e6f0e7','#a7926c',0)
for pos,lab in [(3,'1'),(5,'2')]:
 p.circle(gx+pos*k,gy+3*k,6,'#e5c675','#8c7549');p.text(gx+pos*k-4,gy+3*k+22,lab,12)
p.lines(635,183,['1 → B2','2 → C2','','2mmピッチ','4列×4行の例','外形約8mm角'],10.5,23)
p.text(408,365,'B2/C2は本書で付けたローカル穴名。中央切り欠き面が上。',9)
p.text(796,140,'S1はんだ面：上図を左右に裏返す',12)
sx,sy=830,170;smallgrid(p,sx,sy,back=True)
for world,lab in [(3,'1 / B2'),(5,'2 / C2')]:
 xx=sx+(8-world)*k;yy=sy+3*k;p.circle(xx,yy,6,'#cbd5dc','#7f939f');p.text(xx-18,yy+28,lab,9.5)
p.lines(1010,186,['左が2番','右が1番','','裏返しても','穴名は変えない'],11,25)
p.text(796,365,'はんだ面の脚へW07/W08を接合。J1本体は基板ごと保持。',9)

p.text(36,414,'未測定のため、測定後にAかBの一方を採用する',16,'#a15d20')
choice=[
 ['A','赤プローブJ1-2 / 黒J1-1で正の数V','J1-2 = S1.C2 → U1 BAT+','J1-1 = S1.B2 → U1 BAT-'],
 ['B','同じ当て方で負の数V','J1-1 = S1.B2 → U1 BAT+','J1-2 = S1.C2 → U1 BAT-'],
]
table(p,36,432,[45,353,360,361],['採用','直流電圧の測定結果','W07 赤線','W08 黒線'],choice,41,10)
p.rect(36,570,1119,216,'#fff7e8','#d6bc8a');p.text(50,594,'測定方法と記録欄',14)
p.lines(50,622,[
 'S1をXIAO・USB・他回路から切り離す。W07/W08をXIAOへ接続する前に、電池の付属PHRをJ1へ挿す。',
 'テスターは直流電圧モード。赤リードはV入力、黒はCOM。赤をJ1-2、黒をJ1-1へ当て、隣の端子を短絡させない。',
 '表示の符号でA/Bを決める。0V・不安定・想定外の電圧なら判定せず確認する。導通/抵抗モードや電流入力端子で電池を測らない。',
 '確認後は電池を外してW07/W08を接合する。電池本体、付属線、PHR内の圧着端子は切断・再はんだしない。',
 '記録：測定電圧 ______ V  ／ 採用 A・B ______  ／ J1-1は +・- ______  ／ 日付 ______  ／ 確認者 ______',
 'S1は追加部品：2.0mmピッチ基板（例：秋月104022）を小片にする案。専用変換基板を使う場合は実物の番号/導通を改めて照合。',
],10.2,25)
pages.append(p)

p=Page();header(p,4,'主基板S0の穴と部品面・はんだ面','既存の細長い7列案を継承。J1とJ2はS0へ無理に詰め込まず、S1/S2上に固定しグリップ内で支持する。')
p.rect(36,115,354,550);p.rect(410,115,395,550);p.rect(825,115,330,550)
p.text(50,139,'S0 部品面 / USB上',13);p.text(424,139,'S0 はんだ面 / USB上',13)
f=board(p,125,183,3.2,parts=True,wires=False)
b=board(p,490,183,3.2,back=True,parts=False,wires=True)
for pin,n in data['u1']['pins'].items():
 xx,yy=f(hole(n));p.text(48 if n[0]=='A' else 302,yy+3,n+' '+pin,9)
for pin,n in data['u2']['pins'].items():
 xx,yy=f(hole(n));p.text(48 if n[0]=='A' else 302,yy+3,n+' '+pin,9)
p.text(50,648,'金色の20箇所：ヘッダーの固定穴。色輪：電線の追加。',9)
p.text(429,648,'W09/W10 → S2上のJ2-1/J2-2。BAT±はS0の穴ではない。',9)
p.text(840,141,'配線先の早見',14)
p.lines(840,173,[
 'G3 → A12：W01 / 3V3',
 'G2 → A13：W02 / GND',
 'A5 → A15：W03 / SDA',
 'A6 → A14：W04 / SCL',
 '',
 'A2裏 → SW1-1：W05',
 'G2のXIAO上面 → SW1-3：W06',
 '',
 'XIAO BAT+ ← S1の+側：W07',
 'XIAO BAT- ← S1の-側：W08',
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
 'この外形にS1/S2・電池・ボタン・振動子・電線・絶縁・支持具は含めない。全体のグリップ収納と高さは未確認。',
 'J1を2mm小基板S1へ固定する方式が最新版。以前の「J1脚へ電線だけを付ける」図は本書で置き換える。',
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
 '1  S1のJ1極性を測定して3頁のA/Bを記録する。',
 '2  電池とUSBを外す。XIAO底面のBAT±を先に配線・絶縁する。',
 '3  S0へヘッダー固定後、W01-W06を指定ピンへ接続する。',
 '4  S1/S2の基板とコネクターを保持し、W07-W12を接続する。',
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
 '追加が必要：S1用2.0mmピッチ基板（例：秋月104022）、絶縁・固定材。',
 'S1/S2の外形・固定・グリップ収納は設計案。現物で仮合わせする。',
],9.5,24)
pages.append(p)

pdf=OUT/'LRA専用_全ピン配線表と実装図_2026-10-28.pdf'
c=canvas.Canvas(str(pdf),pagesize=(W,H));c.setTitle('LRA専用 全ピン配線表と実装図 Rev F1')
for p in pages:renderPDF.draw(p.d,c,0,0);c.showPage()
c.save()
renderSVG.drawToFile(pages[2].d,str(OUT/'電池PHコネクター_ピン番号と極性確認.svg'))
head=['線番号','色','接続元の部品ピン','接続元の穴面','接続先の部品ピン','接続先の穴面','信号','確定状況']
with (OUT/'全配線一覧_極性確認前.csv').open('w',encoding='utf-8-sig',newline='') as f:
 wr=csv.writer(f);wr.writerow(head);wr.writerows(schedule)
for name,case in cases.items():
 out=[r.copy() for r in schedule]
 for r in out:
  if r[0] in ['W07','W08']:
   m=case[r[0]];r[2]=m[0];r[3]=m[1];r[7]='ケース'+name+'を測定確認後に採用'
 with (OUT/('全配線一覧_ケース'+name+'.csv')).open('w',encoding='utf-8-sig',newline='') as f:
  wr=csv.writer(f);wr.writerow(head);wr.writerows(out)
checks={
 'user_battery_polarity_status':'unmeasured, confirmed by user',
 'j1_pin1':'S1.B2','j1_pin2':'S1.C2','j1_front_view':'front rectangular-window face toward viewer, legs down: pin1 right, pin2 left',
 'j1_top_view':'keyed/notched wall at top: pin1 left; mirror left/right for solder side',
 'pin1_is_not_intrinsically_plus_or_minus':True,'battery_cases':cases,
 'switch_pins':{'1':'W05','3':'W06','2':'NC, internally common with 1','4':'NC, internally common with 3'},
 'terminal_reference_pins':{'J2-1':'S2.B2, OUT+','J2-2':'S2.C2, OUT-'},
 'connector_fixation':'J1 soldered into additional 2mm-pitch S1, S1 secured mechanically; not floating on leads',
 'physical_test_performed':False,'eda_erc_performed':False,
 'wires':schedule,'factory_wires':factory,'xiao_module_pin_map':xrows,'driver_pin_map':drv,
 'assertions':{'12_unique_wires':True,'both_battery_polarity_cases_covered':True,'polarity_not_assumed':True,'LRA_only':True,'existing_S0_holes_reused':True,'driver_JP_pins_match_vendor_source':True},
 'unverified':['physical battery polarity','S1/S2 fabrication and fit','connector revision and actual marks','live current/charge/LRA/thermal/radio behavior'],
}
(OUT/'全ピンと接続の照合記録.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2))
(OUT/'README.md').write_text('''# LRA専用 全ピン配線表 Rev F1

最新の指示に合わせてLRA専用とし、LiPo・J1・全配線のピン名/番号/基板穴を示した。J1は2mm小基板S1へ基板実装する。以前の浮かせたJ1接合案は採用しない。

ユーザー回答：電池PH極性は未測定。W07/W08のみ測定で確定する。PDF3頁のケースA/Bを選択し、対応CSVを使う。1番/2番に固定の電池極性があると仮定しない。

S0：既存AE-D-TH切出し7列案。S1：追加の2mm基板4列×4行の例。S2：AE-D-TH残材4列×3行の例。S1/S2の穴名はこの設計で付けたローカル名で、購入製品に印字されているとは限らない。切断・固定・収納は未検証。

J1-1/2はメーカーの1番極定義。J2-1/2は本書で定義する参照番号。XIAO1-14は公式回路図U4のモジュール端子番号で、MCUの足番号/Arduino GPIO番号ではない。BATパッドは底面印字で識別する。

PDF5頁、確認前/ケースA/ケースBのCSV、J1のSVG、機械可読JSONを出力。現物試験・EDA ERCは未実施。
''')
print(json.dumps({'pdf':str(pdf),'pages':5,'wires':12,'polarity':'unmeasured / A-B cases included'},ensure_ascii=False))
