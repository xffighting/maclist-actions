import AppKit
import MacListCore
import UniformTypeIdentifiers

final class FileCellView: NSTableCellView {
    private let fileIcon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        fileIcon.translatesAutoresizingMaskIntoConstraints = false
        fileIcon.imageScaling = .scaleProportionallyUpOrDown

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingMiddle

        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.font = .systemFont(ofSize: 11)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle

        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        metaLabel.font = .systemFont(ofSize: 10, weight: .medium)
        metaLabel.textColor = .tertiaryLabelColor
        metaLabel.alignment = .right

        addSubview(fileIcon)
        addSubview(titleLabel)
        addSubview(pathLabel)
        addSubview(metaLabel)

        NSLayoutConstraint.activate([
            fileIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            fileIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            fileIcon.widthAnchor.constraint(equalToConstant: 32),
            fileIcon.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.leadingAnchor.constraint(equalTo: fileIcon.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: metaLabel.leadingAnchor, constant: -8),

            pathLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            pathLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            pathLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),

            metaLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            metaLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            metaLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 58)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(with record: FileRecord, now: Date = Date()) {
        if let contentType = UTType(filenameExtension: record.url.pathExtension) {
            fileIcon.image = NSWorkspace.shared.icon(for: contentType)
        } else {
            fileIcon.image = NSImage(
                systemSymbolName: "doc",
                accessibilityDescription: "文件"
            )
        }
        titleLabel.stringValue = record.displayName
        pathLabel.stringValue = PrivacyPolicy.compactParentPath(for: record.path)

        if record.lastUsedAt == .distantPast {
            metaLabel.stringValue = "Spotlight"
        } else {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            metaLabel.stringValue = formatter.localizedString(for: record.lastUsedAt, relativeTo: now)
        }
        toolTip = record.path
    }
}
