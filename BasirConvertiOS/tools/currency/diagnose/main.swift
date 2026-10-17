// Measures the currency reader the way the camera uses it.
//
// usage: diagnose <tests dir from make_field_tests.py> <RiyalClassifier.mlmodel> <report.json>
// built with: swiftc -O diagnose/main.swift ../../BasirConvert/Models/RiyalNote.swift
//
// Two readers are measured on the same frames:
// - the classifier, exactly as the app runs it (centre square of a portrait frame);
// - the printed number, read by on-device text recognition, in each of the four
//   orientations a note can be held, with and without ignoring text cut by the
//   frame's edge.
// For each: how often it names the right note, a wrong note, or stays silent.

import CoreML
import Foundation
import ImageIO
import Vision

let arguments = CommandLine.arguments
guard arguments.count == 4 else { print("usage: diagnose <tests> <model> <report>"); exit(2) }
let root = URL(fileURLWithPath: arguments[1])
let compiled = try MLModel.compileModel(at: URL(fileURLWithPath: arguments[2]))
let classifier = try VNCoreMLModel(for: MLModel(contentsOf: compiled))
let supported = (try? VNRecognizeTextRequest().supportedRecognitionLanguages()) ?? []
let languages = ["ar-SA", "en-US"].filter(supported.contains)
print("text languages supported:", supported)

func load(_ url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

func classify(_ image: CGImage) -> (String, Double) {
    let request = VNCoreMLRequest(model: classifier)
    request.imageCropAndScaleOption = .centerCrop
    try? VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
    guard let best = (request.results as? [VNClassificationObservation])?.first else { return ("", 0) }
    return (best.identifier, Double(best.confidence))
}

struct Line { var text: String; var box: CGRect }

func read(_ image: CGImage, _ orientation: CGImagePropertyOrientation) -> [Line] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    request.recognitionLanguages = languages
    try? VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])
    return (request.results ?? []).compactMap { observation in
        observation.topCandidates(1).first.map { Line(text: $0.string, box: observation.boundingBox) }
    }
}

func inside(_ box: CGRect) -> Bool {
    box.minX > 0.015 && box.minY > 0.015 && box.maxX < 0.985 && box.maxY < 0.985
}

enum Outcome: String { case correct, wrong, silent }

func judge(_ values: Set<RiyalNote>, _ label: String) -> Outcome {
    guard values.count == 1, let value = values.first else { return .silent }
    return value.label == label ? .correct : .wrong
}

struct Tally: Codable {
    var images = 0, correct = 0, wrong = 0, silent = 0
    mutating func add(_ outcome: Outcome) {
        images += 1
        switch outcome { case .correct: correct += 1; case .wrong: wrong += 1; case .silent: silent += 1 }
    }
}

var tallies: [String: [String: Tally]] = [:]   // set/measure -> label -> tally
var wrongExamples: [String: [String]] = [:]
var textMilliseconds: [Double] = []

func record(_ measure: String, _ label: String, _ outcome: Outcome, _ file: String, _ detail: String = "") {
    tallies[measure, default: [:]][label, default: Tally()].add(outcome)
    if outcome == .wrong, wrongExamples[measure, default: []].count < 25 {
        wrongExamples[measure, default: []].append("\(label)/\(file): \(detail)")
    }
}

let orientations: [(String, CGImagePropertyOrientation)] = [("up", .up), ("down", .down), ("left", .left), ("right", .right)]

for set in ["field", "photos"] {
    let folder = root.appendingPathComponent(set)
    guard let labels = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { continue }
    for label in labels.sorted() {
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent(label).path)) ?? [])
            .filter { $0.hasSuffix(".jpg") }.sorted()
        for file in files {
            guard let image = load(folder.appendingPathComponent(label).appendingPathComponent(file)) else { continue }

            // The classifier, as in the app: speaks at 0.85 or more; "none" is silence.
            let (top, confidence) = classify(image)
            let modelOutcome: Outcome = confidence < 0.85 || top == "none" ? .silent : (top == label ? .correct : .wrong)
            record("\(set)/model", label, modelOutcome, file, "\(top) \(String(format: "%.2f", confidence))")

            // The printed number, per orientation and combined.
            var any = Set<Outcome>(), anyEdge = Set<Outcome>()
            var upDown = Set<Outcome>()
            for (name, orientation) in orientations {
                let started = Date()
                let lines = read(image, orientation)
                textMilliseconds.append(Date().timeIntervalSince(started) * 1000)
                let all = PrintedValue.notes(in: lines.map(\.text))
                let kept = PrintedValue.notes(in: lines.filter { inside($0.box) }.map(\.text))
                let outcome = judge(all, label), edged = judge(kept, label)
                record("\(set)/text_\(name)", label, outcome, file, lines.map(\.text).joined(separator: " | "))
                any.insert(outcome); anyEdge.insert(edged)
                if name == "up" || name == "down" { upDown.insert(outcome) }
            }
            // Combined over several frames: wrong if any orientation names a wrong note.
            func combine(_ outcomes: Set<Outcome>) -> Outcome {
                outcomes.contains(.wrong) ? .wrong : outcomes.contains(.correct) ? .correct : .silent
            }
            record("\(set)/text_any4", label, combine(any), file)
            record("\(set)/text_any4_edge", label, combine(anyEdge), file)
            record("\(set)/text_updown", label, combine(upDown), file)
            // Both readers must agree.
            let both: Outcome = modelOutcome == .silent ? .silent
                : (combine(anyEdge) == .silent ? .silent : (modelOutcome == combine(anyEdge) ? modelOutcome : .silent))
            record("\(set)/model_and_text", label, both, file)
        }
        print(set, label, "done", tallies["\(set)/model"]?[label] ?? Tally())
    }
}

func summary(_ byLabel: [String: Tally]) -> [String: Any] {
    let notes = byLabel.filter { $0.key != "none" }.values.reduce(into: Tally()) {
        $0.images += $1.images; $0.correct += $1.correct; $0.wrong += $1.wrong; $0.silent += $1.silent
    }
    func ratio(_ a: Int, _ b: Int) -> Double { b == 0 ? 0 : (Double(a) / Double(b) * 1000).rounded() / 10 }
    var out: [String: Any] = [
        "notes_images": notes.images,
        "notes_correct_pct": ratio(notes.correct, notes.images),
        "notes_wrong_pct": ratio(notes.wrong, notes.images),
        "notes_silent_pct": ratio(notes.silent, notes.images),
        "per_label": byLabel.mapValues { ["n": $0.images, "correct": $0.correct, "wrong": $0.wrong, "silent": $0.silent] },
    ]
    if let none = byLabel["none"] { out["none_images"] = none.images; out["none_named_a_note_pct"] = ratio(none.wrong, none.images) }
    return out
}

let sortedMs = textMilliseconds.sorted()
let report: [String: Any] = [
    "text_languages_supported": supported,
    "text_languages_used": languages,
    "text_ms_median": sortedMs.isEmpty ? 0 : sortedMs[sortedMs.count / 2],
    "measures": tallies.mapValues(summary),
    "wrong_examples": wrongExamples,
]
let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
try data.write(to: URL(fileURLWithPath: arguments[3]))
print(String(data: data, encoding: .utf8)!)
