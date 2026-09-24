//
//  ChatAttachmentStore.swift
//  SpeechToType
//
//  Files attached to chat messages: imported into Application Support (images are
//  downscaled and re-encoded as JPEG, text is normalised to UTF-8) and read back when
//  a request is built.
//

import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// The app's own folder in Application Support (…/Application Support/<bundle id>).
nonisolated enum AppDataDirectory {
    static let url: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "SpeechToType", isDirectory: true)
    }()

    /// A subfolder of the app folder, created on first use
    static func subdirectory(_ name: String) -> URL {
        let directory = url.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

nonisolated enum ChatAttachmentError: LocalizedError {
    case unsupported(String)
    case tooLarge(String)
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let name):
            return String(format: String(localized: "chatAttachmentUnsupported %@"), name)
        case .tooLarge(let name):
            return String(format: String(localized: "chatAttachmentTooLarge %@"), name)
        case .unreadable(let name):
            return String(format: String(localized: "chatAttachmentUnreadable %@"), name)
        }
    }
}

nonisolated enum ChatAttachmentStore {
    static let maxAttachmentsPerMessage = 10
    /// Text files longer than this are cut off when they are sent to the model
    static let maxInlineTextCharacters = 100_000

    /// Longest image edge after import — plenty for vision models, keeps requests small
    private static let maxImageDimension = 2048
    private static let maxPDFBytes = 10 * 1024 * 1024
    private static let maxTextBytes = 2 * 1024 * 1024

    static var directory: URL { AppDataDirectory.subdirectory("ChatAttachments") }

    static func url(for attachment: ChatAttachment) -> URL {
        directory.appendingPathComponent(attachment.storedName)
    }

    // MARK: - Import

    /// Copies a file into the store. Blocking — call off the main thread.
    static func importFile(at sourceURL: URL) throws -> ChatAttachment {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        let fileName = sourceURL.lastPathComponent
        let values = try? sourceURL.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey, .isDirectoryKey])
        guard values?.isDirectory != true else { throw ChatAttachmentError.unsupported(fileName) }
        let type = values?.contentType ?? UTType(filenameExtension: sourceURL.pathExtension) ?? .data
        let size = values?.fileSize ?? 0

        if type.conforms(to: .image) {
            guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
                throw ChatAttachmentError.unreadable(fileName)
            }
            return try storeImage(from: source, fileName: fileName)
        }

        if type.conforms(to: .pdf) {
            guard size <= maxPDFBytes else { throw ChatAttachmentError.tooLarge(fileName) }
            let attachment = ChatAttachment(
                id: UUID(), kind: .pdf, fileName: fileName,
                storedName: "\(UUID().uuidString).pdf", mimeType: "application/pdf"
            )
            try FileManager.default.copyItem(at: sourceURL, to: url(for: attachment))
            return attachment
        }

        // Anything else has to be readable as text (source code, CSV, Markdown, logs, …)
        guard size <= maxTextBytes else { throw ChatAttachmentError.tooLarge(fileName) }
        guard let data = try? Data(contentsOf: sourceURL) else { throw ChatAttachmentError.unreadable(fileName) }
        guard let text = decodeText(data) else { throw ChatAttachmentError.unsupported(fileName) }
        let attachment = ChatAttachment(
            id: UUID(), kind: .text, fileName: fileName,
            storedName: "\(UUID().uuidString).txt", mimeType: "text/plain"
        )
        try text.write(to: url(for: attachment), atomically: true, encoding: .utf8)
        return attachment
    }

    /// Stores an image pasted from the clipboard (PNG/TIFF data). Blocking.
    static func importImageData(_ data: Data) throws -> ChatAttachment {
        let fileName = String(localized: "chatPastedImageName")
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ChatAttachmentError.unreadable(fileName)
        }
        return try storeImage(from: source, fileName: fileName)
    }

    private static func storeImage(from source: CGImageSource, fileName: String) throws -> ChatAttachment {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxImageDimension
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else {
            throw ChatAttachmentError.unreadable(fileName)
        }

        // JPEG has no alpha channel: flatten transparent areas (e.g. window screenshots) onto white
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)

        let output = NSMutableData()
        guard let flattened = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ChatAttachmentError.unreadable(fileName)
        }
        CGImageDestinationAddImage(destination, flattened, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ChatAttachmentError.unreadable(fileName) }

        let baseName = (fileName as NSString).deletingPathExtension
        let attachment = ChatAttachment(
            id: UUID(), kind: .image, fileName: baseName + ".jpg",
            storedName: "\(UUID().uuidString).jpg", mimeType: "image/jpeg"
        )
        try (output as Data).write(to: url(for: attachment), options: .atomic)
        return attachment
    }

    /// Decodes text files; nil for binary data.
    private static func decodeText(_ data: Data) -> String? {
        guard !data.contains(0) else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252)
    }

    // MARK: - Reading

    static func base64(of attachment: ChatAttachment) -> String? {
        try? Data(contentsOf: url(for: attachment)).base64EncodedString()
    }

    /// Text content of a text or PDF attachment ("" for images or missing files)
    static func text(of attachment: ChatAttachment) -> String {
        switch attachment.kind {
        case .text:
            return (try? String(contentsOf: url(for: attachment), encoding: .utf8)) ?? ""
        case .pdf:
            return PDFDocument(url: url(for: attachment))?.string ?? ""
        case .image:
            return ""
        }
    }

    // MARK: - Cleanup

    static func delete(_ attachments: [ChatAttachment]) {
        for attachment in attachments {
            try? FileManager.default.removeItem(at: url(for: attachment))
        }
    }

    /// Deletes stored files that no message refers to any more (e.g. from drafts that
    /// were never sent). Only safe at launch, before a composer can hold a draft attachment.
    static func removeOrphans(keeping storedNames: Set<String>) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where !storedNames.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
