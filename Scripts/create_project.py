#!/usr/bin/env python3
import pathlib, hashlib
r=pathlib.Path(__file__).resolve().parent.parent
files=sorted([*r.glob('App/*.swift'),*r.glob('Core/*.swift'),r/'Data/kokura-network.json',r/'App/PrivacyInfo.xcprivacy',r/'App/Assets.xcassets'])
model=r/'App/Models/vidvipo_yolov8n_2023-05-19.mlmodelc'
if model.exists(): files.append(model)
def uid(s):return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
def rel(f):return f.relative_to(r).as_posix()
objects=[]
def add(key,body):objects.append(f'{uid(key)} = {{ {body} }};')
for f in files:
 p=rel(f);kind='sourcecode.swift' if f.suffix=='.swift' else 'folder.assetcatalog' if f.suffix=='.xcassets' else 'folder' if f.suffix=='.mlmodelc' else 'text.xml' if f.suffix=='.xcprivacy' else 'text.json';add(p,f'isa = PBXFileReference; lastKnownFileType = {kind}; path = "{p}"; sourceTree = SOURCE_ROOT;');add('build'+p,f'isa = PBXBuildFile; fileRef = {uid(p)};')
# Signing values come from Config/Base.xcconfig + untracked Config/Local.xcconfig.
add('xcconfig','isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = "Config/Base.xcconfig"; sourceTree = SOURCE_ROOT;')
add('product','isa = PBXFileReference; explicitFileType = wrapper.application; path = JunctionGuide.app; sourceTree = BUILT_PRODUCTS_DIR;')
add('uitestfile','isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Tests/UITests/SmokeTests.swift; sourceTree = SOURCE_ROOT;')
add('uitestbuild',f'isa = PBXBuildFile; fileRef = {uid("uitestfile")};')
add('uitestproduct','isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = JunctionGuideUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
add('main','isa = PBXGroup; children = ('+','.join(uid(rel(f)) for f in files)+','+uid('xcconfig')+','+uid('uitestfile')+','+uid('products')+'); sourceTree = "<group>";')
add('products',f'isa = PBXGroup; children = ({uid("product")},{uid("uitestproduct")}); name = Products; sourceTree = "<group>";')
add('uitestsources',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({uid("uitestbuild")}); runOnlyForDeploymentPostprocessing = 0;')
for name,kind in [('sources','PBXSourcesBuildPhase'),('resources','PBXResourcesBuildPhase'),('frameworks','PBXFrameworksBuildPhase')]:
 fs=[uid('build'+rel(f)) for f in files if (name=='sources' and f.suffix=='.swift') or (name=='resources' and f.suffix in ['.json','.mlmodelc','.xcprivacy','.xcassets'])]
 add(name,f'isa = {kind}; buildActionMask = 2147483647; files = ('+','.join(fs)+'); runOnlyForDeploymentPostprocessing = 0;')
settings='CLANG_ENABLE_MODULES = YES; SWIFT_VERSION = 6.0; IPHONEOS_DEPLOYMENT_TARGET = 26.0; SDKROOT = iphoneos;'
appsettings='PRODUCT_NAME = "$(TARGET_NAME)"; PRODUCT_BUNDLE_IDENTIFIER = "$(JG_BUNDLE_ID)"; DEVELOPMENT_TEAM = "$(JG_TEAM)"; INFOPLIST_FILE = App/Info.plist; GENERATE_INFOPLIST_FILE = NO; TARGETED_DEVICE_FAMILY = 1; CODE_SIGN_STYLE = Automatic; SWIFT_EMIT_LOC_STRINGS = YES; ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;'
for scope in ['project','app','uitest']:
 for conf in ['Debug','Release']:
  extra=appsettings if scope=='app' else 'PRODUCT_NAME = "$(TARGET_NAME)"; PRODUCT_BUNDLE_IDENTIFIER = "$(JG_BUNDLE_ID)UITests"; DEVELOPMENT_TEAM = "$(JG_TEAM)"; GENERATE_INFOPLIST_FILE = YES; TARGETED_DEVICE_FAMILY = 1; CODE_SIGN_STYLE = Automatic; TEST_TARGET_NAME = JunctionGuide;' if scope=='uitest' else ''
  base=f'baseConfigurationReference = {uid("xcconfig")}; ' if scope!='project' else ''
  add(scope+conf,'isa = XCBuildConfiguration; '+base+'buildSettings = { '+settings+' '+extra+(' SWIFT_OPTIMIZATION_LEVEL = "-Onone"; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG; DEBUG_INFORMATION_FORMAT = dwarf;' if conf=='Debug' else ' SWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";')+f' }}; name = {conf};')
 add(scope+'configs',f'isa = XCConfigurationList; buildConfigurations = ({uid(scope+"Debug")},{uid(scope+"Release")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
add('target',f'isa = PBXNativeTarget; buildConfigurationList = {uid("appconfigs")}; buildPhases = ({uid("sources")},{uid("frameworks")},{uid("resources")}); buildRules = (); dependencies = (); name = JunctionGuide; productName = JunctionGuide; productReference = {uid("product")}; productType = "com.apple.product-type.application";')
add('uitestproxy',f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {uid("target")}; remoteInfo = JunctionGuide;')
add('uitestdependency',f'isa = PBXTargetDependency; target = {uid("target")}; targetProxy = {uid("uitestproxy")};')
add('uitesttarget',f'isa = PBXNativeTarget; buildConfigurationList = {uid("uitestconfigs")}; buildPhases = ({uid("uitestsources")}); buildRules = (); dependencies = ({uid("uitestdependency")}); name = JunctionGuideUITests; productReference = {uid("uitestproduct")}; productType = "com.apple.product-type.bundle.ui-testing";')
add('project',f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2630; TargetAttributes = {{ {uid("uitesttarget")} = {{ TestTargetID = {uid("target")}; }}; }}; }}; buildConfigurationList = {uid("projectconfigs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = ja; hasScannedForEncodings = 0; knownRegions = (ja,en,Base); mainGroup = {uid("main")}; productRefGroup = {uid("products")}; projectDirPath = ""; projectRoot = ""; targets = ({uid("target")},{uid("uitesttarget")});')
(r/'JunctionGuide.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+f'\n}}; rootObject = {uid("project")}; }}\n')
(r/'JunctionGuide.xcodeproj/xcshareddata/xcschemes/JunctionGuide.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2630" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('target')}" BuildableName="JunctionGuide.app" BlueprintName="JunctionGuide" ReferencedContainer="container:JunctionGuide.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('target')}" BuildableName="JunctionGuide.app" BlueprintName="JunctionGuide" ReferencedContainer="container:JunctionGuide.xcodeproj"/></BuildableProductRunnable></LaunchAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')

# Keep the UI-test action in the generated shared scheme.
p=r/'JunctionGuide.xcodeproj/xcshareddata/xcschemes/JunctionGuide.xcscheme'
s=p.read_text();s=s.replace('<LaunchAction',f'<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("uitesttarget")}" BuildableName="JunctionGuideUITests.xctest" BlueprintName="JunctionGuideUITests" ReferencedContainer="container:JunctionGuide.xcodeproj"/></TestableReference></Testables></TestAction><LaunchAction');p.write_text(s)
