#!/usr/bin/env python3
"""Strict deterministic checks that do not require Xcode or an iOS SDK."""
from __future__ import annotations
import json
import plistlib
import subprocess
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    yaml = None

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "ios" / "Basir"
SHARE = ROOT / "ios" / "ShareExtension"
TESTS = ROOT / "ios" / "BasirTests"
errors: list[str] = []


def require(condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def run(command: list[str], cwd: Path = ROOT, timeout: int = 180) -> subprocess.CompletedProcess[str] | None:
    try:
        return subprocess.run(command, cwd=cwd, text=True, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, timeout=timeout)
    except (FileNotFoundError, subprocess.TimeoutExpired) as exc:
        errors.append(f"Could not run {' '.join(command)}: {exc}")
        return None


swift_files = sorted(APP.rglob("*.swift")) + sorted(SHARE.rglob("*.swift")) + sorted(TESTS.rglob("*.swift"))
combined = "\n".join(read(path) for path in swift_files)
production = "\n".join(read(path) for path in swift_files if TESTS not in path.parents)

# Crash and transport invariants.
require("try!" not in production, "Force-try remains in production Swift sources")
require("fatalError(" not in production, "fatalError remains in production Swift sources")
require("URLSession.shared" not in production, "A networking path bypasses NetworkTransport")
require("?key=" not in production, "A Gemini API key is still placed in a URL query")
require('"responseFormat"' in production, "Current structured-output responseFormat is missing")
require("gemini-2.0" not in production and "gemini-2.5" not in production,
        "Deprecated Gemini 2.x model IDs remain in production code")

settings = read(APP / "Storage" / "BasirSettings.swift")
policy_source = read(APP / "Networking" / "AITaskPolicy.swift")
require("gemini-3.5-flash" in policy_source, "Stable balanced Gemini model is missing")
require("gemini-3.1-flash-lite" in policy_source, "Fast Gemini fallback is missing")
require("gemini-3.1-pro-preview" in policy_source, "Best-quality Gemini route is missing")
require("modelsFor(task:" in settings, "Task model candidate routing is missing")
require("CaseIterable" in policy_source and "AITaskPolicyCatalog" in policy_source,
        "Central per-task policy catalogue is missing")
require(policy_source.count("case ") >= 23, "Task policy catalogue does not cover all expected tasks")
for marker in ["thinkingLevel", "temperature", "maxOutputTokens", "timeoutSeconds",
               "attemptsPerModel", "repairEnabled", "preserveCriticalTokens",
               "validationProfile", "minimumUsefulCharacters"]:
    require(marker in policy_source, f"AI task policy field is missing: {marker}")

client = read(APP / "Networking" / "GeminiClient.swift")
require('forHTTPHeaderField: "x-goog-api-key"' in client, "Gemini key header is missing")
require('"responseFormat"' in client and '"mimeType"' in client and '"schema"' in client,
        "Current structured-output responseFormat is not configured")
require('config["responseMimeType"]' not in client and 'config["responseJsonSchema"]' not in client,
        "Legacy direct structured-output fields remain")
require('"thinkingConfig"' in client and '"thinkingLevel"' in client,
        "Per-task thinking level is not sent to Gemini")
require('config["temperature"]' in client, "Per-task temperature is not sent to Gemini")
require("usageMetadata" in client and "modelVersion" in client,
        "Executed model or usage metadata is not parsed")
require("!settings.privacyMode" in client,
        "Direct AI metrics are not disabled by privacy mode")
require('Basir-iOS/4.4.1' in client, "Gemini user agent was not updated to 4.4.1")
require('"resumable"' in client and '"upload, finalize"' in client,
        "Official two-stage resumable Files API flow is missing")
require("shouldTryNextModel" in client, "Model fallback classification is missing")
require("AIResponseValidator.validate" in client, "Direct AI responses bypass validation")
require("maxUserMessageBytes" in client and "maxSystemInstructionBytes" in client,
        "Direct Gemini requests lack bounded text envelopes")
require("validateTextEnvelope" in client, "Gemini request text limits are not enforced")

proxy = read(APP / "Networking" / "ProxyAiProvider.swift")
require("contract_version" in proxy and "model_candidates" in proxy,
        "Proxy request contract lacks versioning or model candidates")
for marker in ["thinking_level", "temperature", "max_output_tokens", "timeout_seconds",
               "validation_profile", "preserve_critical_tokens", "repair_enabled",
               "response_format", "untrusted_input", "untrusted_message", "system_instruction"]:
    require(marker in proxy, f"Proxy policy parity field is missing: {marker}")
require("basir-ai-2026.06-v5" in policy_source, "Proxy/direct AI contract is not v5")
require("AIResponseValidator.validate" in proxy, "Proxy AI responses bypass validation")
require("!settings.privacyMode" in proxy,
        "Proxy AI metrics are not disabled by privacy mode")
require("maxSystemInstructionBytes" in proxy and "maxUserMessageBytes" in proxy,
        "Proxy requests lack matching text and instruction limits")


# Full 4.4 AI policy, schema, validation, repair and privacy telemetry gates.
for relative in [
    "Networking/AITaskPolicy.swift",
    "Networking/AIResponseSchemas.swift",
    "Networking/AIEngineMetrics.swift",
    "Networking/AIResponseValidator.swift",
]:
    require((APP / relative).exists(), f"4.4 AI engine file is missing: {relative}")
prompts = read(APP / "Networking" / "GeminiPrompts.swift")
require("UUID().uuidString" in prompts and "BASIR_DATA_" in prompts,
        "Per-request randomized untrusted-data boundaries are missing")
require("QUALITY REPAIR PASS" in prompts, "Repair-pass prompt contract is missing")
require("sourceText:" not in prompts, "Document source text can still be embedded in a trusted prompt")
validator = read(APP / "Networking" / "AIResponseValidator.swift")
for marker in ["rejectExplosiveRepetition", "rejectUnwantedPreamble",
               "criticalTokens", "validateStructuredObject", "validateVisualSafety"]:
    require(marker in validator, f"AI response quality gate is missing: {marker}")
metrics = read(APP / "Networking" / "AIEngineMetrics.swift")
for marker in ["executedModel", "durationMilliseconds", "thoughtsTokens",
               "promptTokens", "totalTokens", "maximumRecords"]:
    require(marker in metrics, f"Private local AI metrics field is missing: {marker}")
for forbidden_field in ["let input: String", "let prompt: String", "let response: String",
                        "let document: String", "let imageData: Data"]:
    require(forbidden_field not in metrics,
            f"AI metrics appears to persist private content: {forbidden_field}")

# Document and memory invariants.
reader = read(APP / "Documents" / "PdfReader.swift")
converter = read(APP / "Helpers" / "StructuredDocConverter.swift")
require("actor PdfPageSnapshotter" in reader, "PDF rendering is not actor-isolated")
require("await snapshotter.snapshot" in converter, "Structured conversion still renders on the UI path")
require("pagesPerBatch = 1" in reader, "PDF conversion is not page-isolated")
require("withRetry" not in converter, "Nested conversion retry loop remains")
require("pageImage: imageData" in converter, "Scanned-page preservation fallback is missing")

zip_reader = read(APP / "Documents" / "ZipReader.swift")
for marker in ["maximumEntryCount", "maximumExpandedBytes", "maximumCompressionRatio", "duplicateEntry"]:
    require(marker in zip_reader, f"ZIP hardening marker is missing: {marker}")

share = read(SHARE / "ShareViewController.swift")
require("maximumSharedFileBytes" in share, "Share extension lacks a pre-copy file size limit")
require("cancelRequest" in share and "cancelButton.isEnabled = true" in share,
        "Share extension cannot be cancelled while processing")
require("openMainAppOnMain" in share, "Share extension URL opening is not marshalled to the main thread")

# Runtime/concurrency hardening invariants.
location = read(APP / "Location" / "LocationService.swift")
require("finishLocationRequest" in location and "oneShotTimeoutTask" in location,
        "One-shot location requests can still leak a continuation or ignore timeout")
speech = read(APP / "Speech" / "SpeechRecognizer.swift")
require("guard !Task.isCancelled else" in location,
        "Location continuations do not close the pre-cancellation race")
require("activeSessionID" in speech and "tapInstalled" in speech,
        "Speech recognition lacks stale-callback or audio-tap protection")
live = read(APP / "Camera" / "LiveSceneGuidanceController.swift")
require("captureInFlight" in live and "ImagePreprocessor.jpeg" in live,
        "Live camera lacks capture serialization or bounded image preprocessing")
document_view = read(APP / "Views" / "DocumentConvertView.swift")
require("isPreparingFile" in document_view and "Task.detached" in document_view,
        "Document import/export still blocks the main actor")
document_text = read(APP / "Helpers" / "DocumentText.swift")
require("supportedExtensions" in document_text and "DocumentType.rtf" in document_text,
        "Document type validation or RTF extraction is missing")
require("maximumDocumentBytes" in document_text and "maximumPlainTextBytes" in document_text,
        "Document extraction lacks explicit file-size envelopes")
require("async throws -> String" in document_text and "DocumentTextError.tooLarge" in document_text,
        "Document import errors are still collapsed into a false no-text result")
require("} catch {\n            } catch {" not in document_text,
        "Duplicate empty catch block remains in document OCR")
archive = read(APP / "Memory" / "ArchiveStore.swift")
require("maximumArchiveBytes" in archive and ".completeFileProtection" in archive,
        "Local archive lacks size bounds or atomic protected writes")

# Existing accessibility and prompt-injection gates.
require("UNTRUSTED DOCUMENT DATA" in read(APP / "Networking" / "GeminiPrompts.swift"),
        "Document prompt-injection guard is missing")
qa_view = read(APP / "Views" / "DocumentQAView.swift")
require("groundedQuestionInput" in qa_view,
        "Document Q&A does not keep source context in the data channel")
require("DocumentContextSelector.select" in qa_view and "prefix(12_000)" not in qa_view,
        "Document Q&A still searches only a fixed prefix instead of the full local document")
require((APP / "Helpers" / "DocumentContextSelector.swift").exists(),
        "Full-document context selector is missing")
require((TESTS / "DocumentContextSelectorTests.swift").exists(),
        "Document context retrieval tests are missing")
require((APP / "Design" / "BasirDesignSystem.swift").exists(), "Shared design system is missing")
require("BasirScreen" in "\n".join(read(p) for p in sorted((APP / "Views").glob("*.swift"))),
        "Accessible shared screen component is not used")

# Version and plist integrity.
for path, label in [(APP / "Info.plist", "app"), (SHARE / "Info.plist", "share extension")]:
    try:
        with path.open("rb") as handle:
            plist = plistlib.load(handle)
        require(plist.get("CFBundleShortVersionString") == "4.4.1", f"{label} marketing version is not 4.4.1")
        require(plist.get("CFBundleVersion") == "64", f"{label} build version is not 64")
        if label == "app":
            require(plist.get("NSAppTransportSecurity", {}).get("NSAllowsArbitraryLoads") is False,
                    "App Transport Security is not strict")
        else:
            extension = plist.get("NSExtension", {})
            require("NSExtensionMainStoryboard" not in extension,
                    "Share extension still depends on a storyboard")
            require(extension.get("NSExtensionPrincipalClass") ==
                    "$(PRODUCT_MODULE_NAME).ShareViewController",
                    "Share extension principal class is incorrect")
    except Exception as exc:
        errors.append(f"Could not parse {path}: {exc}")

# Apple privacy manifest and required-reason API declarations.
privacy_manifest_path = APP / "PrivacyInfo.xcprivacy"
try:
    with privacy_manifest_path.open("rb") as handle:
        privacy_manifest = plistlib.load(handle)
    require(privacy_manifest.get("NSPrivacyTracking") is False,
            "Privacy manifest unexpectedly enables tracking")
    accessed = {
        item.get("NSPrivacyAccessedAPIType"): set(item.get("NSPrivacyAccessedAPITypeReasons", []))
        for item in privacy_manifest.get("NSPrivacyAccessedAPITypes", [])
    }
    require("CA92.1" in accessed.get("NSPrivacyAccessedAPICategoryUserDefaults", set()),
            "Privacy manifest lacks the UserDefaults required reason")
    require("C617.1" in accessed.get("NSPrivacyAccessedAPICategoryFileTimestamp", set()),
            "Privacy manifest lacks the file-timestamp required reason")
    collected = {
        item.get("NSPrivacyCollectedDataType")
        for item in privacy_manifest.get("NSPrivacyCollectedDataTypes", [])
    }
    for expected_type in {
        "NSPrivacyCollectedDataTypeOtherUserContent",
        "NSPrivacyCollectedDataTypePhotosorVideos",
        "NSPrivacyCollectedDataTypePreciseLocation",
    }:
        require(expected_type in collected,
                f"Privacy manifest lacks collected-data disclosure: {expected_type}")
except Exception as exc:
    errors.append(f"Could not parse privacy manifest: {exc}")

project_yml = read(ROOT / "ios" / "project.yml")
require("BasirTests:" in project_yml, "Unit-test target is missing")
require("- target: BasirShare" in project_yml, "Host app does not depend on the share extension")

# YAML syntax.
if yaml is None:
    errors.append("PyYAML is unavailable; CI YAML could not be parsed")
else:
    for path in [ROOT / "ios" / "project.yml", ROOT / "codemagic.yaml", ROOT / ".github" / "workflows" / "swift.yml"]:
        try:
            yaml.safe_load(read(path))
        except Exception as exc:
            errors.append(f"Invalid YAML in {path.relative_to(ROOT)}: {exc}")

test_sources = "\n".join(read(path) for path in sorted((ROOT / "ios" / "BasirTests").glob("*.swift")))
require("testZipEntryCountLimitIsEnforcedBeforeDirectoryWalk" in test_sources,
        "ZIP entry-count regression test is missing")
require("testZipReaderInflatesAStandardDeflatedEntry" in test_sources,
        "Standard DEFLATE ZIP compatibility test is missing")
require("testApiKeyIsAHeaderAndNeverInTheURL" in test_sources,
        "API-key transport regression test is missing")
for test_name in [
    "testCatalogContainsExactlyTwentyThreeDistinctTasks",
    "testEveryTaskHasACompleteBoundedPolicy",
    "testAllTaskPolicySignaturesMatchV44Contract",
    "testRandomDataBoundariesDifferAndNeverEnterSystemPrompt",
    "testProxyContractMatchesDirectPolicyAndSeparatesUntrustedInput",
    "testUsageAndExecutedModelAreParsed",
    "testStructuredTaskSchemasExistAndAreSemanticallyChecked",
    "testMetricEncodingContainsNoPromptOrUserContentFields",
]:
    require(test_name in test_sources, f"4.4 AI regression test is missing: {test_name}")

# Swift parser catches malformed declarations even without the iOS SDK.
parsed = run(["swiftc", "-parse", *map(str, swift_files)], timeout=180)
if parsed is not None:
    require(parsed.returncode == 0, "Swift parser failed:\n" + parsed.stderr[-6000:])

# Simulator selector is tested with mixed watchOS/iOS input.
fixture = {
    "devices": {
        "com.apple.CoreSimulator.SimRuntime.watchOS-11-0": [
            {"name": "Apple Watch", "udid": "WATCH", "isAvailable": True}
        ],
        "com.apple.CoreSimulator.SimRuntime.iOS-17-5": [
            {"name": "iPhone 15", "udid": "OLD", "isAvailable": True}
        ],
        "com.apple.CoreSimulator.SimRuntime.iOS-18-2": [
            {"name": "iPhone 16 Pro", "udid": "NEW", "isAvailable": True}
        ],
    }
}
try:
    checked = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "select_ios_simulator.py")],
        input=json.dumps(fixture), text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        cwd=ROOT, timeout=20
    )
    require(checked.returncode == 0 and checked.stdout.strip() == "NEW",
            "Simulator selector did not choose the newest available iPhone")
except Exception as exc:
    errors.append(f"Simulator selector test failed: {exc}")

# Compile and execute the platform-independent AI/network and DOCX cores.
portable = run([sys.executable, str(ROOT / "scripts" / "run_portable_core_checks.py")], timeout=240)
if portable is not None:
    require(portable.returncode == 0,
            "Portable executable checks failed:\n" + portable.stdout + portable.stderr)

# Repository whitespace and patch validity.
git_check = run(["git", "diff", "--check"])
if git_check is not None:
    require(git_check.returncode == 0, "git diff --check failed:\n" + git_check.stdout + git_check.stderr)

if errors:
    print("FAILED")
    for item in errors:
        print(f"- {item}")
    raise SystemExit(1)
print(f"PASS: {len(swift_files)} Swift files and strict repository invariants verified")
