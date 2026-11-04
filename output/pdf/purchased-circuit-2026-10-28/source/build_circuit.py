"""Purchased-parts module-level circuit. Generates PDF, SVG, CSV and net checks."""
from pathlib import Path
import csv,json,hashlib,zipfile,xml.etree.ElementTree as E
from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import A3,landscape
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.graphics.shapes import Drawing,Rect,Line,Circle,String,PolyLine,Polygon
from reportlab.graphics import renderPDF,renderSVG
from reportlab.lib.colors import toColor

OUT=Path(__file__).resolve().parents[1];ROOT=OUT.parents[2]
SOURCE=Path('/Users/akiyoshishuta/Documents/開発分/HeroesLeague/ハッカソン購入部品一覧2026-10-23.docx')
FONT='NotoSansJP'
pdfmetrics.registerFont(TTFont(FONT,str(ROOT/'output/pdf/ae-d-th-layout-2026-10-28/source/NotoSansJP.ttf')))
W,H=landscape(A3);INK='#153246';GREY='#536a7c';BORDER='#ccd9e1'
C={'3V3':'#cc3c36','GND':'#25343e','SDA':'#147bb6','SCL':'#b28712','BUTTON':'#268755','VBAT':'#cc3c36','OUT+':'#b84f9c','OUT-':'#7350a2','USB':'#b66a29'}
ns={'w':'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
xml=E.fromstring(zipfile.ZipFile(SOURCE).read('word/document.xml'))
inventory=[]
for table in xml.findall('.//w:tbl',ns):
    for row in table.findall('w:tr',ns):
        vals=[''.join(x.text or '' for x in c.findall('.//w:t',ns)) for c in row.findall('w:tc',ns)]
        if len(vals)>=5 and vals[0].isdigit():inventory.append(vals)
assert len(inventory)==11,inventory
assert all(any(s in ' '.join(row) for row in inventory) for s in ['XIAO nRF52840','LD14-002','316040001','B2B-PH-K-S','WJEK254','AE-D-TH','118293','PH-1x40SG','DRV2605L','DTP502035','TVDP01-060CR'])

wires=[
 ['W01','3V3','赤','U1.3V3','G3','U2.VIN','A12','従来図と同じ'],
 ['W02','GND','黒','U1.GND','G2','U2.GND','A13','従来図と同じ'],
 ['W03','SDA','青','U1.D4 / P0.04','A5','U2.SDA','A15','I²Cデータ'],
 ['W04','SCL','黄','U1.D5 / P0.05','A6','U2.SCL','A14','I²Cクロック'],
 ['W05','BUTTON','緑','U1.D1 / P0.03','A2','SW1.接点a','外付け','INPUT_PULLUP / 押下LOW'],
 ['W06','GND','黒','U1.GND 上面取出','G2上面','SW1.接点b','外付け','裏面へ複数線を押し込まない'],
 ['W07','VBAT','赤','U1.BAT+ 底面','底面印字','J1.電池+対応側','PH 2P','左右・ピン番号は実測照合'],
 ['W08','GND','黒','U1.BAT- 底面','底面印字','J1.電池-対応側','PH 2P','電池を外してはんだづけ'],
 ['W09','OUT+','紫','U2.OUT+','F16','J2.接続A（+）','外付け','本図では端子台へ接続'],
 ['W10','OUT-','紫・印付き','U2.OUT-','F12','J2.接続B（-）','外付け','本図では端子台へ接続'],
 ['W11','OUT+','紫','J2.接続A（+）','ねじ端子','M1.LRA ①','端子図照合','端子台からLRAへ追加する線'],
 ['W12','OUT-','紫・印付き','J2.接続B（-）','ねじ端子','M1.LRA ②','端子図照合','端子台からLRAへ追加する線'],
]
nets={
 'VBAT':['BT1.+','J1.plus_mating_side','U1.BAT+'],
 'GND':['BT1.-','J1.minus_mating_side','U1.BAT-','U1.GND','U2.GND','SW1.b','USB.GND'],
 '3V3':['U1.3V3','U2.VIN'],
 'SDA':['U1.D4','U2.SDA'],
 'SCL':['U1.D5','U2.SCL'],
 'BUTTON':['U1.D1','SW1.a'],
 'OUT+':['U2.OUT+','J2.A','M1.1'],
 'OUT-':['U2.OUT-','J2.B','M1.2'],
 'USB_5V':['USB.VBUS','U1.USB_C_VBUS'],
}
assert set(nets['OUT+']).isdisjoint(nets['OUT-'])
assert set(nets['OUT+']+nets['OUT-']).isdisjoint(nets['GND'])
assert 'U2.VIN' in nets['3V3'] and 'U2.VIN' not in nets['VBAT']+nets['USB_5V']
flat=[n for nn in nets.values() for n in nn];assert len(flat)==len(set(flat))
q=E.parse(ROOT/'tmp/pdfs/ae-d-th/sources/drv-qt.brd')
mapping={s.get('name'):[(c.get('element'),c.get('pad')) for c in s.findall('contactref')] for s in q.findall('.//signals/signal')}
for name,pad in [('VCC','1'),('GND','2'),('SCL','3'),('SDA','4'),('IN/TRIG','5')]:assert ('JP2',pad) in mapping[name]
assert ('JP1','1') in mapping['OUT+'] and ('JP3','1') in mapping['OUT-']
layout=json.loads((ROOT/'output/pdf/ae-d-th-layout-2026-10-28/配置と配線.json').read_text())
assert layout['u1']['pins']['D4']=='A5' and layout['u1']['pins']['D5']=='A6'
assert layout['u2']['pins']['OUT+']=='F16' and layout['u2']['pins']['OUT-']=='F12'

class Page:
 def __init__(self):self.d=Drawing(W,H)
 def rect(self,x,y,w,h,fill='#ffffff',stroke=BORDER,r=5,lw=1):
  self.d.add(Rect(x,H-y-h,w,h,fillColor=toColor(fill) if fill else None,strokeColor=toColor(stroke) if stroke else None,strokeWidth=lw,rx=r,ry=r))
 def text(self,x,y,t,size=11,color=INK,anchor='start'):
  self.d.add(String(x,H-y,t,fontName=FONT,fontSize=size,fillColor=toColor(color),textAnchor=anchor))
 def lines(self,x,y,ss,size=11,color=GREY,lead=18):
  for s in ss:self.text(x,y,s,size,color);y+=lead
 def wire(self,ps,color=INK,lw=1.7,dash=False):
  self.d.add(PolyLine([v for x,y in ps for v in (x,H-y)],strokeColor=toColor(color),strokeWidth=lw,fillColor=None,strokeDashArray=[5,4] if dash else None))
 def circle(self,x,y,r=2.5,fill='#ffffff',stroke=INK,lw=1):
  self.d.add(Circle(x,H-y,r,fillColor=toColor(fill) if fill else None,strokeColor=toColor(stroke) if stroke else None,strokeWidth=lw))
 def cross(self,x,y,size=4):
  self.wire([(x-size,y-size),(x+size,y+size)],GREY,1);self.wire([(x-size,y+size),(x+size,y-size)],GREY,1)
 def arrow(self,ps,color=INK,lw=1.7,dash=False):
  import math
  self.wire(ps,color,lw,dash);a,b=ps[-2:];ang=math.atan2(b[1]-a[1],b[0]-a[0]);r=7
  pts=[b,(b[0]-r*math.cos(ang-.5),b[1]-r*math.sin(ang-.5)),(b[0]-r*math.cos(ang+.5),b[1]-r*math.sin(ang+.5))]
  self.d.add(Polygon([v for x,y in pts for v in (x,H-y)],fillColor=toColor(color),strokeColor=None))
 def header(self,n,title,sub):
  self.text(36,31,'HeroesLeague / 白杖振動デバイス',10,GREY)
  self.text(36,62,title,24)
  self.text(36,84,sub,10,GREY)
  self.wire([(36,94),(W-36,94)],BORDER,1)
  self.text(36,H-22,'2026-10-28 / Rev P1   部品単位の接続設計。現物加工・通電・収納は未検証。',9,GREY)
  self.text(W-75,H-22,f'{n} / 3',10,GREY)

pages=[]
p=Page();p.header(1,'購入部品に対応した全体回路図','LRAを使用する基本回路 / 購入済み端子台を使用 / 実装位置・縮尺は回路図と別に確認する')

# iPhone and USB supply.
p.rect(40,110,220,70,'#eef4f8');p.text(55,135,'iPhone 16',16);p.text(55,157,'障害物判定 → BLE通知',11)
p.arrow([(260,145),(320,145),(320,230),(400,230)],'#50799c',1.8,True)
p.text(300,198,'BLE 無線',10,'#50799c')
p.rect(400,110,220,60,'#fbf4e9');p.text(415,134,'PC / 5V USB電源',14);p.text(415,156,'USB-Cケーブル → XIAO内蔵端子',10)
p.arrow([(510,170),(510,200)],C['USB'],2);p.text(520,191,'給電・充電',10,C['USB'])

# Modules.
p.rect(400,200,220,410,'#f1f6fa','#7898ad',7,1.5)
p.text(414,220,'U1  XIAO nRF52840',15);p.text(414,237,'非Sense / 秋月 117341',10,GREY)
p.rect(745,210,165,230,'#f1f6fa','#7898ad',7,1.5)
p.text(756,230,'U2  DRV2605L',14);p.text(756,246,'Adafruit / STEMMA QT版',9,GREY)
for yy,label,net,ident in [(265,'3V3 [G3]','3V3','W01'),(300,'GND [G2]','GND','W02'),(335,'D4 / SDA [A5]','SDA','W03'),(370,'D5 / SCL [A6]','SCL','W04')]:
 p.circle(620,yy,3,C[net],C[net]);p.circle(745,yy,3,C[net],C[net])
 p.text(610,yy-5,label,10,INK,'end')
 lab={'3V3':'VIN [A12]','GND':'GND [A13]','SDA':'SDA [A15]','SCL':'SCL [A14]'}[net]
 p.text(753,yy-5,lab,10)
 p.wire([(620,yy),(745,yy)],C[net],2.2);p.text(647,yy-6,ident+'  '+net,9,C[net])
p.lines(416,465,['内蔵USB充電回路','電池は底面BAT+ / BAT-へ','GNDとBAT-は基板内で共通','P0.13：初回はHi-Z / 約50mA'],11,GREY,20)
p.lines(756,400,['I²Cアドレス 0x5A','SDA/SCL: 10kΩ → VIN 実装済み','QT×2、IN(INT/TRIG) は未接続'],9,GREY,16)
p.wire([(827,440),(827,455)],GREY,1);p.cross(827,455);p.text(840,459,'IN: NC',9,GREY)

# Battery + PH mating pair. Logical +/- do not invent numbered pin orientation.
p.rect(40,300,165,150,'#f5f8fa');p.text(52,325,'BT1  LiPo電池',15)
p.lines(52,352,['DTP502035(PHR)','3.7V / 300mAh','保護回路内蔵'],11,GREY,24)
p.text(192,357,'+',13,C['VBAT']);p.text(192,417,'-',13,C['GND'])
p.rect(245,300,105,150,'#fffaf2');p.text(255,325,'J1  PH 2P',12)
p.text(250,477,'B2B-PH-K-S',10);p.text(250,493,'2.0mmピッチ',9,GREY)
for yy,net,sign,ident in [(350,'VBAT','+対応側','W07'),(410,'GND','-対応側','W08')]:
 p.wire([(205,yy),(245,yy)],C[net],2.2)
 p.circle(245,yy,3,'#ffffff',C[net]);p.circle(350,yy,3,'#ffffff',C[net])
 p.wire([(245,yy),(350,yy)],C[net],2.2)
 p.text(265,yy-8,sign,10,C[net])
 p.wire([(350,yy),(400,yy)],C[net],2.2);p.text(355,yy-7,ident,9,C[net])
 p.circle(400,yy,3,C[net],C[net]);p.text(411,yy+4,'BAT+ 底面' if net=='VBAT' else 'BAT- 底面',11)
p.text(43,472,'電池側の付属PHRコネクターを使用',10,GREY)
p.text(43,490,'電池本体・付属リード線は加工しない',10,GREY)
p.lines(43,535,['J1の左右とピン番号は極性実測後に確定。','図中の「+対応側」「-対応側」は電気的な管理名。','形状が合っても逆極性がないことを確認する。'],10,GREY,19)

# Driver outputs via purchased terminal block.
p.rect(950,250,70,135,'#f6f1f7');p.text(950,232,'J2  2極端子台',11)
p.rect(1070,250,85,145,'#f6f1f7');p.text(1076,272,'M1  LRA',12)
p.text(1076,355,'LD14-002',10);p.text(1076,375,'⑤⑥: NC',9,GREY)
for yy,net,jterm,mterm,a,b in [(295,'OUT+','A (+)','①','W09','W11'),(340,'OUT-','B (-)','②','W10','W12')]:
 p.circle(910,yy,3,C[net],C[net]);p.text(905,yy-6,net,10,C[net],'end')
 p.wire([(910,yy),(950,yy)],C[net],2.2);p.text(914,yy-8,a,8.5,C[net])
 p.circle(962,yy,3,'#ffffff',C[net]);p.circle(1008,yy,3,'#ffffff',C[net]);p.wire([(950,yy),(1020,yy)],C[net],2.2)
 p.text(971,yy-9,jterm,9,C[net])
 p.wire([(1020,yy),(1070,yy)],C[net],2.2);p.text(1027,yy-8,b,8.5,C[net])
 p.circle(1070,yy,3,'#ffffff',C[net]);p.text(1077,yy+5,mterm,12,C[net])
p.text(929,405,'WJEK254 / 2.54mmピッチ',9,GREY)
p.text(929,422,'A/Bは本図の管理名。実物へ + / - を表示。',9,GREY)

# External button. Two physical contacts, not a power switch.
p.rect(765,500,220,120,'#eff7f1');p.text(777,520,'SW1 操作ボタン / TVDP01-060CR',11)
for yy,lab,net,ident in [(545,'D1 / P0.03 [A2]','BUTTON','W05'),(590,'GND [G2上面]','GND','W06')]:
 p.circle(620,yy,3,C[net],C[net]);p.text(610,yy-6,lab,10,INK,'end')
 p.wire([(620,yy),(765,yy)],C[net],2.2);p.text(675,yy-7,ident,9,C[net])
p.wire([(765,545),(820,545)],C['BUTTON'],2);p.circle(820,545,3,'#ffffff',C['BUTTON'])
p.wire([(820,545),(880,529)],C['BUTTON'],2)
p.circle(930,545,3,'#ffffff',C['GND']);p.wire([(930,545),(930,590),(765,590)],C['GND'],2)
p.text(790,564,'a: ①②の側',9,GREY);p.text(886,564,'b: ③④の側',9,GREY)
p.text(777,610,'押下LOW / 電源を切るスイッチではない',9,GREY)
p.text(414,576,'INPUT_PULLUP',10,GREY)

p.rect(1020,485,135,125,'#fafafa',BORDER);p.text(1030,507,'M2 ERM 交換評価用',10)
p.lines(1030,531,['316040001','通常は未接続','M1を外して交換','ERM用設定へ変更'],10,GREY,18)
p.text(40,642,'実装：AE-D-TH / AWG26 / PH-1x40SG。J1・J2・電池・ボタン・振動子は主基板外へ固定する。',11)

notes=[
 (40,'電池と充電',[
  'USB-C → XIAO内蔵充電回路 → BAT端子 → 電池。',
  '電池の充電上限4.20V、標準充電60mA。',
  '初回はP0.13をプルなし入力にして約50mA。',
  'P0.13は内部制御ピン。D13等とは区別する。',
  '電池・USBを外して接合し、極性と短絡を確認。']),
 (415,'購入済みPHコネクターの接合',[
  'J1は基板取付用2mm品。AE-D-THへ無理に挿さない。',
  '短い脚へAWG26を接合し、各脚を個別に絶縁。',
  '本体を保持し、抜き差しの力をはんだ部へかけない。',
  '熱収縮チューブ・支持具の保有は未確認。',
  '変換基板を使う場合は別途追加部品になる。']),
 (790,'振動子と3.3V電源',[
  'DRVのVINは3V3。VBAT・USB 5Vへ直結しない。',
  'LRA両端はOUT+ / OUT-へ。GNDへは接続しない。',
  'LRAの定格Vrms・電流・クランプ設定は未確定。',
  '確定前に最大出力・自動校正を行わない。',
  '3.3V電源の余裕、温度・充電・動作は実測が必要。']),
]
for xx,head,ss in notes:
 p.rect(xx,668,365,125,'#f2f6f9');p.text(xx+12,690,head,12);p.lines(xx+12,712,ss,9.5,GREY,16)
pages.append(p)

# 2: Exact wire list plus terminal block bypass / connector detail.
p=Page();p.header(2,'配線表とコネクターの接続','W01-W08は前の実装図を継承。W09/W10の行先をJ2とし、J2からLRAへW11/W12を追加。')
xs=[40,94,160,202,415,489,702,789,1155]
heads=['線番号','信号','色','接続元','穴・位置','接続先','穴・位置','用途・注意']
top=120;rowh=32
for j in range(8):
 p.rect(xs[j],top,xs[j+1]-xs[j],30,'#dfeaf1',BORDER,r=0);p.text(xs[j]+6,top+20,heads[j],10)
for i,w in enumerate(wires):
 yy=top+30+i*rowh
 vals=[w[0],w[1],w[2],w[3],w[4],w[5],w[6],w[7]]
 for j,v in enumerate(vals):
  p.rect(xs[j],yy,xs[j+1]-xs[j],rowh,'#f6f9fb' if i%2==0 else '#ffffff',BORDER,r=0,lw=.5)
  p.text(xs[j]+6,yy+21,v,9 if j in [2,4,6] else 9.5,C[w[1]] if j in [0,1,2] else INK)
yy=555
p.rect(40,yy,545,215,'#f4f7f9');p.text(55,yy+25,'最小構成で端子台J2を省く場合',14)
p.lines(55,yy+52,[
 'W09：U2 OUT+ [F16] → LRA①へ直接接続。',
 'W10：U2 OUT- [F12] → LRA②へ直接接続。',
 'W11 / W12 とJ2を省略する。電気的な接続先は同じ。',
 '端子台あり：12本。端子台なし：10本。',
 'USBケーブルと電池に付属する線はこの本数に含めない。',
 '端子台あり版は交換評価向け。最小収納を優先する場合は省略可。',
 'いずれもERMとLRAを同時接続しない。',
],11,GREY,21)
p.rect(610,yy,545,215,'#f4f7f9');p.text(625,yy+25,'PH電池接続の作業順',14)
p.lines(625,yy+52,[
 '1  電池をJ1から外し、USBも抜く。',
 '2  J1の短い基板用脚と、XIAOのBAT端子を電線で接続する。',
 '3  J1の2脚を個別に絶縁し、コネクター本体を固定する。',
 '4  電池側の極性を直流電圧モードで確認し、J1との対応を照合。',
 '5  接続部の短絡がないことを確認してから電池を挿す。',
 '電池本体や付属リード線へのはんだづけ・切断は不要。',
 '主基板の穴へJ1の脚を広げて無理に押し込まない。',
],11,GREY,21)
p.text(40,800,'A-G・1-17は先の細長基板図の座標。G1/G17は元の取付穴に重なり未使用。図面は実物の左右と照合して使う。',10,GREY)
pages.append(p)

# 3: purchased inventory and traceable limits.
p=Page();p.header(3,'購入部品の使い方と確認事項','購入一覧の全11品目を照合。原本のDOCXは変更せず、実装条件と未確認事項を追加した。')
bom=[
 ['U1','XIAO nRF52840','117341','1 / 1','BLE受信、制御、内蔵USB充電'],
 ['U2','Adafruit DRV2605L / ADA-2305','EEHD-54SJ','1 / 1','白いQTコネクター2個の版として扱う'],
 ['BT1','DTP502035(PHR) / 3.7V 300mAh','EEHD-5GHG','1 / 1','PH接続。極性、充電条件を確認'],
 ['SW1','TVDP01-060CR（赤）','108076','1 / 3','操作用1個、予備2個'],
 ['M1','LRA LD14-002','106838','1 / 1','基本回路に使用。駆動条件未確定'],
 ['M2','ERM 316040001','116777','0 / 1','交換評価用。LRAと同時使用しない'],
 ['J1','B2B-PH-K-S','112802','1 / 1','2.0mm。電線で引出し・個別絶縁・本体保持'],
 ['J2','WJEK254-2.54-02P-140-00A','114217','1 / 1','2.54mm端子台。最小構成では省略可能'],
 ['基板','AE-D-TH','111960','1 / 1','主基板。細長実装は7列部分の切出し案'],
 ['配線','AWG26・9色セット','118293','必要長 / 1組','被覆付き線で配線。裸スズメッキ線は必須でない'],
 ['ヘッダー','PH-1x40SG','100167','20本 / 40本','XIAO 13本、DRV 7本。脚長は仮合わせ'],
]
bx=[40,110,460,595,720,1155]
for j,h in enumerate(['符号','購入品・型番','販売コード','使用 / 購入','使い方']):
 p.rect(bx[j],120,bx[j+1]-bx[j],30,'#dfeaf1',BORDER,r=0);p.text(bx[j]+6,140,h,10)
for i,row in enumerate(bom):
 yy=150+i*29
 for j,t in enumerate(row):
  p.rect(bx[j],yy,bx[j+1]-bx[j],29,'#f6f9fb' if i%2==0 else '#ffffff',BORDER,r=0,lw=.5)
  p.text(bx[j]+6,yy+20,t,9.5)

p.rect(40,495,545,278,'#f3f7fa');p.text(55,520,'実装と動作の確認境界',14)
p.lines(55,548,[
 '主基板18×47mm、部品外形約19.05×50.15mmの細長案を継承。',
 'この外形に電線・絶縁・支持具・外付け部品は含めない。',
 'J1/J2・電池・ボタン・LRAはグリップ内へ別途保持する。',
 '追加消耗品：熱収縮チューブ、絶縁支持材、固定具。保有未確認。',
 '実物の部品版、ヘッダー脚長、収納高さ、ゴムとの干渉は未確認。',
 'ソフト検査：購入11品目、12配線、ネット分離、DRV端子、穴対応。',
 '未実施：EDA ERC、加工・組立、通電、電源余裕、温度、BLE。',
 '未実施：電池の充電、充電終止、LRA駆動・クランプ・校正。',
 '初回の充電確認はDRV/LRAを外し、XIAOと電池で行う。',
 '充電中は目を離さず、異常な発熱・膨らみ・異臭があれば中止。',
],10,GREY,21)
p.rect(610,495,545,278,'#f3f7fa');p.text(625,520,'参照資料',14)
refs=[
 ('購入原本','ハッカソン購入部品一覧2026-10-23.docx',None),
 ('XIAO端子・充電電流','https://wiki.seeedstudio.com/XIAO_BLE/','https://wiki.seeedstudio.com/XIAO_BLE/'),
 ('DRV端子・基板データ','https://github.com/adafruit/Adafruit-DRV2605-PCB','https://github.com/adafruit/Adafruit-DRV2605-PCB'),
 ('LRA端子図','https://akizukidenshi.com/goodsaffix/LD14-002.png','https://akizukidenshi.com/goodsaffix/LD14-002.png'),
 ('LiPoメーカー仕様書','千石電商掲載 DTP502035(PHR) / 2023-04-24 Ver 2.0','https://www.sengoku.co.jp/item/pdf/SPE-DTP502035%28PHR%29-3.7V-300mAh-en-2.0ver.pdf'),
 ('PH / AE-D-TH仕様','秋月電子 販売コード112802 / 111960','https://akizukidenshi.com/catalog/g/g112802/'),
]
yy=546
for label,detail,url in refs:
 p.text(625,yy,label,10);p.text(625,yy+15,detail,8.8,GREY);yy+=36
pages.append(p)

pdf=OUT/'白杖振動デバイス_購入部品対応回路図_2026-10-28.pdf'
c=canvas.Canvas(str(pdf),pagesize=(W,H));c.setTitle('白杖振動デバイス 購入部品対応回路図 Rev P1')
c.setAuthor('HeroesLeague prototype design')
for p in pages:renderPDF.draw(p.d,c,0,0);c.showPage()
c.save()
renderSVG.drawToFile(pages[0].d,str(OUT/'全体回路図_2026-10-28.svg'))
with (OUT/'配線一覧_端子台あり.csv').open('w',encoding='utf-8-sig',newline='') as f:
 wr=csv.writer(f);wr.writerow(['線番号','信号','色','接続元','穴・位置','接続先','穴・位置','注意']);wr.writerows(wires)
with (OUT/'購入部品対応.csv').open('w',encoding='utf-8-sig',newline='') as f:
 wr=csv.writer(f);wr.writerow(['符号','型番','販売コード','使用/購入','使い方']);wr.writerows(bom)
checks={
 'source_docx':str(SOURCE),'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
 'inventory_items_checked':len(inventory),'source_inventory_rows':inventory,'wires_with_terminal_block':12,'wires_without_terminal_block':10,
 'nets':nets,'assertions':{'purchased_models':True,'output_nets_separate_from_gnd':True,'driver_vin_is_3v3':True,'no_duplicate_net_node':True,'drv_pads_match_vendor_eagle':True,'layout_holes_match_prior_drawing':True},
 'connector_pin_number_and_left_right':'not assigned: identify by measured battery polarity',
 'nc':['U2.IN','U2.QT1','U2.QT2','M1.case5','M1.case6','M2.ERM','U1.VBUS header'],
 'layout_exceptions':['G1 and G17 unavailable','button GND uses XIAO top side','J1 2mm pitch does not fit AE-D-TH 2.54mm pitch'],
 'unverified':['physical board revision and assembly','header leg length and grip fit','power budget and temperature','charge current and termination','LRA voltage current clamp and calibration','BLE operation'],
 'eda_erc_performed':False,'physical_test_performed':False,
}
(OUT/'回路接続と照合記録.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2))
(OUT/'README.md').write_text('''# 購入部品対応回路図 Rev P1

購入一覧を読み直し、LRAを基本とした全体接続図を再出力した。原本のDOCXと過去のPDFは変更していない。

PDF 1ページ目は基板単位の回路図、2ページ目は12本の配線表とPH接続、3ページ目は購入11品目との対応・検証境界。

購入済みの振動子交換用端子台J2を基本図へ含めた。先の最小実装図からの差分は、W09/W10の行先を端子台へ変え、W11/W12でLRAへつなぐこと。端子台を省く場合は従来どおり10本となる。XIAO/DRVの主基板穴位置は維持した。

PHは2mmピッチの基板用ポストで、2.54mm基板へ無理に差し込まない。J1の+/-は実測で決める管理名であり、ピン番号や見た目の左右を確定していない。電池本体や付属線へのはんだづけ・切断は不要。PH本体は固定し、脚は個別に絶縁する。

ネット表とメーカーEagleの端子対応をスクリプトで照合した。EDA ERCや実機試験の代わりではない。通電、充電終止、電源余裕、LRA定格と駆動設定、収納・無線は未検証。

SVGは編集用、PNGは閲覧用。スクリプト再実行にはReportLab、pypdfではなく標準xml/zip/jsonと、日本語TTF、既存の配置JSON・公式Eagleデータが必要。スクリプト内の参照パスを参照。
''')
print(json.dumps({'pdf':str(pdf),'pages':len(pages),'purchase_items':len(inventory),'wires':len(wires),'checks':checks['assertions']},ensure_ascii=False))
