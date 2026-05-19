#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");

const rootDir = path.resolve(__dirname, "../..");
const sourcesDir = path.join(rootDir, "Sources");

const failures = [];
const notes = [];

function read(relativePath) {
  return fs.readFileSync(path.join(rootDir, relativePath), "utf8");
}

function walkSwiftFiles(dir) {
  const output = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      output.push(...walkSwiftFiles(fullPath));
    } else if (entry.isFile() && entry.name.endsWith(".swift")) {
      output.push(fullPath);
    }
  }
  return output;
}

function fail(message) {
  failures.push(message);
}

function note(message) {
  notes.push(message);
}

function assertContains(label, content, needle) {
  if (!content.includes(needle)) {
    fail(`${label}: missing expected source guard '${needle}'`);
  }
}

function countOccurrences(content, needle) {
  let count = 0;
  let index = 0;
  while (true) {
    const found = content.indexOf(needle, index);
    if (found === -1) {
      return count;
    }
    count += 1;
    index = found + needle.length;
  }
}

function constantValue(content, name) {
  const pattern = new RegExp(`\\b${name}\\b[^=]*=\\s*([0-9][0-9_]*(?:\\.[0-9]+)?)`);
  const match = content.match(pattern);
  if (!match) {
    fail(`missing constant '${name}'`);
    return null;
  }
  return Number(match[1].replace(/_/g, ""));
}

function assertAtMost(label, value, max) {
  if (value === null) {
    return;
  }
  if (value > max) {
    fail(`${label}: ${value} exceeds smooth baseline maximum ${max}`);
  }
}

function assertAtLeast(label, value, min) {
  if (value === null) {
    return;
  }
  if (value < min) {
    fail(`${label}: ${value} is below smooth baseline minimum ${min}`);
  }
}

function checkBroadAppModelObservation() {
  const broadObservationPattern = /@(?:EnvironmentObject|ObservedObject)[^\n]*AppModel|\.environmentObject\s*\(\s*appModel\s*\)/;
  const matches = [];
  for (const filePath of walkSwiftFiles(sourcesDir)) {
    const content = fs.readFileSync(filePath, "utf8");
    const lines = content.split(/\r?\n/);
    lines.forEach((line, index) => {
      if (broadObservationPattern.test(line)) {
        matches.push(`${path.relative(rootDir, filePath)}:${index + 1}: ${line.trim()}`);
      }
    });
  }

  if (matches.length > 0) {
    fail(`broad AppModel observation reintroduced:\n${matches.join("\n")}`);
  } else {
    note("AppModel broad observation guard passed");
  }
}

function checkSurfaceSwitchingBaseline() {
  const contentView = read("Sources/ContentView.swift");
  const sidebar = read("Sources/UI/XTPrimarySurface.swift");

  const inactiveReleaseNs = constantValue(contentView, "inactiveSurfaceReleaseDelayNanoseconds");
  const secondaryMountNs = constantValue(contentView, "secondarySurfaceMountDelayNanoseconds");
  const supervisorMountNs = constantValue(contentView, "supervisorSurfaceMountDelayNanoseconds");
  const supervisorPrewarmNs = constantValue(contentView, "supervisorSurfacePrewarmDelayNanoseconds");
  const sidebarCommitNs = constantValue(sidebar, "selectionCommitDelayNanoseconds");
  const projectSidebarReleaseNs = constantValue(sidebar, "projectSidebarReleaseDelayNanoseconds");

  assertAtMost("inactive surface release delay", inactiveReleaseNs, 200_000_000);
  assertAtMost("secondary surface mount delay", secondaryMountNs, 80_000_000);
  assertAtMost("supervisor surface mount delay", supervisorMountNs, 80_000_000);
  assertAtMost("supervisor surface prewarm delay", supervisorPrewarmNs, 600_000_000);
  assertAtMost("sidebar selection commit delay", sidebarCommitNs, 32_000_000);
  assertAtMost("project sidebar release delay", projectSidebarReleaseNs, 200_000_000);

  assertContains(
    "ContentView",
    contentView,
    "workSurfaceMounted || retainedWorkSurfaceAfterPrimarySwitch"
  );
  assertContains(
    "ContentView",
    contentView,
    "reviewSurfaceMounted || retainedReviewSurfaceAfterPrimarySwitch"
  );
  assertContains(
    "ContentView",
    contentView,
    "controlSurfaceMounted || retainedControlSurfaceAfterPrimarySwitch"
  );
  assertContains(
    "ContentView",
    contentView,
    "PrimarySurfaceWarmupView(surface: .work)"
  );
  assertContains(
    "ContentView",
    contentView,
    "PrimarySurfaceWarmupView(surface: .review)"
  );
  assertContains(
    "ContentView",
    contentView,
    "PrimarySurfaceWarmupView(surface: .control)"
  );
  assertContains(
    "XTPrimarySurface",
    sidebar,
    "ProjectSidebarView(isActive: displayedPrimarySurface == .work)"
  );

  const heavySurfaceCounts = [
    ["ContentWorkSurfaceHost(", countOccurrences(contentView, "ContentWorkSurfaceHost(")],
    ["XTReviewSurfaceView(", countOccurrences(contentView, "XTReviewSurfaceView(")],
    ["XTControlSurfaceView(", countOccurrences(contentView, "XTControlSurfaceView(")]
  ];
  for (const [label, count] of heavySurfaceCounts) {
    if (count !== 1) {
      fail(`${label}: expected exactly one root construction site in ContentView, found ${count}`);
    }
  }

  note("sidebar delayed mount/release guard passed");
}

function checkBackgroundCadenceBaseline() {
  const appModel = read("Sources/AppModel.swift");
  const supervisorManager = read("Sources/Supervisor/SupervisorManager.swift");

  const doctorInterval = constantValue(appModel, "backgroundUnifiedDoctorRefreshIntervalSec");
  const heartbeatInterval = constantValue(supervisorManager, "heartbeatIntervalSec");
  const schedulerPollInterval = constantValue(supervisorManager, "schedulerPollIntervalSec");

  assertAtLeast("background unified doctor refresh interval", doctorInterval, 20);
  assertAtLeast("supervisor heartbeat interval", heartbeatInterval, 300);
  assertAtLeast("supervisor scheduler poll interval", schedulerPollInterval, 12);

  const hubPollBlock = appModel.match(
    /nonisolated static func backgroundHubPollInterval[\s\S]*?private func shouldSuppressAutomaticReconnectDuringStartup/
  );
  if (!hubPollBlock) {
    fail("AppModel.backgroundHubPollInterval block not found");
  } else {
    const block = hubPollBlock[0];
    const disconnected = constantValue(block, "disconnectedInterval");
    const connected = constantValue(block, "connectedInterval");
    const remoteGenerate = constantValue(block, "remoteGenerateInterval");
    assertAtLeast("hub disconnected poll interval", disconnected, 5);
    assertAtLeast("hub connected poll interval", connected, 8);
    assertAtLeast("hub remote-generate poll interval", remoteGenerate, 12);
  }

  assertContains("AppModel", appModel, "assignIfChanged(\\.unifiedDoctorReport, report)");
  assertContains("AppModel", appModel, "Task.detached(priority: .utility)");
  note("background cadence guard passed");
}

function checkSupervisorWindowObservationBaseline() {
  const content = read("Sources/Supervisor/SupervisorViewContent.swift");

  if (content.includes("settingsSurfaceProjectionStore")) {
    fail("SupervisorViewContent must not observe the full settingsSurfaceProjectionStore; use the narrow settingsSupervisorSignalStore instead");
  }

  assertContains(
    "SupervisorViewContent",
    content,
    "@EnvironmentObject private var settingsSupervisorSignalStore: XTSettingsSupervisorSignalStore"
  );
  note("supervisor window narrow settings observation guard passed");
}

function checkSettingsOnlyObservationBaseline() {
  const settingsOnlyViews = [
    "Sources/UI/SupervisorSettingsView.swift",
    "Sources/UI/Supervisor/SupervisorPersonaCenterView.swift",
    "Sources/UI/Supervisor/SupervisorPersonalReviewCenterView.swift",
    "Sources/UI/Supervisor/SupervisorPersonalAssistantSummaryBoard.swift",
    "Sources/UI/Projects/CreateProjectSheet.swift"
  ];

  for (const relativePath of settingsOnlyViews) {
    const content = read(relativePath);
    if (content.includes("settingsSurfaceProjectionStore")) {
      fail(`${relativePath}: settings-only UI must not observe the full settingsSurfaceProjectionStore; use settingsValueStore instead`);
    }
    assertContains(
      relativePath,
      content,
      "@EnvironmentObject private var settingsValueStore: XTSettingsValueStore"
    );
  }
  note("settings-only narrow observation guard passed");
}

function main() {
  checkBroadAppModelObservation();
  checkSurfaceSwitchingBaseline();
  checkBackgroundCadenceBaseline();
  checkSupervisorWindowObservationBaseline();
  checkSettingsOnlyObservationBaseline();

  if (failures.length > 0) {
    console.error("[xt-sidebar-smooth-guard] failed");
    for (const failure of failures) {
      console.error(`- ${failure}`);
    }
    process.exit(1);
  }

  console.log("[xt-sidebar-smooth-guard] passed");
  for (const message of notes) {
    console.log(`- ${message}`);
  }
}

main();
