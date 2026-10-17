// Trains the currency reader's classifier with Create ML and measures it.
//
// usage: swift train_classifier.swift <dataset dir with train/ and test/> <output dir>
//
// The measurement is the one that matters to someone who cannot check the
// answer: on photos from capture sessions the model never saw, how often it
// names the right note, how often it stays silent, and — the number that must
// stay near zero — how often it names a wrong note with confidence.

import CoreML
import CreateML
import Foundation
import Vision

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("usage: train_classifier.swift <dataset> <output>")
    exit(2)
}
let dataset = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let started = Date()
var parameters = MLImageClassifier.ModelParameters()
parameters.featureExtractor = .scenePrint(revision: 2)
parameters.maxIterations = 100
parameters.validation = .split(strategy: .automatic)
// The training images are already augmented (composites, lighting, blur); a
// little more exposure and noise variation costs little.
parameters.augmentationOptions = [.exposure, .noise]

let classifier = try MLImageClassifier(
    trainingData: .labeledDirectories(at: dataset.appendingPathComponent("train")),
    parameters: parameters)
print("training accuracy: \(1 - classifier.trainingMetrics.classificationError)")
print("validation accuracy: \(1 - classifier.validationMetrics.classificationError)")

let modelURL = output.appendingPathComponent("RiyalClassifier.mlmodel")
let metadata = MLModelMetadata(
    author: "Basir",
    shortDescription: "Saudi riyal banknotes (1, 5, 10, 20, 50, 100, 200, 500) and \"none\".",
    license: "Trained on the Saudi Currency Dataset (Maruf, Basuhail, Adil; King Abdulaziz University; CC BY 4.0) and on CC BY / CC BY-SA banknote images from Numista listed in tools/currency/references.json.",
    version: "2")
try classifier.write(to: modelURL, metadata: metadata)

// MARK: Measuring on unseen sessions, the way the app decides

let compiled = try MLModel.compileModel(at: modelURL)
let model = try VNCoreMLModel(for: MLModel(contentsOf: compiled))
let threshold: Float = 0.85
struct Tally: Codable {
    var total = 0, correct = 0, confidentCorrect = 0, confidentWrong = 0, silent = 0
}
func ratio(_ a: Int, _ b: Int) -> Double { b == 0 ? 0 : (Double(a) / Double(b) * 10000).rounded() / 10000 }

/// Measures one test folder. Notes and "none" are reported apart: for a note
/// the number that matters is a confident wrong value; for "none", any value.
func measure(_ testRoot: URL) throws -> [String: Any] {
    var tallies: [String: Tally] = [:]
    var confusions: [String: Int] = [:]
    for label in try FileManager.default.contentsOfDirectory(atPath: testRoot.path).sorted() {
        let folder = testRoot.appendingPathComponent(label)
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { continue }
        var tally = Tally()
        for file in files where file.hasSuffix(".jpg") {
            let request = VNCoreMLRequest(model: model)
            request.imageCropAndScaleOption = .centerCrop
            try VNImageRequestHandler(url: folder.appendingPathComponent(file)).perform([request])
            guard let best = (request.results as? [VNClassificationObservation])?.first else { continue }
            tally.total += 1
            let right = best.identifier == label
            if right { tally.correct += 1 } else { confusions["\(label)→\(best.identifier)", default: 0] += 1 }
            if best.confidence >= threshold {
                // Naming "none" confidently is silence, not an error.
                if right { tally.confidentCorrect += 1 } else if best.identifier != "none" { tally.confidentWrong += 1 }
                else { tally.silent += 1 }
            } else {
                tally.silent += 1
            }
        }
        tallies[label] = tally
    }
    let notes = tallies.filter { $0.key != "none" }.values.reduce(into: Tally()) {
        $0.total += $1.total; $0.correct += $1.correct; $0.confidentCorrect += $1.confidentCorrect
        $0.confidentWrong += $1.confidentWrong; $0.silent += $1.silent
    }
    let none = tallies["none"] ?? Tally()
    return [
        "note_images": notes.total,
        "note_accuracy_top1": ratio(notes.correct, notes.total),
        "note_confident_correct": ratio(notes.confidentCorrect, notes.total),
        "note_confident_wrong": ratio(notes.confidentWrong, notes.total),
        "note_silent": ratio(notes.silent, notes.total),
        "none_images": none.total,
        "none_named_a_note": ratio(none.confidentWrong, none.total),
        "confusions": confusions,
        "per_label": tallies.mapValues {
            ["images": $0.total, "accuracy": ratio($0.correct, $0.total),
             "confident_correct": ratio($0.confidentCorrect, $0.total),
             "confident_wrong": ratio($0.confidentWrong, $0.total), "silent": ratio($0.silent, $0.total)]
        },
    ]
}

var report: [String: Any] = [
    "threshold": threshold,
    "seconds": Int(Date().timeIntervalSince(started)),
    "training_accuracy": 1 - classifier.trainingMetrics.classificationError,
    "validation_accuracy": 1 - classifier.validationMetrics.classificationError,
]
for folder in try FileManager.default.contentsOfDirectory(atPath: dataset.path).sorted() where folder.hasPrefix("test") {
    report[folder] = try measure(dataset.appendingPathComponent(folder))
    print(folder, "measured")
}
let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
try data.write(to: output.appendingPathComponent("metrics.json"))
print(String(data: data, encoding: .utf8)!)
