from pathlib import Path
src=Path('output/pdf/all-pin-wiring-caseB-2026-10-28/source/build_all_pins.py')
out=Path('output/pdf/j1-integrated-2026-10-28');(out/'source').mkdir(parents=True,exist_ok=True)
s=src.read_text()
s=s.replace('Rev F2 / ケースB確定','Rev J1 / 主基板一体化・ケースB')
s=s.replace("'J1-1：電池+','S1.B2'","'J1-1：電池+','S0.H1 新規穴 / 表の脚'")
s=s.replace("'J1-2：電池-','S1.C2'","'J1-2：電池-','S0.H2 新規穴 / 表の脚'")
s=s.replace('S0＝主基板 / S1＝J1用2.0mmピッチ小基板（追加）/ S2＝J2用2.54mmピッチ小基板（AE-D-TH残材の案）','S0＝AE-D-TH主基板。J1は裏面へ直接実装（新規穴H1/H2）。S1小基板を廃止。J2だけは従来のS2上。')
s=s.replace('J1はS1へ基板実装し、本体ごとグリップに固定する。J1の脚へ電線だけを付けて浮かせる旧案は本書では採用しない。','J1はS0裏面へ直接実装。2.0mm間隔の新規穴H1/H2を追加し、本体を樹脂の押さえで保持する。別基板S1は不要。')
s=s.replace('既存の細長い7列案を継承。J1とJ2はS0へ無理に詰め込まず、S1/S2上に固定しグリップ内で支持する。','7列の幅を維持してJ1を裏面中央へ置く。W01/W02をJ1の外側へ迂回。図の上下は両面ともUSB側が上。')
s=s.replace('XIAO BAT+ ← J1-1 / S1.B2：W07','XIAO BAT+ ← J1-1 / H1：W07')
s=s.replace('XIAO BAT- ← J1-2 / S1.C2：W08','XIAO BAT- ← J1-2 / H2：W08')
s=s.replace('S0.G1/G17は穴がなく無配線。','S0.G1/G17は穴がなく無配線。')
s=s.replace('この外形にS1/S2・電池・ボタン・振動子・電線・絶縁・支持具は含めない。全体のグリップ収納と高さは未確認。','J1本体も主基板の幅・長さ内へ収納。PH嵌合高さ8mmが裏へ追加される。電池・S2・電線・支持具と収納高さは別途確認。')
s=s.replace('J1を2mm小基板S1へ固定する方式が最新版。以前の「J1脚へ電線だけを付ける」図は本書で置き換える。','新規穴は非めっきでランド無し。穴へはんだを流しても固定できない。本体の機械保持が必須。旧S1の図は本書で置き換える。')
s=s.replace('1  ケースB：J1-1＝+、J1-2＝-。3頁の接続先を確認する。','1  裸基板でH1/H2を加工し、J1を裏面から仮合わせする（3頁）。')
s=s.replace('2  電池とUSBを外す。XIAO底面のBAT±を先に配線・絶縁する。','2  電池とUSBを外す。W07/W08をXIAO底面のBAT±へ先に接合する。')
s=s.replace('3  S0へヘッダー固定後、W01-W06を指定ピンへ接続する。','3  J1の脚へW07/W08を表面側で接合・絶縁。J1本体を保持する。')
s=s.replace('4  S1/S2の基板とコネクターを保持し、W07-W12を接続する。','4  XIAO/DRVを固定。W01/W02は新経路で配線。残りの線を接続する。')
s=s.replace('追加が必要：S1用2.0mmピッチ基板（例：秋月104022）、絶縁・固定材。','必要：0.8mm穴あけ工具・位置決め治具、絶縁材、J1本体の樹脂製押さえ。')
s=s.replace('S1/S2の外形・固定・グリップ収納は設計案。現物で仮合わせする。','S1追加基板は不要。S2・本体の固定・全高・収納は現物で仮合わせする。')
s=s.replace("'j1_pin1':'S1.B2','j1_pin2':'S1.C2'","'j1_pin1':'S0.H1 new drill','j1_pin2':'S0.H2 new drill'")
s=s.replace("'J1 soldered into additional 2mm-pitch S1, S1 secured mechanically; not floating on leads'","'J1 on S0 reverse, two new non-plated holes H1/H2; direct wire solder on front, mechanical body restraint required; no S1'")
s=s.replace("'S1/S2 fabrication and fit'","'S0 drilling, J1 mechanical restraint, S2 fabrication and fit'")
s=s.replace("'LRA専用_全ピン配線表と実装図_ケースB確定_2026-10-28.pdf'","'J1主基板一体型_実装配線図_ケースB_2026-10-28.pdf'")
s=s.replace("'電池PHコネクター_ピン番号と極性確認.svg'","'J1追加穴_加工詳細.svg'")
s=s.replace("'全配線一覧_ケースB確定.csv'","'全配線一覧_J1主基板一体型.csv'")
# Only emit the selected integrated schedule; old case names/coordinates are no longer useful outputs.
a=s.index('for name,case in {\'B\':cases[\'B\']}.items():');b=s.index('checks={',a)
s=s[:a]+s[b:]
s=s.replace("'pin1_is_not_intrinsically_plus_or_minus':True,'battery_cases':cases,","'pin1_is_not_intrinsically_plus_or_minus':True,'current_case_B':{'positive_pin':1,'negative_pin':2,'W07':['J1-1','S0.H1','U1.BAT+'],'W08':['J1-2','S0.H2','U1.BAT-']},")
s=s.replace("'both_battery_polarity_cases_covered':True,","'selected_case_B_preserved':True,")
# Geometry/routing updates are inserted before drawings are made.
key='pages=[]\n'
geometry='''# User choice B is preserved. Coordinate origin: S0 front, USB up, x right/y down in mm.
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
  p.text(x,y+17,('1 +' if name=='H1' else '2 -') if back else name,8,INK,'middle')
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
'''
s=s.replace(key,geometry,1)
# Replace previous S1 page entirely with direct-S0 fabrication detail.
a=s.index("p=Page();header(p,3,");b=s.index("p=Page();header(p,4,",a)
page3='''p=Page();header(p,3,'J1をS0裏面へ直付けする：追加穴H1/H2','H1/H2は既存のA-G・1-17とは別の新規穴。部品実装前の裸基板に加工し、J1を裏側から差し込む。')
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
 p.text(px,py-18,n+(' / 1+' if n=='H1' else ' / 2-'),10,INK,'middle')
p.line([(ox+8.11*k,oy+4.23*k+24),(ox+10.11*k,oy+4.23*k+24)],INK,1)
p.text(ox+9.11*k,oy+4.23*k+42,'2.00mm',10,INK,'middle')
p.lines(50,448,['H1/H2のy位置：8行目と9行目の中央。','D列から左右へ各1.00mm。既存のD8/D9等の穴は拡張しない。','φ0.8mmの非めっき穴。位置決め治具を使用し、2.00±0.05mmを目標。'],10.5,23)
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

'''
s=s[:a]+page3+s[b:]
s=s.replace("b=board(p,490,183,3.2,back=True,parts=False,wires=True)","b=board(p,490,183,3.2,back=True,parts=False,wires=True)\nonj1(p,f,False);onj1(p,b,True)")
s=s.replace("p.text(50,648,'金色の20箇所：ヘッダーの固定穴。色輪：電線の追加。',9)","p.text(50,625,'H1/H2：新規穴の脚へW07/W08を接合（表面側）。',9)\np.text(50,648,'金色20箇所：ヘッダー。H1/H2の位置は3頁。',9)")
s=s.replace("p.text(429,648,'W09/W10 → S2上のJ2-1/J2-2。BAT±はS0の穴ではない。',9)","p.text(429,625,'J1本体：裏面中央。配線は本体の外を通す。',9)\np.text(429,648,'W01はy27.4、W02はy29.0で横切る新経路。',9)")
s=s.replace("'G3 → A12：W01 / 3V3',","'G3 → A12：W01 / 3V3（新経路）',")
s=s.replace("'G2 → A13：W02 / GND',","'G2 → A13：W02 / GND（新経路）',")
# Replace final README with an unambiguous current description.
a=s.index("(OUT/'README.md').write_text(");b=s.index('print(json.dumps',a)
s=s[:a]+'''(OUT/'README.md').write_text("""# J1主基板一体型 Rev J1 / ケースB

J1を同じAE-D-TH切出しS0の裏面へ直付けする試作案。別基板S1を廃止。幅優先で従来のS0 18×47mm、部品の平面外形約19.05×50.15mmを維持する。J2用S2は基板外の従来構成。

新規穴：H1=(10.11,22.23)mm→J1-1/+、H2=(8.11,22.23)mm→J1-2/-。原点はS0表面の左上、USB上。穴径0.8mm、2mm間隔。裏面で左右反転する。既存の2.54mm穴へ直挿ししない。

ユーザー測定報告：赤J1-2/黒J1-1で-3.8V、ケースB。W07はJ1-1/H1→BAT+、W08はJ1-2/H2→BAT-。追加穴は非めっき。電線と端子を表面で直接接合・絶縁し、本体を樹脂製押さえとグリップ側ホルダーで保持する。機械保持は必須で、形状・強度は未検証。はんだだけで基板に固定できない。

W01/W02をJ1の裏面占有範囲から迂回。旧図の配線経路・S1の穴名は使わない。ピン接続は同じ。全12本の接続表CSVを同梱。

裏面PHの嵌合高さは基板面から8mm＋電線曲げ余裕。全高=表面実装高さ+S0厚1.6mm+裏面8mm+絶縁/固定/電線余裕。グリップ内径と収納は未確認。電池は基板外へ保持。

原寸テンプレートは100%印刷で50mm確認線と実物の既存穴を照合する。最適化は「同じAE-D-TH・幅長さ維持・J1固定」を優先した候補比較で、数学的な全組合せの最適解や実機適合を保証しない。実機穴あけ・組立・通電・EDA ERC・保持強度・収納は未検証。
""")
''' + s[b:]
# Geometry audit is part of the same reproducible deliverable.
s=s.replace("'wires':schedule,'factory_wires':factory", "'drill_geometry':checks_geo,'j1_body_mm':J1BOX,'j1_keepout_mm':J1KEEP,'rear_wire_routes':data['wires'][:2],'wires':schedule,'factory_wires':factory")
s=s.replace("'case B selected by user measurement report'","'case B, integrated into S0 reverse with H1/H2'")
# Append print-scale template (A4): exact millimetres, not the explanatory figure scale.
s+='''
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
 c.line(px,py,145,py)
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
'''
(out/'source/build_integrated.py').write_text(s)
print(out/'source/build_integrated.py')
