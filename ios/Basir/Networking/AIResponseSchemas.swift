import Foundation

enum AIResponseSchemas {
    static func schema(for task: TaskKind) -> [String: Any]? {
        switch task {
        case .describeImage: return imageDescription
        case .altText: return altText
        case .screenshot: return screenshot
        case .currencyOrReceipt: return currencyOrReceipt
        case .medicalText: return medicalDocument
        case .legalText: return legalDocument
        case .tableRead: return table
        case .studyCards: return studyCards
        case .liveScene: return liveScene
        case .walkingSnapshot: return walkingSnapshot
        case .ocr: return ocr
        default: return nil
        }
    }

    static func promptDirective(for task: TaskKind) -> String? {
        switch task {
        case .describeImage:
            return "Return JSON with summary, details, visible_text, and uncertainties. Every array item must be a complete useful sentence."
        case .altText:
            return "Return JSON with alt_text, key_details, visible_text, and uncertainties. alt_text must stand alone for a screen reader."
        case .screenshot:
            return "Return JSON with screen_title, elements in reading order, messages, errors, and next_actions. Quote visible labels and values exactly."
        case .currencyOrReceipt:
            return "Return JSON with kind, currency, denomination, total, merchant, date, line_items, visible_text, uncertainties, and authenticity_note. Never claim authenticity."
        case .medicalText:
            return "Return JSON with document_type, patient_details, medications, findings, dates, printed_warnings, unreadable, and safety_note. Transcribe printed medical facts without diagnosing."
        case .legalText:
            return "Return JSON with document_type, parties, obligations, dates, amounts, decisive_quotes, signatures, uncertainties, and legal_note. Do not give a verdict or advice."
        case .tableRead:
            return "Return JSON with title, columns, rows, and unreadable_cells. rows must be rectangular and preserve every visible row and blank cell."
        case .studyCards:
            return "Return JSON with cards. Each card must contain a faithful question and answer, and may contain an optional source_reference."
        case .liveScene:
            return "Return only the live-scene JSON object matching the schema."
        case .walkingSnapshot:
            return "Return JSON with immediate_obstacle, path, notable_objects, visible_text, uncertainty, and safety_reminder. Never claim the route is safe."
        case .ocr:
            return "Return JSON with text, languages, and unreadable_segments. Preserve line order and every legible character; do not summarize."
        default:
            return nil
        }
    }


    static let documentRun = object([
        "text": ["type": "STRING"],
        "bold": ["type": "BOOLEAN"],
        "italic": ["type": "BOOLEAN"],
        "underline": ["type": "BOOLEAN"],
        "strike": ["type": "BOOLEAN"],
        "highlight": ["type": "BOOLEAN"],
        "superscript": ["type": "BOOLEAN"],
        "subscript": ["type": "BOOLEAN"],
        "font_size_pt": ["type": "NUMBER", "minimum": 5, "maximum": 96],
        "color_hex": ["type": "STRING"],
        "url": ["type": "STRING"],
        "direction": ["type": "STRING", "enum": ["auto", "rtl", "ltr"]]
    ], required: ["text"])

    static let documentPage = object([
        "sections": ["type": "ARRAY", "items": object([
            "type": ["type": "STRING", "enum": ["heading", "paragraph", "list_item", "table", "image_description"]],
            "level": ["type": "INTEGER"],
            "ordered": ["type": "BOOLEAN"],
            "text": ["type": "STRING"],
            "runs": ["type": "ARRAY", "items": documentRun, "maxItems": 1_000],
            "caption": ["type": "STRING"],
            "row_header": ["type": "BOOLEAN"],
            "cells": ["type": "ARRAY", "minItems": 1, "maxItems": 500, "items": ["type": "ARRAY", "minItems": 1, "maxItems": 50, "items": ["type": "STRING"]]],
            "description": ["type": "STRING"]
        ], required: ["type"]), "minItems": 1, "maxItems": 2_000]
    ], required: ["sections"])

    private static let stringArray: [String: Any] = ["type": "ARRAY", "items": ["type": "STRING"], "maxItems": 1_000]
    private static func object(_ properties: [String: Any], required: [String]) -> [String: Any] {
        ["type": "OBJECT", "properties": properties, "required": required, "additionalProperties": false]
    }

    static let imageDescription = object([
        "summary": ["type": "STRING"],
        "details": stringArray,
        "visible_text": stringArray,
        "uncertainties": stringArray
    ], required: ["summary", "details", "visible_text", "uncertainties"])

    static let altText = object([
        "alt_text": ["type": "STRING"],
        "key_details": stringArray,
        "visible_text": stringArray,
        "uncertainties": stringArray
    ], required: ["alt_text", "key_details", "visible_text", "uncertainties"])

    static let screenshot = object([
        "screen_title": ["type": "STRING"],
        "elements": ["type": "ARRAY", "maxItems": 500, "items": object([
            "role": ["type": "STRING"],
            "label": ["type": "STRING"],
            "value": ["type": "STRING"],
            "state": ["type": "STRING"]
        ], required: ["role", "label", "value", "state"])],
        "messages": stringArray,
        "errors": stringArray,
        "next_actions": stringArray
    ], required: ["screen_title", "elements", "messages", "errors", "next_actions"])

    static let currencyOrReceipt = object([
        "kind": ["type": "STRING", "enum": ["banknote", "coin", "receipt", "invoice", "unknown"]],
        "currency": ["type": "STRING"],
        "denomination": ["type": "STRING"],
        "total": ["type": "STRING"],
        "merchant": ["type": "STRING"],
        "date": ["type": "STRING"],
        "line_items": stringArray,
        "visible_text": stringArray,
        "uncertainties": stringArray,
        "authenticity_note": ["type": "STRING"]
    ], required: ["kind", "currency", "denomination", "total", "merchant", "date", "line_items", "visible_text", "uncertainties", "authenticity_note"])

    static let medicalDocument = object([
        "document_type": ["type": "STRING"],
        "patient_details": ["type": "ARRAY", "items": keyValue],
        "medications": ["type": "ARRAY", "maxItems": 500, "items": object([
            "name": ["type": "STRING"],
            "dose": ["type": "STRING"],
            "unit": ["type": "STRING"],
            "frequency": ["type": "STRING"],
            "printed_instructions": ["type": "STRING"]
        ], required: ["name", "dose", "unit", "frequency", "printed_instructions"])],
        "findings": stringArray,
        "dates": stringArray,
        "printed_warnings": stringArray,
        "unreadable": stringArray,
        "safety_note": ["type": "STRING"]
    ], required: ["document_type", "patient_details", "medications", "findings", "dates", "printed_warnings", "unreadable", "safety_note"])

    static let legalDocument = object([
        "document_type": ["type": "STRING"],
        "parties": stringArray,
        "obligations": ["type": "ARRAY", "maxItems": 1_000, "items": object([
            "party": ["type": "STRING"],
            "obligation": ["type": "STRING"],
            "deadline": ["type": "STRING"],
            "amount": ["type": "STRING"]
        ], required: ["party", "obligation", "deadline", "amount"])],
        "dates": stringArray,
        "amounts": stringArray,
        "decisive_quotes": stringArray,
        "signatures": stringArray,
        "uncertainties": stringArray,
        "legal_note": ["type": "STRING"]
    ], required: ["document_type", "parties", "obligations", "dates", "amounts", "decisive_quotes", "signatures", "uncertainties", "legal_note"])

    static let table = object([
        "title": ["type": "STRING"],
        "columns": ["type": "ARRAY", "minItems": 1, "maxItems": 50, "items": ["type": "STRING"]],
        "rows": ["type": "ARRAY", "minItems": 1, "maxItems": 500, "items": ["type": "ARRAY", "minItems": 1, "maxItems": 50, "items": ["type": "STRING"]]],
        "unreadable_cells": stringArray
    ], required: ["title", "columns", "rows", "unreadable_cells"])

    static let studyCards = object([
        "cards": ["type": "ARRAY", "minItems": 1, "maxItems": 500, "items": object([
            "question": ["type": "STRING"],
            "answer": ["type": "STRING"],
            "source_reference": ["type": "STRING"]
        ], required: ["question", "answer", "source_reference"])]
    ], required: ["cards"])

    static let liveScene = object([
        "hazard": object([
            "level": ["type": "STRING", "enum": ["stop", "caution", "none"]],
            "description": ["type": "STRING"]
        ], required: ["level", "description"]),
        "path": ["type": "STRING"],
        "scene": ["type": "STRING"]
    ], required: ["hazard", "path", "scene"])

    static let walkingSnapshot = object([
        "immediate_obstacle": ["type": "STRING"],
        "path": ["type": "STRING"],
        "notable_objects": stringArray,
        "visible_text": stringArray,
        "uncertainty": ["type": "STRING"],
        "safety_reminder": ["type": "STRING"]
    ], required: ["immediate_obstacle", "path", "notable_objects", "visible_text", "uncertainty", "safety_reminder"])

    static let ocr = object([
        "text": ["type": "STRING"],
        "languages": stringArray,
        "unreadable_segments": stringArray
    ], required: ["text", "languages", "unreadable_segments"])

    private static let keyValue = object([
        "key": ["type": "STRING"],
        "value": ["type": "STRING"]
    ], required: ["key", "value"])
}
