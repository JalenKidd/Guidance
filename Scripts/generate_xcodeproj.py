#!/usr/bin/env python3
"""Generate GuideAI.xcodeproj for local development."""
from __future__ import annotations

import json
import os
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def uid() -> str:
    return uuid.uuid4().hex[:24].upper()


class PBX:
    def __init__(self) -> None:
        self.objects: dict[str, dict] = {}

    def add(self, isa: str, **kwargs) -> str:
        key = uid()
        obj = {"isa": isa, **kwargs}
        self.objects[key] = obj
        return key


def swift_files(folder: Path) -> list[Path]:
    return sorted(folder.rglob("*.swift"))


def main() -> None:
    pbx = PBX()

    main_swift = swift_files(ROOT / "GuideAI")
    test_swift = swift_files(ROOT / "GuideAITests")

    ext_targets = {
        "GuideAIShieldConfiguration": {
            "folder": ROOT / "Extensions/GuideAIShieldConfiguration",
            "product": "GuideAIShieldConfiguration.appex",
            "bundle": "com.cac.guideai.ShieldConfiguration",
            "entitlements": "Extensions/GuideAIShieldConfiguration/GuideAIShieldConfiguration.entitlements",
            "frameworks": ["ManagedSettings.framework", "ManagedSettingsUI.framework"],
        },
        "GuideAIShieldAction": {
            "folder": ROOT / "Extensions/GuideAIShieldAction",
            "product": "GuideAIShieldAction.appex",
            "bundle": "com.cac.guideai.ShieldAction",
            "entitlements": "Extensions/GuideAIShieldAction/GuideAIShieldAction.entitlements",
            "frameworks": ["ManagedSettings.framework"],
        },
        "GuideAIDeviceActivityMonitor": {
            "folder": ROOT / "Extensions/GuideAIDeviceActivityMonitor",
            "product": "GuideAIDeviceActivityMonitor.appex",
            "bundle": "com.cac.guideai.DeviceActivityMonitor",
            "entitlements": "Extensions/GuideAIDeviceActivityMonitor/GuideAIDeviceActivityMonitor.entitlements",
            "frameworks": ["DeviceActivity.framework"],
        },
    }

    file_refs: dict[Path, str] = {}

    def file_ref(path: Path) -> str:
        if path in file_refs:
            return file_refs[path]
        rel = path.relative_to(ROOT).as_posix()
        fr = pbx.add("PBXFileReference", lastKnownFileType=guess_type(path), path=rel, sourceTree="SOURCE_ROOT")
        file_refs[path] = fr
        return fr

    def guess_type(path: Path) -> str:
        ext = path.suffix.lower()
        return {
            ".swift": "sourcecode.swift",
            ".plist": "text.plist.xml",
            ".entitlements": "text.plist.entitlements",
            ".json": "text.json",
        }.get(ext, "file")

    # Groups
    main_group = pbx.add("PBXGroup", children=[], sourceTree="<group>")
    products_group = pbx.add("PBXGroup", children=[], name="Products", sourceTree="<group>")

    guideai_group = pbx.add("PBXGroup", children=[], name="GuideAI", sourceTree="<group>")
    ext_group = pbx.add("PBXGroup", children=[], name="Extensions", sourceTree="<group>")
    tests_group = pbx.add("PBXGroup", children=[], name="GuideAITests", sourceTree="<group>")

    pbx.objects[main_group]["children"] = [guideai_group, ext_group, tests_group, products_group]

    assets_path = ROOT / "GuideAI/Assets.xcassets"
    assets_ref = file_ref(assets_path)
    entitlements_ref = file_ref(ROOT / "GuideAI/GuideAI.entitlements")
    info_plist_ref = file_ref(ROOT / "GuideAI/Info.plist")

    guideai_swift_refs = [file_ref(p) for p in main_swift]
    pbx.objects[guideai_group]["children"] = guideai_swift_refs + [assets_ref, entitlements_ref, info_plist_ref]

    # Extension groups & file refs
    ext_target_ids: dict[str, dict] = {}
    embed_files: list[str] = []

    for name, cfg in ext_targets.items():
        g = pbx.add("PBXGroup", children=[], name=name, sourceTree="<group>")
        pbx.objects[ext_group]["children"].append(g)
        sources = [file_ref(p) for p in swift_files(cfg["folder"])]
        plist_ref = file_ref(cfg["folder"] / "Info.plist")
        ent_ref = file_ref(ROOT / cfg["entitlements"])
        pbx.objects[g]["children"] = sources + [plist_ref, ent_ref]

    tests_refs = [file_ref(p) for p in test_swift]
    pbx.objects[tests_group]["children"] = tests_refs

    # Products
    app_product = pbx.add("PBXFileReference", explicitFileType="wrapper.application", includeInIndex=0, path="GuideAI.app", sourceTree="BUILT_PRODUCTS_DIR")
    test_product = pbx.add("PBXFileReference", explicitFileType="wrapper.cfbundle", includeInIndex=0, path="GuideAITests.xctest", sourceTree="BUILT_PRODUCTS_DIR")
    pbx.objects[products_group]["children"] = [app_product]

    ext_products: dict[str, str] = {}
    for name, cfg in ext_targets.items():
        pr = pbx.add(
            "PBXFileReference",
            explicitFileType="wrapper.app-extension",
            includeInIndex=0,
            path=cfg["product"],
            sourceTree="BUILT_PRODUCTS_DIR",
        )
        ext_products[name] = pr
        pbx.objects[products_group]["children"].append(pr)

    pbx.objects[products_group]["children"].append(test_product)

    # Build phases helper
    def sources_phase(refs: list[str]) -> str:
        phase = pbx.add("PBXSourcesBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
        for r in refs:
            bf = pbx.add("PBXBuildFile", fileRef=r)
            pbx.objects[phase]["files"].append(bf)
        return phase

    def frameworks_phase(framework_names: list[str]) -> str:
        phase = pbx.add("PBXFrameworksBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
        for fw in framework_names:
            fr = pbx.add("PBXFileReference", lastKnownFileType="wrapper.framework", name=fw.replace(".framework", ""), path=f"System/Library/Frameworks/{fw}", sourceTree="SDKROOT")
            bf = pbx.add("PBXBuildFile", fileRef=fr)
            pbx.objects[phase]["files"].append(bf)
        return phase

    def resources_phase(refs: list[str]) -> str:
        phase = pbx.add("PBXResourcesBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
        for r in refs:
            bf = pbx.add("PBXBuildFile", fileRef=r)
            pbx.objects[phase]["files"].append(bf)
        return phase

    # App target
    app_sources = sources_phase(guideai_swift_refs)
    app_frameworks = frameworks_phase(
        [
            "FamilyControls.framework",
            "ManagedSettings.framework",
            "DeviceActivity.framework",
            "LocalAuthentication.framework",
        ]
    )
    app_resources = resources_phase([assets_ref])

    embed_phase = pbx.add(
        "PBXCopyFilesBuildPhase",
        buildActionMask=2147483647,
        dstPath="",
        dstSubfolderSpec=13,
        files=[],
        name="Embed Foundation Extensions",
        runOnlyForDeploymentPostprocessing=0,
    )

    ext_native: dict[str, str] = {}
    ext_dep_ids: list[str] = []

    for name, cfg in ext_targets.items():
        folder = cfg["folder"]
        src_refs = [file_ref(p) for p in swift_files(folder)]
        src_phase = sources_phase(src_refs)
        fw_phase = frameworks_phase(cfg["frameworks"])
        res_phase = resources_phase([])

        target = pbx.add(
            "PBXNativeTarget",
            name=name,
            productName=name,
            productReference=ext_products[name],
            productType="com.apple.product-type.app-extension",
            buildConfigurationList=pbx.add("XCConfigurationList", buildConfigurations=[], defaultConfigurationIsVisible=0, defaultConfigurationName="Release"),
            buildPhases=[src_phase, fw_phase, res_phase],
            dependencies=[],
        )
        ext_native[name] = target

        bf = pbx.add("PBXBuildFile", fileRef=ext_products[name], settings={"ATTRIBUTES": ["RemoveHeadersOnCopy"]})
        pbx.objects[embed_phase]["files"].append(bf)

        dep = pbx.add("PBXTargetDependency", target=target, targetProxy=pbx.add("PBXContainerItemProxy", containerPortal="", proxyType=1, remoteGlobalIDString=target, remoteInfo=name))
        ext_dep_ids.append(dep)

        ext_target_ids[name] = {
            "target": target,
            "cfg_list": pbx.objects[target]["buildConfigurationList"],
            "entitlements": cfg["entitlements"],
            "bundle": cfg["bundle"],
            "info_plist": (folder / "Info.plist").relative_to(ROOT).as_posix(),
        }

    app_cfg_list = pbx.add("XCConfigurationList", buildConfigurations=[], defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
    app_target = pbx.add(
        "PBXNativeTarget",
        name="GuideAI",
        productName="GuideAI",
        productReference=app_product,
        productType="com.apple.product-type.application",
        buildConfigurationList=app_cfg_list,
        buildPhases=[app_sources, app_frameworks, app_resources, embed_phase],
        dependencies=[pbx.add("PBXTargetDependency", target=ext_native[n], targetProxy=pbx.add("PBXContainerItemProxy", containerPortal="", proxyType=1, remoteGlobalIDString=ext_native[n], remoteInfo=n)) for n in ext_targets],
    )

    # Fix container portal on proxies - set after project created
    project_cfg_list = pbx.add("XCConfigurationList", buildConfigurations=[], defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
    project = pbx.add(
        "PBXProject",
        attributes={"BuildIndependentTargetsInParallel": 1, "LastUpgradeCheck": 2600, "TargetAttributes": {app_target: {"CreatedOnToolsVersion": "16.0"}}},
        buildConfigurationList=project_cfg_list,
        compatibilityVersion="Xcode 14.0",
        developmentRegion="en",
        hasScannedForEncodings=0,
        knownRegions=["en"],
        mainGroup=main_group,
        productRefGroup=products_group,
        projectDirPath="",
        projectRoot="",
        targets=[app_target] + [ext_native[n] for n in ext_targets],
    )

    for obj in pbx.objects.values():
        if obj.get("isa") == "PBXContainerItemProxy":
            obj["containerPortal"] = project

    # Tests target
    test_sources = sources_phase(tests_refs)
    test_frameworks = frameworks_phase([])
    test_cfg_list = pbx.add("XCConfigurationList", buildConfigurations=[], defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
    test_target = pbx.add(
        "PBXNativeTarget",
        name="GuideAITests",
        productName="GuideAITests",
        productReference=test_product,
        productType="com.apple.product-type.bundle.unit-test",
        buildConfigurationList=test_cfg_list,
        buildPhases=[test_sources, test_frameworks],
        dependencies=[pbx.add("PBXTargetDependency", target=app_target, targetProxy=pbx.add("PBXContainerItemProxy", containerPortal=project, proxyType=1, remoteGlobalIDString=app_target, remoteInfo="GuideAI"))],
    )
    pbx.objects[project]["targets"].append(test_target)

    common_debug = {
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "ENABLE_TESTABILITY": "YES",
        "GCC_DYNAMIC_NO_PIC": "NO",
        "GCC_OPTIMIZATION_LEVEL": "0",
        "ONLY_ACTIVE_ARCH": "YES",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
    }
    common_release = {
        "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
        "SWIFT_COMPILATION_MODE": "wholemodule",
        "VALIDATE_PRODUCT": "YES",
    }
    common_ios = {
        "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
        "SDKROOT": "iphoneos",
        "SWIFT_VERSION": "5.0",
        "TARGETED_DEVICE_FAMILY": "1",
        "CODE_SIGN_STYLE": "Automatic",
        "DEVELOPMENT_TEAM": "",
    }

    def add_cfgs(cfg_list_id: str, extra: dict) -> None:
        for name, extra_build in [("Debug", common_debug), ("Release", common_release)]:
            cfg = pbx.add(
                "XCBuildConfiguration",
                name=name,
                buildSettings={**common_ios, **extra_build, **extra},
            )
            pbx.objects[cfg_list_id]["buildConfigurations"].append(cfg)

    add_cfgs(
        project_cfg_list,
        {
            "ALWAYS_SEARCH_USER_PATHS": "NO",
            "CLANG_ENABLE_MODULES": "YES",
            "COPY_PHASE_STRIP": "NO",
        },
    )

    add_cfgs(
        app_cfg_list,
        {
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
            "CODE_SIGN_ENTITLEMENTS": "GuideAI/GuideAI.entitlements",
            "CURRENT_PROJECT_VERSION": "1",
            "GENERATE_INFOPLIST_FILE": "NO",
            "INFOPLIST_FILE": "GuideAI/Info.plist",
            "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
            "MARKETING_VERSION": "1.0",
            "PRODUCT_BUNDLE_IDENTIFIER": "com.cac.guideai",
            "PRODUCT_NAME": "$(TARGET_NAME)",
            "SWIFT_EMIT_LOC_STRINGS": "YES",
        },
    )

    for name, meta in ext_target_ids.items():
        add_cfgs(
            meta["cfg_list"],
            {
                "CODE_SIGN_ENTITLEMENTS": meta["entitlements"],
                "CURRENT_PROJECT_VERSION": "1",
                "GENERATE_INFOPLIST_FILE": "NO",
                "INFOPLIST_FILE": meta["info_plist"],
                "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks",
                "MARKETING_VERSION": "1.0",
                "PRODUCT_BUNDLE_IDENTIFIER": meta["bundle"],
                "PRODUCT_NAME": "$(TARGET_NAME)",
                "SKIP_INSTALL": "YES",
            },
        )

    add_cfgs(
        test_cfg_list,
        {
            "BUNDLE_LOADER": "$(TEST_HOST)",
            "GENERATE_INFOPLIST_FILE": "YES",
            "MARKETING_VERSION": "1.0",
            "PRODUCT_BUNDLE_IDENTIFIER": "com.cac.guideai.tests",
            "PRODUCT_NAME": "$(TARGET_NAME)",
            "SWIFT_EMIT_LOC_STRINGS": "NO",
            "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/GuideAI.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/GuideAI",
        },
    )

    out_dir = ROOT / "GuideAI.xcodeproj"
    out_dir.mkdir(exist_ok=True)
    project_json = {
        "archiveVersion": 1,
        "classes": {},
        "objectVersion": 56,
        "objects": pbx.objects,
        "rootObject": project,
    }
    (out_dir / "project.pbxproj").write_text(format_pbx(project_json))
    scheme_dir = out_dir / "xcshareddata" / "xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)
    (scheme_dir / "GuideAI.xcscheme").write_text(scheme_xml(app_target, test_target))
    workspace_dir = out_dir / "project.xcworkspace"
    workspace_dir.mkdir(parents=True, exist_ok=True)
    (workspace_dir / "contents.xcworkspacedata").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<Workspace\n   version = "1.0">\n'
        '   <FileRef\n      location = "self:">\n   </FileRef>\n'
        '</Workspace>\n'
    )
    print(f"Wrote {out_dir / 'project.pbxproj'}")


def format_pbx(data: dict) -> str:
    # Minimal plist formatter for pbxproj
    lines = [
        "// !$*UTF8*$!",
        "{",
        f"\tarchiveVersion = {data['archiveVersion']};",
        "\tclasses = {",
        "\t};",
        f"\tobjectVersion = {data['objectVersion']};",
        "\tobjects = {",
    ]
    for key, obj in data["objects"].items():
        lines.append(f"\t\t{key} = {{")
        lines.append(f"\t\t\tisa = {obj['isa']};")
        for k, v in obj.items():
            if k == "isa":
                continue
            lines.append(f"\t\t\t{k} = {render(v, 3)};")
        lines.append("\t\t};")
    lines.append("\t};")
    lines.append(f"\trootObject = {data['rootObject']} /* Project object */;")
    lines.append("}")
    return "\n".join(lines) + "\n"


def render(v, indent: int) -> str:
    sp = "\t" * indent
    if isinstance(v, bool):
        return "YES" if v else "NO"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, str):
        if v == "":
            return '""'
        if v in ("<group>", "SOURCE_ROOT", "BUILT_PRODUCTS_DIR", "SDKROOT"):
            return f'"{v}"'
        if " " in v or v.startswith("$") or "/" in v or "." in v or v.startswith("("):
            return f'"{v}"'
        return v
    if isinstance(v, list):
        if not v:
            return "()"
        inner = ",\n".join(f"{sp}\t{render(i, indent + 1)}" for i in v)
        return f"(\n{inner},\n{sp})"
    if isinstance(v, dict):
        if not v:
            return "{}"
        parts = []
        for k, val in v.items():
            parts.append(f'{sp}\t{k} = {render(val, indent + 1)};')
        return "{\n" + "\n".join(parts) + f"\n{sp}}}"
    return str(v)


def scheme_xml(app_target: str, test_target: str) -> str:
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "2600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{app_target}"
               BuildableName = "GuideAI.app"
               BlueprintName = "GuideAI"
               ReferencedContainer = "container:GuideAI.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference
            skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{test_target}"
               BuildableName = "GuideAITests.xctest"
               BlueprintName = "GuideAITests"
               ReferencedContainer = "container:GuideAI.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_target}"
            BuildableName = "GuideAI.app"
            BlueprintName = "GuideAI"
            ReferencedContainer = "container:GuideAI.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
</Scheme>
"""


if __name__ == "__main__":
    main()
