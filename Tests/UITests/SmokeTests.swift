import XCTest
final class SmokeTests:XCTestCase {
 override func setUp() {
  super.setUp()
  addUIInterruptionMonitor(withDescription:"位置情報・カメラ・通知の許可") { alert in
   for label in ["Appの使用中は許可","アプリの使用中は許可","Allow While Using App","許可","Allow","OK"] {
    let button=alert.buttons[label]
    if button.exists { button.tap();return true }
   }
   return false
  }
 }
 @MainActor func answerPermissionAlert(_ app:XCUIApplication,allow:Bool=true) {
  let systemAlert=XCUIApplication(bundleIdentifier:"com.apple.springboard").alerts.firstMatch
  let appAlert=app.alerts.firstMatch
  let alert:XCUIElement?
  if systemAlert.waitForExistence(timeout:2) { alert=systemAlert }
  else if appAlert.exists { alert=appAlert }
  else { alert=nil }
  guard let alert else { return }
  let labels=allow ? ["Appの使用中は許可","アプリの使用中は許可","Allow While Using App","許可","Allow","OK"]:["許可しない","Don't Allow","Don’t Allow"]
  for label in labels {
   let button=alert.buttons[label].firstMatch
   if button.exists { button.tap();return }
  }
  XCTFail("許可ダイアログの選択肢を見つけられません: \(alert.buttons.allElementsBoundByIndex.map { $0.label })")
 }
 @MainActor func completeRequiredPermissions(_ app:XCUIApplication) {
  for label in ["位置情報の許可を確認","カメラの許可を確認"] {
   let button=app.buttons[label]
   if button.waitForExistence(timeout:5) {
    XCTAssertFalse(app.buttons["tutorialNext"].exists)
    button.tap();answerPermissionAlert(app)
   }
  }
  XCTAssertTrue(app.textFields["destinationQuery"].waitForExistence(timeout:10))
 }
 @MainActor func launchMap(maximumText:Bool=false,developer:Bool=false,simulated:Bool=false,networkID:String="kokura-ground-osm")->XCUIApplication {
  let app=XCUIApplication();app.launchArguments=["-AppleLanguages","(ja)","-AppleLocale","ja_JP","-tutorialComplete","YES","-selectedNetworkID",networkID,"--ui-testing","--reset-test-data"]
  if maximumText { app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"] }
  if developer { app.launchArguments += ["--developer-mode"] }
  if simulated { app.launchArguments += ["--simulate-position"] }
  app.resetAuthorizationStatus(for:.location);app.resetAuthorizationStatus(for:.camera)
  app.launch();completeRequiredPermissions(app);return app
 }
 @MainActor func tapSavedDestination(_ label:String,app:XCUIApplication) {
  let button=app.buttons[label],chips=app.scrollViews["savedChipsScroll"]
  chips.swipeLeft()
  XCTAssertTrue(button.waitForExistence(timeout:5),label);button.tap()
 }
 @MainActor func testCaneStatusStaysInSettingsWithoutPersistentMapBadge() throws {
  let app=launchMap()
  XCTAssertFalse(app.buttons["caneConnectionBadge"].exists)
  XCTAssertFalse(app.otherElements["caneConnectionNotice"].exists)
  app.buttons["設定"].firstMatch.tap()
  let status=app.staticTexts["caneConnectionStatus"]
  XCTAssertTrue(status.waitForExistence(timeout:5))
  XCTAssertEqual(status.label,"未接続")
  let scan=app.buttons["scanCane"];reach(scan,app:app)
  XCTAssertTrue(scan.isHittable)
  XCTAssertFalse(app.buttons["disconnectCane"].exists)
  attach(app,"Cane-connection-settings-disconnected")
  app.buttons["完了"].tap()
  XCTAssertTrue(app.textFields["destinationQuery"].waitForExistence(timeout:5))
  XCTAssertFalse(app.buttons["caneConnectionBadge"].exists)
  app.buttons["全面カメラで案内"].tap()
  XCTAssertTrue(app.buttons["cameraBack"].waitForExistence(timeout:5))
  XCTAssertFalse(app.buttons["caneConnectionBadge"].exists)
 }
 @MainActor func testTobataDestinationAndRoutePreview() throws {
  let app=launchMap(developer:true,simulated:true,networkID:"tobata-ground-osm")
  XCTAssertTrue(app.buttons["九工大前駅付近・実験接続点を目的地にする"].waitForExistence(timeout:10))
  tapSavedDestination("戸畑キャンパス正門付近・実験接続点を目的地にする",app:app)
  XCTAssertTrue(app.staticTexts["戸畑キャンパス正門付近・実験接続点"].waitForExistence(timeout:5))
  let matched=app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","道路候補を照合")).firstMatch
  XCTAssertTrue(matched.waitForExistence(timeout:15),"戸畑の模擬位置を道路に照合できること")
  XCTAssertTrue(app.buttons["startMapNavigation"].waitForExistence(timeout:10),"目的地設定後に自動で経路確認へ進むこと")
 }
 @MainActor func testShinzutsumiParkCoordinateReachesRoutePreview() throws {
  let app=launchMap(developer:true,simulated:true,networkID:"tobata-ground-osm")

  let query=app.textFields["destinationQuery"];XCTAssertTrue(query.waitForExistence(timeout:10));query.tap();query.typeText("33.89800372649751,130.84239911645375")
  let coordinateSearch=app.buttons["destinationSearchButton"];XCTAssertTrue(coordinateSearch.waitForExistence(timeout:5));coordinateSearch.tap()
  XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","選択地点までは約")).firstMatch.waitForExistence(timeout:5),"選択地点と自動選択した案内終点の差が表示されること")
  XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","入口・通路は未確認")).firstMatch.exists)
  XCTAssertFalse(app.staticTexts["案内の終点を確認"].exists)
  XCTAssertFalse(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","destinationConnection.")).firstMatch.exists)
  XCTAssertTrue(app.buttons["startMapNavigation"].waitForExistence(timeout:15),"新堤公園を目的地としてルート案内開始まで進めること")
 }
 @MainActor func testTobataRouteRecalculatesAfterClosureAndRemoval() throws {
  let app=launchMap(developer:true,simulated:true,networkID:"tobata-ground-osm")
  XCTAssertTrue(app.buttons["戸畑キャンパス正門付近・実験接続点を目的地にする"].waitForExistence(timeout:10))
  tapSavedDestination("戸畑キャンパス正門付近・実験接続点を目的地にする",app:app)
  XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","道路候補を照合")).firstMatch.waitForExistence(timeout:15))
  XCTAssertTrue(app.buttons["startMapNavigation"].waitForExistence(timeout:10))

  app.buttons["通行不可を登録"].tap();selectRoadOnReportMap(app)
  let review=app.buttons["対象を確認して登録"];XCTAssertTrue(review.isEnabled);review.tap();app.buttons["この範囲を登録"].tap()
  if app.alerts.firstMatch.waitForExistence(timeout:2) { app.alerts.buttons["閉じる"].tap() }
  XCTAssertTrue(app.buttons["startMapNavigation"].waitForExistence(timeout:10),"通行不可登録後も迂回経路を再計算できること")

  app.buttons["設定"].tap();let remove=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","removeReport.")).firstMatch;reach(remove,app:app,count:20);XCTAssertTrue(remove.waitForExistence(timeout:5));remove.tap()
  let confirmations=app.buttons.matching(NSPredicate(format:"label == %@","この報告を解除"));confirmations.element(boundBy:max(0,confirmations.count-1)).tap();app.buttons["完了"].tap()
  XCTAssertTrue(app.buttons["startMapNavigation"].waitForExistence(timeout:10),"通行不可解除後も経路が最新状態で再計算されること")
 }
 @MainActor func reach(_ button:XCUIElement,app:XCUIApplication,count:Int=10) {
  for _ in 0..<count where !button.isHittable { app.swipeUp() }
 }
 @MainActor func selectRoadOnReportMap(_ app:XCUIApplication) {
  let map=app.otherElements["reportRoadMap"]
  XCTAssertTrue(map.waitForExistence(timeout:5))
  let selected=app.staticTexts["選択 1区間"]
  let candidate=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","roadCandidate.")).firstMatch
  for (dx,dy) in [(0.5,0.5),(0.45,0.55),(0.55,0.45),(0.4,0.6),(0.6,0.4),(0.5,0.65)] where !selected.exists {
   map.coordinate(withNormalizedOffset:CGVector(dx:dx,dy:dy)).tap()
   if candidate.waitForExistence(timeout:1) { candidate.tap() }
  }
  XCTAssertTrue(selected.waitForExistence(timeout:5))
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
 @MainActor func testTutorialPermissionsAndRequiredAccess() throws {
  let app=XCUIApplication();app.launchArguments=["--reset-tutorial","--ui-testing","--reset-test-data"]
  app.resetAuthorizationStatus(for:.location);app.resetAuthorizationStatus(for:.camera);app.launch()
  XCTAssertTrue(app.staticTexts["選んだ場所までの避難を支援"].waitForExistence(timeout:10))
  let next=app.buttons["tutorialNext"];reach(next,app:app);next.tap()
  XCTAssertTrue(app.staticTexts["通知の許可"].exists);XCTAssertTrue(app.buttons["通知の許可を確認"].exists)
  app.buttons["通知の許可を確認"].tap();answerPermissionAlert(app)
  XCTAssertTrue(app.buttons["位置情報の許可を確認"].waitForExistence(timeout:10))
  XCTAssertFalse(next.exists)
  app.buttons["位置情報の許可を確認"].tap();answerPermissionAlert(app)
  XCTAssertTrue(app.buttons["カメラの許可を確認"].waitForExistence(timeout:10))
  XCTAssertFalse(next.exists)
  app.buttons["カメラの許可を確認"].tap();answerPermissionAlert(app)
  XCTAssertTrue(app.staticTexts["地図とカメラで案内"].waitForExistence(timeout:10))
  reach(next,app:app);next.tap()
  XCTAssertTrue(app.textFields["destinationQuery"].waitForExistence(timeout:10))
 }
 @MainActor func testEnglishAppLanguage() throws {
  let app=XCUIApplication()
  app.launchArguments=["-AppleLanguages","(en)","-AppleLocale","en_US","-tutorialComplete","YES","--ui-testing","--reset-test-data"]
  app.resetAuthorizationStatus(for:.location);app.resetAuthorizationStatus(for:.camera)
  app.launch()
  for label in ["Check location permission","Check camera permission"] {
   let button=app.buttons[label]
   XCTAssertTrue(button.waitForExistence(timeout:10),label)
   button.tap();answerPermissionAlert(app)
  }
  XCTAssertTrue(app.textFields["destinationQuery"].waitForExistence(timeout:10))
  XCTAssertTrue(app.buttons["Report a blocked road"].exists)
  app.buttons["Settings"].tap()
  XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout:5))
  XCTAssertTrue(app.staticTexts["Location and camera access are required to use this app. Notifications are optional; in-app audio still works without them."].exists)
  app.buttons["Done"].tap()
  app.buttons["Report a blocked road"].tap()
  XCTAssertTrue(app.navigationBars["Blocked road report"].waitForExistence(timeout:5))
  XCTAssertTrue(app.buttons["Back"].exists)
 }
 @MainActor func testCameraPermissionRevocationBlocksHome() throws {
  let app=launchMap()
  app.terminate();app.resetAuthorizationStatus(for:.camera);app.launch()
  XCTAssertTrue(app.buttons["カメラの許可を確認"].waitForExistence(timeout:10))
  XCTAssertFalse(app.otherElements["homeMap"].exists)
  XCTAssertFalse(app.buttons["tutorialNext"].exists)
 }
 @MainActor func testDeniedCameraPermissionStaysOnRequiredPage() throws {
  let app=XCUIApplication();app.launchArguments=["-tutorialComplete","YES","--ui-testing","--reset-test-data"]
  app.resetAuthorizationStatus(for:.location);app.resetAuthorizationStatus(for:.camera);app.launch()
  let location=app.buttons["位置情報の許可を確認"]
  if location.waitForExistence(timeout:5) { location.tap();answerPermissionAlert(app) }
  let camera=app.buttons["カメラの許可を確認"];XCTAssertTrue(camera.waitForExistence(timeout:10))
  addUIInterruptionMonitor(withDescription:"カメラを拒否") { alert in
   for label in ["許可しない","Don't Allow","Don’t Allow"] {
    let button=alert.buttons[label]
    if button.exists { button.tap();return true }
   }
   return false
  }
  camera.tap();answerPermissionAlert(app,allow:false)
  XCTAssertTrue(app.staticTexts["カメラ：許可なし"].waitForExistence(timeout:10))
  XCTAssertTrue(app.buttons["iOS設定を開く"].exists)
  XCTAssertFalse(app.buttons["tutorialNext"].exists)
  XCTAssertFalse(app.otherElements["homeMap"].exists)
 }
 @MainActor func testHomeIsFullScreenMapWithFloatingSearch() throws {
  let app=launchMap()
  XCTAssertTrue(app.textFields["destinationQuery"].waitForExistence(timeout:10));XCTAssertFalse(app.tabBars.firstMatch.exists);XCTAssertFalse(app.navigationBars.firstMatch.exists)
  let map=app.otherElements["homeMap"];XCTAssertTrue(map.exists)
  XCTAssertEqual(map.frame.width,app.windows.firstMatch.frame.width,accuracy:1);XCTAssertGreaterThan(map.frame.height,app.windows.firstMatch.frame.height*0.95)
  XCTAssertLessThan(app.textFields["destinationQuery"].frame.minY,map.frame.midY,"search floats over the top of the map")
  let chips=app.scrollViews["savedChipsScroll"];XCTAssertTrue(chips.exists)
  XCTAssertEqual(chips.frame.minX,app.windows.firstMatch.frame.minX,accuracy:1)
  XCTAssertEqual(chips.frame.maxX,app.windows.firstMatch.frame.maxX,accuracy:1)
  XCTAssertGreaterThanOrEqual(chips.buttons.firstMatch.frame.minX-chips.frame.minX,12)
  for label in ["設定","現在位置を表示","通行不可を登録","全面カメラで案内","京町・実験接続点を目的地にする"] { XCTAssertTrue(app.buttons[label].exists,label) }
  app.buttons["京町・実験接続点を目的地にする"].tap()
  XCTAssertTrue(app.staticTexts["京町・実験接続点"].waitForExistence(timeout:5))
  attach(app,"Home-full-screen-map")
 }
 @MainActor func testDestinationPanelDragsDownAndBackUp() throws {
  let app=launchMap()
  app.buttons["京町・実験接続点を目的地にする"].tap()
  let panel=app.otherElements["destinationPanel"]
  let handle=app.buttons["destinationPanelHandle"]
  XCTAssertTrue(panel.waitForExistence(timeout:5))
  XCTAssertTrue(handle.exists)
  let expandedHeight=panel.frame.height
  let start=app.staticTexts["京町・実験接続点"].coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
  start.press(forDuration:0.1,thenDragTo:start.withOffset(CGVector(dx:0,dy:230)))
  XCTAssertLessThan(panel.frame.height,expandedHeight-80)
  XCTAssertEqual(handle.label,"目的地パネルを展開")
  let compactStart=handle.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
  compactStart.press(forDuration:0.1,thenDragTo:compactStart.withOffset(CGVector(dx:0,dy:-230)))
  XCTAssertGreaterThan(panel.frame.height,expandedHeight-30)
  XCTAssertEqual(handle.label,"目的地パネルを縮小")
  XCTAssertTrue(app.buttons["通行不可を避ける経路を確認"].exists)
 }
 @MainActor func testSeparatedRoadsCanBeSelectedDeselectedAndSavedTogether() throws {
  let app=launchMap();app.buttons["通行不可を登録"].tap()
  selectRoadOnReportMap(app)
  let map=app.otherElements["reportRoadMap"]
  let candidate=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","roadCandidate.")).firstMatch
  var second:CGVector?
  for point in [CGVector(dx:0.2,dy:0.8),CGVector(dx:0.8,dy:0.8),CGVector(dx:0.8,dy:0.2)] {
   map.coordinate(withNormalizedOffset:point).tap()
   if candidate.waitForExistence(timeout:1) { candidate.tap() }
   if app.staticTexts["選択 2区間"].waitForExistence(timeout:1) { second=point;break }
  }
  let point=try XCTUnwrap(second,"離れた2つ目の道路も選択できること")
  map.coordinate(withNormalizedOffset:point).tap()
  if candidate.waitForExistence(timeout:1) { candidate.tap() }
  XCTAssertTrue(app.staticTexts["選択 1区間"].waitForExistence(timeout:5))
  map.coordinate(withNormalizedOffset:point).tap()
  if candidate.waitForExistence(timeout:1) { candidate.tap() }
  XCTAssertTrue(app.staticTexts["選択 2区間"].waitForExistence(timeout:5))
  app.buttons["対象を確認して登録"].tap();app.buttons["この範囲を登録"].tap()
  if app.alerts.firstMatch.waitForExistence(timeout:2) { app.alerts.buttons["閉じる"].tap() }
  app.terminate();app.launchArguments.removeAll { $0 == "--reset-test-data" };app.launch()
  app.buttons["設定"].tap()
  let reports=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","removeReport."))
  reach(reports.firstMatch,app:app,count:20)
  XCTAssertTrue(reports.firstMatch.waitForExistence(timeout:5))
  XCTAssertEqual(reports.count,2,"選択した全区間が再起動後も保存されること")
 }
 @MainActor func testReportSelectionConfirmationAndRestartPersistence() throws {
  let app=launchMap();resolveStorage(app);let register=app.buttons["通行不可を登録"];register.tap()
  XCTAssertTrue(app.staticTexts["道路が選択されていません"].waitForExistence(timeout:5))
  XCTAssertFalse(app.buttons["対象を確認して登録"].isEnabled)
  selectRoadOnReportMap(app)
  let review=app.buttons["対象を確認して登録"];XCTAssertTrue(review.isEnabled);review.tap()
  XCTAssertTrue(app.staticTexts["区間全体を通行不可にします"].waitForExistence(timeout:5))
  let count=app.staticTexts["reportReviewSegmentCount"]
  XCTAssertEqual(count.label,"通行不可にする道路：1区間")
  XCTAssertFalse(app.staticTexts["名称未登録の道路"].exists)
  app.buttons["戻って修正"].tap()
  XCTAssertTrue(review.waitForExistence(timeout:5));review.tap()
  XCTAssertEqual(app.staticTexts["reportReviewSegmentCount"].label,"通行不可にする道路：1区間")
  app.buttons["この範囲を登録"].tap()
  if app.alerts.firstMatch.waitForExistence(timeout:3) { app.alerts.buttons["閉じる"].tap() }
  app.terminate();app.launchArguments.removeAll { $0 == "--reset-test-data" };app.launch()
  app.buttons["設定"].tap();let saved=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","removeReport.")).firstMatch
  reach(saved,app:app,count:20);XCTAssertTrue(saved.waitForExistence(timeout:5));app.buttons["完了"].tap()
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
 @MainActor func testCameraDoesNotRecognizeWithoutDestinationAtLaunchOrAfterClearing() throws {
  let app=launchMap()
  let camera=app.buttons["全面カメラで案内"]
  let recognitionDisabled=app.descendants(matching:.any)["cameraRecognitionDisabled"]
  XCTAssertTrue(camera.waitForExistence(timeout:10));camera.tap()
  XCTAssertTrue(recognitionDisabled.waitForExistence(timeout:5),"起動直後の目的地未設定状態では画像認識を開始しないこと")
  app.buttons["cameraBack"].tap()

  app.buttons["京町・実験接続点を目的地にする"].tap()
  let clear=app.buttons["目的地の選択を解除"]
  reach(clear,app:app);XCTAssertTrue(clear.isHittable);clear.tap()
  camera.tap()
  XCTAssertTrue(recognitionDisabled.waitForExistence(timeout:5),"目的地を解除した後も画像認識を開始しないこと")
 }
 @MainActor func testCameraRecognitionRemainsEnabledWithDestination() throws {
  let app=launchMap()
  app.buttons["京町・実験接続点を目的地にする"].tap()
  app.buttons["全面カメラで案内"].tap()
  XCTAssertTrue(app.descendants(matching:.any)["sceneBar"].waitForExistence(timeout:5),"目的地設定済みでは従来どおり画像認識を有効にすること")
  XCTAssertFalse(app.descendants(matching:.any)["cameraRecognitionDisabled"].exists)
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
  let app=launchMap(developer:true,simulated:true)
  XCTAssertTrue(app.textFields["destinationQuery"].waitForExistence(timeout:10))
  openDeveloper(app)
  let boxes=app.switches["toggleBoxes"];reach(boxes,app:app);XCTAssertTrue(boxes.exists);turnOn(boxes)
  let pole=app.buttons["ポールの模擬継続検出（BBOXにも表示）"];reach(pole,app:app,count:15);pole.tap()
  app.navigationBars.buttons.element(boundBy:0).tap();app.buttons["完了"].tap()
  resolveStorage(app)
  app.buttons["京町・実験接続点を目的地にする"].tap()
  let matched=app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","道路候補を照合")).firstMatch
  XCTAssertTrue(matched.waitForExistence(timeout:15),"simulated position must match a road")
  let startMap=app.buttons["startMapNavigation"];XCTAssertTrue(startMap.waitForExistence(timeout:10))
  attach(app,"Route-preview-with-two-guidance-modes")
  startMap.tap();app.buttons["確認してナビを開始"].tap()
  XCTAssertTrue(app.otherElements["instructionBanner"].waitForExistence(timeout:10));XCTAssertTrue(app.otherElements["navigationMap"].exists)
  XCTAssertTrue(app.descendants(matching:.any).matching(NSPredicate(format:"label CONTAINS %@","徒歩目安")).firstMatch.waitForExistence(timeout:10))
  attach(app,"Map-navigation")
  for removed in ["再読み上げ","経路一覧"] { XCTAssertFalse(app.buttons[removed].exists,removed) }
  // Map navigation → camera guidance → back to the map.
  app.buttons["navSwitchCamera"].tap()
  XCTAssertTrue(app.otherElements["arDirection"].waitForExistence(timeout:10))
  app.buttons["switchToMapNavigation"].tap();XCTAssertTrue(app.otherElements["navigationMap"].waitForExistence(timeout:5))
  // Camera guidance can also start from the route preview.
  app.buttons["endNavigation"].tap();app.buttons["案内を終了"].tap()
  app.buttons["通行不可を避ける経路を確認"].tap()
  let startCamera=app.buttons["startCameraNavigation"];XCTAssertTrue(startCamera.waitForExistence(timeout:10))
  startCamera.tap();app.buttons["確認して全面カメラで案内開始"].tap()
  XCTAssertTrue(app.otherElements["arDirection"].waitForExistence(timeout:10))
  XCTAssertTrue(app.buttons["switchToMapNavigation"].exists)
  attach(app,"Camera-navigation-AR-arrow")
  app.buttons["switchToMapNavigation"].tap()
  XCTAssertTrue(app.otherElements["navigationMap"].waitForExistence(timeout:5))
  app.buttons["endNavigation"].tap();app.buttons["案内を終了"].tap()
  XCTAssertTrue(app.textFields["destinationQuery"].waitForExistence(timeout:5))
 }
 @MainActor func testStoppingCameraNavigationReturnsDirectlyToMap() throws {
  let app=launchMap(developer:true,simulated:true)
  let destination=app.buttons["京町・実験接続点を目的地にする"];XCTAssertTrue(destination.waitForExistence(timeout:10));destination.tap()
  let matched=app.staticTexts.containing(NSPredicate(format:"label CONTAINS %@","道路候補を照合")).firstMatch
  XCTAssertTrue(matched.waitForExistence(timeout:15),"simulated position must match a road")
  app.buttons["通行不可を避ける経路を確認"].tap()
  let startCamera=app.buttons["startCameraNavigation"];XCTAssertTrue(startCamera.waitForExistence(timeout:10));startCamera.tap()
  app.buttons["確認して全面カメラで案内開始"].tap()
  XCTAssertTrue(app.buttons["cameraMenu"].waitForExistence(timeout:10))
  app.buttons["cameraMenu"].tap()
  let stopGuidance=app.buttons["案内を停止"];XCTAssertTrue(stopGuidance.waitForExistence(timeout:5));stopGuidance.tap()
  let confirmStop=app.buttons["停止"];XCTAssertTrue(confirmStop.waitForExistence(timeout:5));confirmStop.tap()
  XCTAssertTrue(app.textFields["destinationQuery"].waitForExistence(timeout:5))
  XCTAssertFalse(app.staticTexts["カメラ停止中"].exists)
  XCTAssertFalse(app.staticTexts["カメラは画面を開くと自動で起動します。起動しない場合は地図へ戻り、もう一度カメラボタンを押してください"].exists)
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
  XCTAssertFalse(app.buttons["placeSetDestination"].exists,"「目的地にする」 was removed; out-of-range places cannot become destinations")
 }
 @MainActor func testReportLegendDoesNotSwallowMapTap() throws {
  let app=launchMap();app.buttons["通行不可を登録"].tap()
  let message=app.staticTexts["reportTapFeedback"]
  XCTAssertTrue(message.waitForExistence(timeout:5));let before=message.label
  let map=app.otherElements["reportRoadMap"];reach(map,app:app)
  map.coordinate(withNormalizedOffset:CGVector(dx:0.2,dy:0.07)).tap()
  let changed=NSPredicate(format:"label != %@",before)
  expectation(for:changed,evaluatedWith:message)
  waitForExpectations(timeout:5)
  attach(app,"Report-tap-through-legend")
 }
 @MainActor func testMapTapRoadSelectionIsDefault() throws {
  let app=launchMap();app.buttons["通行不可を登録"].tap()
  XCTAssertTrue(app.staticTexts["道路を選ぶ"].waitForExistence(timeout:5))
  XCTAssertTrue(app.buttons["戻る"].exists)
  XCTAssertFalse(app.buttons["roadListAlternative"].exists)
  XCTAssertFalse(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","区間）")).firstMatch.exists)
  XCTAssertFalse(app.staticTexts["なぞって複数区間を選択"].exists)
  XCTAssertFalse(app.switches["なぞり選択モード"].exists)
  XCTAssertFalse(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","edge.")).firstMatch.exists)
  selectRoadOnReportMap(app)
  XCTAssertTrue(app.buttons["対象を確認して登録"].isEnabled)
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
  let app=launchMap(simulated:true);let map=app.otherElements["homeMap"];XCTAssertTrue(map.waitForExistence(timeout:10))
  // Above the bottom panel, below the chips. A POI under the finger would open its own card instead.
  map.coordinate(withNormalizedOffset:CGVector(dx:0.25,dy:0.38)).press(forDuration:1.0)
  XCTAssertTrue(app.otherElements["placeCard"].waitForExistence(timeout:5))
  add(XCTAttachment(string:app.staticTexts["placeName"].label))
  for id in ["placeRoute","closePlace"] { XCTAssertTrue(app.buttons[id].exists,id) }
  attach(app,"Place-card-dropped-pin")
  app.buttons["placeRoute"].tap()
  XCTAssertFalse(app.otherElements["placeCard"].exists)
  XCTAssertFalse(app.staticTexts["案内の終点を確認"].exists)
  XCTAssertFalse(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","destinationConnection.")).firstMatch.exists)
  XCTAssertTrue(app.buttons["startMapNavigation"].waitForExistence(timeout:15),"地図で選んだ目的地も自動で経路確認へ進むこと")
 }
}
