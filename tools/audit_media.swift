import Foundation
import ImageIO
import Vision

private struct Finding {
    let file: String
    let frame: Int
    let pattern: String
    let evidence: String
}

private let patterns: [(String, NSRegularExpression)] = [
    ("absolute user path", try! NSRegularExpression(pattern: #"(?i)/Users/"#)),
    ("email address", try! NSRegularExpression(pattern: #"(?i)[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#)),
    ("IPv4 address", try! NSRegularExpression(pattern: #"(?<!\d)(?:\d{1,3}\.){3}\d{1,3}(?!\d)"#)),
    ("Chinese mobile number", try! NSRegularExpression(pattern: #"(?<!\d)1[3-9]\d{9}(?!\d)"#)),
    ("local username", try! NSRegularExpression(pattern: #"(?i)feiver"#)),
    ("known private business term", try! NSRegularExpression(pattern: #"良固|客户资料"#)),
]

private func matches(_ text: String) -> [(String, String)] {
    let range = NSRange(text.startIndex..., in: text)
    return patterns.compactMap { name, regex in
        guard let match = regex.firstMatch(in: text, range: range),
              let swiftRange = Range(match.range, in: text) else { return nil }
        return (name, String(text[swiftRange]))
    }
}

private func recognizeText(in image: CGImage) throws -> [String] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    request.recognitionLanguages = ["en-US", "zh-Hans"]
    try VNImageRequestHandler(cgImage: image).perform([request])
    return request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
}

private func audit(_ url: URL) throws -> [Finding] {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        throw NSError(domain: "MediaAudit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot read \(url.path)"])
    }

    var findings: [Finding] = []
    let count = CGImageSourceGetCount(source)
    for frame in 0..<count {
        guard let image = CGImageSourceCreateImageAtIndex(source, frame, nil) else { continue }
        let recognized = try recognizeText(in: image).joined(separator: " | ")
        for (pattern, evidence) in matches(recognized) {
            findings.append(Finding(file: url.lastPathComponent, frame: frame, pattern: pattern, evidence: evidence))
        }

        if let properties = CGImageSourceCopyPropertiesAtIndex(source, frame, nil) as? [String: Any] {
            let metadata = String(describing: properties)
            for (pattern, evidence) in matches(metadata) {
                findings.append(Finding(file: url.lastPathComponent, frame: frame, pattern: "metadata: \(pattern)", evidence: evidence))
            }
        }

        if frame == 0 || frame == count - 1 {
            print("OCR \(url.lastPathComponent) frame \(frame): \(recognized)")
        }
    }
    print("PASS inspected \(url.lastPathComponent): \(count) image frame(s)")
    return findings
}

let paths = CommandLine.arguments.dropFirst()
guard !paths.isEmpty else {
    fputs("usage: audit-media <image-or-gif> [...]\n", stderr)
    exit(64)
}

do {
    let findings = try paths.flatMap { try audit(URL(fileURLWithPath: $0)) }
    if findings.isEmpty {
        print("PASS no sensitive text or metadata patterns detected")
        exit(0)
    }
    for finding in findings {
        fputs("FAIL \(finding.file) frame \(finding.frame): \(finding.pattern) [\(finding.evidence)]\n", stderr)
    }
    exit(1)
} catch {
    fputs("FAIL media audit: \(error)\n", stderr)
    exit(1)
}
