"""Generate a deterministic native Xcode project using only Python's stdlib.
The generated .xcodeproj and shared scheme are committed; CI verifies consistency.
"""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parent.parent
objects = {}

def ident(key):
    return hashlib.sha256(key.encode()).hexdigest()[:24].upper()

def q(value):
    return json.dumps(str(value), ensure_ascii=False)

def add(key, isa, body):
    oid = ident(key)
    objects[oid] = f"isa = {isa}; {body}"
    return oid

def refs(items):
    return "(" + ", ".join(items) + ");"

def settings(values):
    return "{" + " ".join(f"{k} = {q(v)};" for k,v in values.items()) + "}"

core_product = add("core-product", "XCSwiftPackageProductDependency", "productName = CampusLensCore;")
package = add("local-package", "XCLocalSwiftPackageReference", 'relativePath = ".";')

groups = []
targets = []
products = []
target_ids = {name: ident("target-"+name) for name in ["CampusLens","CampusLensTests","CampusLensUITests"]}
for name, source_paths, product_type in [
    # Path comparison is case-insensitive on Windows but case-sensitive on macOS.
    # Compare explicit strings so names such as AIClient and AdjustmentSheet
    # generate the same project ordering on both hosts.
    ("CampusLens", sorted((ROOT/"App").glob("*.swift"),key=lambda p:p.name), "com.apple.product-type.application"),
    ("CampusLensTests", sorted((ROOT/"Tests/CampusLensCoreTests").glob("*.swift"),key=lambda p:p.name) + sorted((ROOT/"AppTests").glob("*.swift"),key=lambda p:p.name), "com.apple.product-type.bundle.unit-test"),
    ("CampusLensUITests", sorted((ROOT/"UITests").glob("*.swift"),key=lambda p:p.name), "com.apple.product-type.bundle.ui-testing")
]:
    file_ids = []
    build_ids = []
    for source in source_paths:
        path = source.relative_to(ROOT).as_posix()
        file_id = add("file-"+name+path, "PBXFileReference", f'lastKnownFileType = sourcecode.swift; path = {q(path)}; sourceTree = SOURCE_ROOT;')
        build_id = add("build-"+name+path, "PBXBuildFile", f"fileRef = {file_id};")
        file_ids.append(file_id); build_ids.append(build_id)
    resources = []
    if name == "CampusLens":
        for path,kind in [("App/Info.plist","text.plist.xml"),("App/PrivacyInfo.xcprivacy","text.plist.xml"),("App/Assets.xcassets","folder.assetcatalog")]:
            fid = add("file-"+path,"PBXFileReference",f'lastKnownFileType = {kind}; path = {q(path)}; sourceTree = SOURCE_ROOT;')
            file_ids.append(fid)
            if "Info.plist" not in path:
                resources.append(add("resource-"+path,"PBXBuildFile",f"fileRef = {fid};"))
    groups.append(add("group-"+name,"PBXGroup",f"children = {refs(file_ids)} name = {q(name)}; sourceTree = \"<group>\";"))
    suffix = ".app" if name == "CampusLens" else ".xctest"
    product = add("product-"+name,"PBXFileReference",f'explicitFileType = {"wrapper.application" if suffix == ".app" else "wrapper.cfbundle"}; includeInIndex = 0; path = {q(name+suffix)}; sourceTree = BUILT_PRODUCTS_DIR;')
    products.append(product)
    sources_phase = add("sources-"+name,"PBXSourcesBuildPhase",f"buildActionMask = 2147483647; files = {refs(build_ids)} runOnlyForDeploymentPostprocessing = 0;")
    frameworks = []
    if name != "CampusLensUITests":
        frameworks.append(add("core-link-"+name,"PBXBuildFile",f"productRef = {core_product};"))
    frameworks_phase = add("frameworks-"+name,"PBXFrameworksBuildPhase",f"buildActionMask = 2147483647; files = {refs(frameworks)} runOnlyForDeploymentPostprocessing = 0;")
    resources_phase = add("resources-"+name,"PBXResourcesBuildPhase",f"buildActionMask = 2147483647; files = {refs(resources)} runOnlyForDeploymentPostprocessing = 0;")
    configs = []
    for config in ["Debug","Release"]:
        values = {"PRODUCT_NAME":"$(TARGET_NAME)","PRODUCT_BUNDLE_IDENTIFIER":"org.campuslens."+name,
                  "SWIFT_VERSION":"6.0","IPHONEOS_DEPLOYMENT_TARGET":"26.0","TARGETED_DEVICE_FAMILY":"1",
                  "CODE_SIGN_STYLE":"Automatic","CURRENT_PROJECT_VERSION":"1","MARKETING_VERSION":"0.2.0",
                  "SWIFT_STRICT_CONCURRENCY":"complete","GENERATE_INFOPLIST_FILE":"YES"}
        if name == "CampusLens":
            values.update({"GENERATE_INFOPLIST_FILE":"NO","INFOPLIST_FILE":"App/Info.plist","ASSETCATALOG_COMPILER_APPICON_NAME":"AppIcon"})
        else:
            values["TEST_TARGET_NAME"] = "CampusLens"
            if name == "CampusLensTests":
                values["TEST_HOST"] = "$(BUILT_PRODUCTS_DIR)/CampusLens.app/CampusLens"
                values["BUNDLE_LOADER"] = "$(TEST_HOST)"
        if config == "Debug":
            values["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG $(inherited)"
            values["SWIFT_OPTIMIZATION_LEVEL"] = "-Onone"
        else: values["SWIFT_OPTIMIZATION_LEVEL"] = "-O"
        configs.append(add("config-"+name+config,"XCBuildConfiguration",f"buildSettings = {settings(values)}; name = {config};"))
    config_list = add("configs-"+name,"XCConfigurationList",f"buildConfigurations = {refs(configs)} defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
    dependencies = []
    if name != "CampusLens":
        proxy = add("proxy-"+name,"PBXContainerItemProxy",f"containerPortal = {ident('project')}; proxyType = 1; remoteGlobalIDString = {target_ids['CampusLens']}; remoteInfo = CampusLens;")
        dependencies.append(add("dependency-"+name,"PBXTargetDependency",f"target = {target_ids['CampusLens']}; targetProxy = {proxy};"))
    targets.append(add("target-"+name,"PBXNativeTarget",f"buildConfigurationList = {config_list}; buildPhases = {refs([sources_phase,frameworks_phase,resources_phase])} buildRules = (); dependencies = {refs(dependencies)} name = {q(name)}; productName = {q(name)}; productReference = {product}; productType = {q(product_type)}; packageProductDependencies = {refs([core_product] if name != 'CampusLensUITests' else [])}"))

products_group = add("products","PBXGroup",f"children = {refs(products)} name = Products; sourceTree = \"<group>\";")
main_group = add("main-group","PBXGroup",f"children = {refs(groups+[products_group])} sourceTree = \"<group>\";")
configs = []
for config in ["Debug","Release"]:
    values = {"CLANG_ENABLE_MODULES":"YES","SDKROOT":"iphoneos","ENABLE_TESTABILITY":"YES" if config == "Debug" else "NO",
              "DEBUG_INFORMATION_FORMAT":"dwarf" if config == "Debug" else "dwarf-with-dsym","SWIFT_VERSION":"6.0",
              "ONLY_ACTIVE_ARCH":"YES" if config == "Debug" else "NO"}
    configs.append(add("project-config-"+config,"XCBuildConfiguration",f"buildSettings = {settings(values)}; name = {config};"))
config_list = add("project-configs","XCConfigurationList",f"buildConfigurations = {refs(configs)} defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
add("project","PBXProject",f"attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2600; }}; buildConfigurationList = {config_list}; compatibilityVersion = \"Xcode 15.0\"; developmentRegion = zh-Hans; hasScannedForEncodings = 0; knownRegions = (en, Base, \"zh-Hans\"); mainGroup = {main_group}; packageReferences = {refs([package])} productRefGroup = {products_group}; projectDirPath = \"\"; projectRoot = \"\"; targets = {refs(targets)}")
project_dir = ROOT/"CampusLens.xcodeproj"
project_dir.mkdir(exist_ok=True)
contents = "// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 60; objects = {\n"
contents += "\n".join(f"{oid} = {{ {body} }};" for oid,body in sorted(objects.items()))
contents += f"\n}}; rootObject = {ident('project')}; }}\n"
(project_dir/"project.pbxproj").write_text(contents,encoding="utf-8",newline="\n")
def buildable(name):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_ids[name]}" BuildableName="{name}{".app" if name == "CampusLens" else ".xctest"}" BlueprintName="{name}" ReferencedContainer="container:CampusLens.xcodeproj"/>'
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.7">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{buildable("CampusLens")}</BuildActionEntry>
</BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>
<TestableReference skipped="NO">{buildable("CampusLensTests")}</TestableReference>
<TestableReference skipped="NO">{buildable("CampusLensUITests")}</TestableReference>
</Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable("CampusLens")}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable("CampusLens")}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
scheme_dir = project_dir/"xcshareddata/xcschemes"
scheme_dir.mkdir(parents=True,exist_ok=True)
(scheme_dir/"CampusLens.xcscheme").write_text(scheme,encoding="utf-8",newline="\n")
print("Generated native CampusLens project and shared scheme")
