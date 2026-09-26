import XCTest
final class SmokeTests:XCTestCase {
 @MainActor func launchMap(maximumText:Bool=false,developer:Bool=false,networkID:String="kokura-ground-osm")->XCUIApplication {
  let app=XCUIApplication();app.launchArguments=["-tutorialComplete","YES","-selectedNetworkID",networkID,"--ui-testing","--reset-test-data"]
  if maximumText { app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"] }
  if developer { app.launchArguments += ["--developer-mode"] }
  app.launch();return app
 }
 @MainActor func testTobataDestinationAndRoutePreview() throws {
  let app=launchMap(developer:true,networkID:"tobata-ground-osm")
  XCTAssertTrue(app.buttons["九工大前駅付近・実験接続点を避難先にする"].waitForExistence(timeout:10))
  openDeveloper(app);let simulation=app.switches["toggleSimulation"];reach(simulation,app:app);turnOn(simulation)
  app.navigationBars.buttons.element(boundBy:0).tap();app.buttons["完了"].tap()
  app.buttons["戸畑キャンパス正門付近・実験接続点を避難先にする"].tap()
  XCTAssertTrue(app.staticTexts["戸畑キャンパス正門付近・実験接続点"].waitForExistence(timeout:5))
  let matched=app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","道路候補を照合")).firstMatch
  XCTAssertTrue(matched.waitForExistence(timeout:15),"戸畑の模擬位置を道路に照合できること")
  app.buttons["通行不可を避ける経路を確認"].tap()
  XCTAssertTrue(app.buttons["startMapNavigation"].waitForExistence(timeout:10))
 }
 @MainActor func testTobataRouteRecalculatesAfterClosureAndRemoval() throws {
  let app=launchMap(developer:true,networkID:"tobata-ground-osm")
  XCTAssertTrue(app.buttons["戸畑キャンパス正門付近・実験接続点を避難先にする"].waitForExistence(timeout:10))
  openDeveloper(app);let simulation=app.switches["toggleSimulation"];reach(simulation,app:app);turnOn(simulation)
  app.navigationBars.buttons.element(boundBy:0).tap();app.buttons["完了"].tap()
  app.buttons["戸畑キャンパス正門付近・実験接続点を避難先にする"].tap()
  XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","道路候補を照合")).firstMatch.waitForExistence(timeout:15))
  app.buttons["通行不可を避ける経路を確認"].tap()
  XCTAssertTrue(app.descendants(matching:.any).matching(NSPredicate(format:"label CONTAINS %@","通行不可登録0区間")).firstMatch.waitForExistence(timeout:10))

  // This stable OSM edge is on the fixture route and has a verified alternate path in CoreTests.
  let closedEdge="osm:166677852:11702112551:1781302900"
  app.buttons["通行不可を登録"].tap();app.buttons["roadListAlternative"].tap()
  let search=app.textFields["道路名・接続点・区間IDを検索"];reach(search,app:app,count:15);search.tap();search.typeText(closedEdge)
  let edge=app.buttons["edge."+closedEdge];XCTAssertTrue(edge.waitForExistence(timeout:5));edge.tap()
  let review=app.buttons["対象を確認して登録"];reach(review,app:app,count:12);review.tap();app.buttons["この範囲を登録"].tap()
  if app.alerts.firstMatch.waitForExistence(timeout:2) { app.alerts.buttons["閉じる"].tap() }
  XCTAssertTrue(app.descendants(matching:.any).matching(NSPredicate(format:"label CONTAINS %@","通行不可登録1区間")).firstMatch.waitForExistence(timeout:10),"登録後の迂回経路が最新の除外件数を保持すること")

  app.buttons["設定"].tap();let remove=app.buttons["removeReport."+closedEdge];reach(remove,app:app,count:20);XCTAssertTrue(remove.waitForExistence(timeout:5));remove.tap()
  let confirmations=app.buttons.matching(NSPredicate(format:"label == %@","この報告を解除"));confirmations.element(boundBy:max(0,confirmations.count-1)).tap();app.buttons["完了"].tap()
  XCTAssertTrue(app.descendants(matching:.any).matching(NSPredicate(format:"label CONTAINS %@","通行不可登録0区間")).firstMatch.waitForExistence(timeout:10),"解除後も経路が最新状態で再計算されること")
 }
 @MainActor func reach(_ button:XCUIElement,app:XCUIApplication,count:Int=10) {
  for _ in 0..<count where !button.isHittable { app.swipeUp() }
 }
 @MainActor func attach(_ app:XCUIApplication,_ name:String) { let image=XCTAttachment(screenshot:app.screenshot());image.name=name;image.lifetime = .keepAlways;add(image) }
 /// Tests run on isolated data (--ui-testing), so this only triggers if that data is from an older road version.
 @MainActor func resolveStorage(_ app:XCUIApplication) {
  let open=app.buttons["openStorageSettings"]
  guard open.waitForExistence(timeout:2) else { return }
  open.tap()
  let archive=app.buttons["旧報告を退避して新しい道路版で開始"]
  if archive.waitForExistence(timeout:5) { archive.tap();app.buttons["退避して開始"].firstMatch.tap() }
  if app.alerts.firstMatch.waitForExistence(timeout:3) { app.alerts.buttons["閉じる"].tap() }
  app.buttons["完了"].tap()
 }
 @MainActor func turnOn(_ toggle:XCUIElement) {
  // iOS 26 exposes the row and the inner control differently depending on the section; try both.
  for _ in 0..<3 where (toggle.value as? String) != "1" {
   let inner=toggle.switches.firstMatch
   if inner.exists { inner.tap() } else { toggle.coordinate(withNormalizedOffset:CGVector(dx:0.95,dy:0.5)).tap() }
   let app=XCUIApplication();if app.alerts.firstMatch.waitForExistence(timeout:2) { app.alerts.buttons["閉じる"].tap() }
   _=XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == '1'"),object:toggle)],timeout:3)
  }
  XCTAssertEqual(toggle.value as? String,"1",toggle.identifier)
 }
 @MainActor func openDeveloper(_ app:XCUIApplication) {
  let gear=app.buttons["設定"].firstMatch;XCTAssertTrue(gear.waitForExistence(timeout:10))
  for _ in 0..<3 where !app.navigationBars["設定"].exists { gear.tap();_=app.navigationBars["設定"].waitForExistence(timeout:3) }
  let link=app.buttons["DeveloperModeを開く"];reach(link,app:app,count:15);link.tap()
 }
 @MainActor func testTutorialPermissionsAndOptionalContinuation() throws {
  let app=XCUIApplication();app.launchArguments=["--reset-tutorial","--ui-testing","--reset-test-data"];app.launch()
  XCTAssertTrue(app.staticTexts["選んだ場所までの避難を支援"].waitForExistence(timeout:10))
  let next=app.buttons["tutorialNext"];reach(next,app:app);next.tap()
  XCTAssertTrue(app.staticTexts["通知の許可"].exists);XCTAssertTrue(app.buttons["通知の許可を確認"].exists)
  reach(next,app:app);next.tap()
  XCTAssertTrue(app.staticTexts["位置情報の許可"].exists);XCTAssertTrue(app.buttons["位置情報の許可を確認"].exists)
  reach(next,app:app);next.tap()
  XCTAssertTrue(app.staticTexts["カメラの許可"].exists)
  reach(next,app:app);next.tap();reach(next,app:app);next.tap()
  XCTAssertTrue(app.textFields["destinationQuery"].waitForExistence(timeout:10))
 }
 @MainActor func testHomeIsFullScreenMapWithFloatingSearch() throws {
  let app=launchMap()
  XCTAssertTrue(app.textFields["destinationQuery"].waitForExistence(timeout:10));XCTAssertFalse(app.tabBars.firstMatch.exists);XCTAssertFalse(app.navigationBars.firstMatch.exists)
  let map=app.otherElements["homeMap"];XCTAssertTrue(map.exists)
  XCTAssertEqual(map.frame.width,app.windows.firstMatch.frame.width,accuracy:1);XCTAssertGreaterThan(map.frame.height,app.windows.firstMatch.frame.height*0.95)
  XCTAssertLessThan(app.textFields["destinationQuery"].frame.minY,map.frame.midY,"search floats over the top of the map")
  for label in ["設定","現在位置を表示","通行不可を登録","全面カメラで案内","京町・実験接続点を避難先にする"] { XCTAssertTrue(app.buttons[label].exists,label) }
  app.buttons["京町・実験接続点を避難先にする"].tap()
  XCTAssertTrue(app.staticTexts["京町・実験接続点"].waitForExistence(timeout:5))
  attach(app,"Home-full-screen-map")
 }
 @MainActor func testReportSelectionConfirmationAndRestartPersistence() throws {
  let app=launchMap();resolveStorage(app);let register=app.buttons["通行不可を登録"];register.tap()
  app.buttons["roadListAlternative"].tap()
  let first=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","edge.")).firstMatch
  XCTAssertTrue(first.waitForExistence(timeout:5));let identifier=first.identifier;first.tap()
  let review=app.buttons["対象を確認して登録"];reach(review,app:app,count:18);review.tap()
  XCTAssertTrue(app.staticTexts["区間全体を通行不可にします"].waitForExistence(timeout:5));app.buttons["この範囲を登録"].tap()
  if app.alerts.firstMatch.waitForExistence(timeout:3) { app.alerts.buttons["閉じる"].tap() }
  app.terminate();app.launchArguments.removeAll { $0 == "--reset-test-data" };app.launch();register.tap()
  app.buttons["roadListAlternative"].tap()
  let saved=app.buttons[identifier];XCTAssertTrue(saved.waitForExistence(timeout:5));XCTAssertTrue(saved.label.contains("通行不可登録あり"));app.buttons["取消"].tap()
  attach(app,"Report-persisted-after-restart")
 }
 @MainActor func testMaximumTextCameraControlsRemainReachable() throws {
  let app=launchMap(maximumText:true);let camera=app.buttons["全面カメラで案内"];camera.tap()
  let map=app.buttons["cameraBack"];XCTAssertTrue(map.waitForExistence(timeout:5));XCTAssertFalse(app.buttons["カメラと通知を開始"].exists)
  for _ in 0..<8 where !map.isHittable { app.scrollViews["cameraControls"].swipeUp() }
  XCTAssertTrue(map.isHittable)
  attach(app,"Maximum-text-full-camera-controls");map.tap()
  XCTAssertTrue(app.buttons["設定"].waitForExistence(timeout:5))
 }
 @MainActor func testDestinationSelectionAndFullCameraWithoutHomeTab() throws {
  let app=launchMap();XCTAssertTrue(app.textFields["destinationQuery"].waitForExistence(timeout:15));XCTAssertFalse(app.tabBars.firstMatch.exists)
  app.textFields["destinationQuery"].tap()
  app.buttons["小倉駅南側・実験接続点"].tap()
  XCTAssertTrue(app.staticTexts["小倉駅南側・実験接続点"].waitForExistence(timeout:5))
  attach(app,"Evacuation-destination-map")
  app.buttons["全面カメラで案内"].tap()
  XCTAssertTrue(app.buttons["cameraBack"].waitForExistence(timeout:5))
  XCTAssertFalse(app.buttons["カメラと通知を開始"].exists);XCTAssertFalse(app.buttons["案内を再読み上げ"].exists)
 }
 @MainActor func testSimulatedMapAndCameraNavigationWithBoxes() throws {
  let app=launchMap(developer:true)
  XCTAssertTrue(app.textFields["destinationQuery"].waitForExistence(timeout:10))
  openDeveloper(app)
  let boxes=app.switches["toggleBoxes"];reach(boxes,app:app);XCTAssertTrue(boxes.exists);turnOn(boxes)
  let simulation=app.switches["toggleSimulation"];reach(simulation,app:app);XCTAssertTrue(simulation.exists);turnOn(simulation)
  let pole=app.buttons["ポールの模擬継続検出（BBOXにも表示）"];reach(pole,app:app,count:15);pole.tap()
  app.navigationBars.buttons.element(boundBy:0).tap();app.buttons["完了"].tap()
  resolveStorage(app)
  app.buttons["京町・実験接続点を避難先にする"].tap()
  let matched=app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","道路候補を照合")).firstMatch
  XCTAssertTrue(matched.waitForExistence(timeout:15),"simulated position must match a road")
  app.buttons["通行不可を避ける経路を確認"].tap()
  let startMap=app.buttons["startMapNavigation"];XCTAssertTrue(startMap.waitForExistence(timeout:10))
  attach(app,"Route-preview-with-two-guidance-modes")
  startMap.tap();app.buttons["確認してナビを開始"].tap()
  XCTAssertTrue(app.otherElements["instructionBanner"].waitForExistence(timeout:10));XCTAssertTrue(app.otherElements["navigationMap"].exists)
  XCTAssertTrue(app.descendants(matching:.any).matching(NSPredicate(format:"label CONTAINS %@","徒歩目安")).firstMatch.waitForExistence(timeout:10))
  attach(app,"Map-navigation")
  app.buttons["navSwitchCamera"].tap()
  XCTAssertTrue(app.otherElements["arDirection"].waitForExistence(timeout:10))
  XCTAssertTrue(app.buttons["switchToMapNavigation"].exists)
  attach(app,"Camera-navigation-AR-arrow")
  app.buttons["switchToMapNavigation"].tap()
  XCTAssertTrue(app.otherElements["navigationMap"].waitForExistence(timeout:5))
  app.buttons["endNavigation"].tap();app.buttons["案内を終了"].tap()
  XCTAssertTrue(app.textFields["destinationQuery"].waitForExistence(timeout:5))
 }
 @MainActor func testDeveloperDebugLogScreen() throws {
  let app=launchMap(developer:true);XCTAssertTrue(app.textFields["destinationQuery"].waitForExistence(timeout:10))
  openDeveloper(app);app.buttons["openDebugLog"].tap()
  XCTAssertTrue(app.staticTexts["debugLogCount"].waitForExistence(timeout:5))
  let search=app.textFields["debugLogSearch"];search.tap();search.typeText("Road network")
  let entry=app.buttons.containing(NSPredicate(format:"label CONTAINS %@","Road network loaded")).firstMatch
  XCTAssertTrue(entry.waitForExistence(timeout:5));entry.tap()
  XCTAssertTrue(app.staticTexts["発生元"].waitForExistence(timeout:5));XCTAssertTrue(app.staticTexts["詳細"].exists)
  attach(app,"Debug-log-expanded")
 }
 @MainActor func testRealCameraModelInferenceAndDeveloperMode() throws {
  if ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil { throw XCTSkip("Camera requires physical iPhone") }
  let app=launchMap();app.buttons["全面カメラで案内"].tap()
  let springboard=XCUIApplication(bundleIdentifier:"com.apple.springboard")
  let allow=springboard.buttons.matching(NSPredicate(format:"label IN %@",["許可","OK","Allow"])).firstMatch
  if allow.waitForExistence(timeout:3) { allow.tap() }
  XCTAssertTrue(app.staticTexts["端末内で認識中"].waitForExistence(timeout:15))
  app.buttons["cameraBack"].tap();app.buttons["設定"].tap();let version=app.buttons["versionInfo"];reach(version,app:app)
  for _ in 0..<7 { version.tap() }
  if app.alerts.firstMatch.waitForExistence(timeout:3) { app.alerts.buttons["閉じる"].tap() }
  app.buttons["DeveloperModeを開く"].tap();let metrics=app.staticTexts["metricInference"];reach(metrics,app:app,count:20)
  XCTAssertTrue(metrics.waitForExistence(timeout:10));expectation(for:NSPredicate(format:"label MATCHES %@","推論 [1-9][0-9]*・通知 [0-9]+・抑制 [0-9]+"),evaluatedWith:metrics);waitForExpectations(timeout:20);add(XCTAttachment(string:metrics.label))
 }
 @MainActor func testNetworkSearchAndUnsupportedDestination() throws {
  let app=launchMap()
  let query=app.textFields["destinationQuery"];XCTAssertTrue(query.waitForExistence(timeout:5));query.tap();query.typeText("Mojiko Station");app.buttons["destinationSearchButton"].tap()
  let result=app.buttons["destinationResult.0"]
  XCTAssertTrue(result.waitForExistence(timeout:30),"Internet search must return a result in this integration run")
  attach(app,"Live-destination-search")
  result.tap()
  XCTAssertTrue(app.otherElements["placeCard"].waitForExistence(timeout:5),"search result opens the place card like Google Maps")
  XCTAssertFalse(app.buttons["placeRoute"].isEnabled,"outside the stored network the route button is disabled")
  attach(app,"Place-card-search-result")
  app.buttons["placeSetDestination"].tap()
  XCTAssertTrue(app.staticTexts["選択した避難先は経路案内の対応範囲外です"].waitForExistence(timeout:5))
  XCTAssertFalse(app.buttons["通行不可を避ける経路を確認"].isEnabled)
 }
 @MainActor func testMapTapRoadSelectionIsDefault() throws {
  let app=launchMap();app.buttons["通行不可を登録"].tap()
  XCTAssertTrue(app.staticTexts["地図の道路をタップして選択"].waitForExistence(timeout:5))
  XCTAssertFalse(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","edge.")).firstMatch.exists)
  let map=app.otherElements["reportRoadMap"]
  XCTAssertTrue(map.waitForExistence(timeout:5))
  let selected=app.staticTexts["選択 1区間"],candidate=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","roadCandidate.")).firstMatch
  // The dense network makes most taps land on a road; try a few points in case one falls inside a block.
  for (dx,dy) in [(0.5,0.5),(0.45,0.55),(0.55,0.45),(0.4,0.6),(0.6,0.4),(0.5,0.65)] where !selected.exists {
   map.coordinate(withNormalizedOffset:CGVector(dx:dx,dy:dy)).tap()
   if candidate.waitForExistence(timeout:2) { reach(candidate,app:app);candidate.tap() }
  }
  XCTAssertTrue(selected.waitForExistence(timeout:5))
  attach(app,"Report-map-selectable-roads")
 }
 @MainActor func testDirectInputCompletionAndClear() throws {
  let app=launchMap();let query=app.textFields["destinationQuery"];XCTAssertTrue(query.waitForExistence(timeout:5))
  query.tap();query.typeText("Kokura Castle")
  let suggestion=app.buttons["destinationSuggestion.0"]
  XCTAssertTrue(suggestion.waitForExistence(timeout:25))
  attach(app,"Direct-input-search-suggestions")
  let searchAction=app.buttons["searchAction"]
  XCTAssertEqual(searchAction.label,"入力を消去")
  XCTAssertGreaterThanOrEqual(searchAction.frame.width,44)
  XCTAssertGreaterThanOrEqual(searchAction.frame.height,44)
  XCTAssertFalse(app.buttons["取消"].exists)
  searchAction.tap()
  XCTAssertFalse((query.value as? String ?? "").contains("Kokura"))
  XCTAssertFalse(app.buttons["destinationSuggestion.0"].exists)
  XCTAssertEqual(searchAction.label,"検索を閉じる")
  attach(app,"Direct-input-search-empty")
  searchAction.tap()
  XCTAssertFalse(searchAction.exists)
  XCTAssertTrue(app.buttons["設定"].exists)
  query.tap()
  query.typeText("33.8845, 130.880\n")
  XCTAssertTrue(app.staticTexts["指定した座標"].waitForExistence(timeout:5))
 }
 @MainActor func testLongPressDropsPinWithPlaceCard() throws {
  let app=launchMap();let map=app.otherElements["homeMap"];XCTAssertTrue(map.waitForExistence(timeout:10))
  // Above the bottom panel, below the chips. A POI under the finger would open its own card instead.
  map.coordinate(withNormalizedOffset:CGVector(dx:0.25,dy:0.38)).press(forDuration:1.0)
  XCTAssertTrue(app.otherElements["placeCard"].waitForExistence(timeout:5))
  add(XCTAttachment(string:app.staticTexts["placeName"].label))
  for id in ["placeRoute","placeSetDestination","closePlace"] { XCTAssertTrue(app.buttons[id].exists,id) }
  attach(app,"Place-card-dropped-pin")
  app.buttons["placeSetDestination"].tap()
  XCTAssertFalse(app.otherElements["placeCard"].exists);XCTAssertTrue(app.buttons["通行不可を避ける経路を確認"].waitForExistence(timeout:5))
 }
}
