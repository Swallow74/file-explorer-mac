import SwiftUI
import AppKit

// MARK: - Model

struct CustomCommand: Codable, Identifiable, Hashable {
    enum Applies: String, Codable, CaseIterable {
        case selection = "A selected item"
        case files = "Selected files"
        case folders = "Selected folders"
        case folder = "The current folder"

        var label: String { tr(rawValue) }

        var shortLabel: String {
            switch self {
            case .selection: return tr("Selection")
            case .files: return tr("Files")
            case .folders: return tr("Folders")
            case .folder: return tr("Folder")
            }
        }
    }

    var id = UUID()
    var name: String = tr("New command")
    var script: String = ""
    var icon: String = Icon.terminal.rawValue
    var applies: Applies = .selection
    var refreshAfter: Bool = true

    var iconCase: Icon { Icon(rawValue: icon) ?? .terminal }
}

/// User-defined shell commands. Deliberately scripts rather than loadable
/// native code: a plugin that can crash or compromise the app is not a feature.
final class CustomCommands: ObservableObject {
    static let shared = CustomCommands()

    @Published var commands: [CustomCommand] { didSet { save() } }

    static var storeURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask)[0]
            .appendingPathComponent("File Explorer")
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("commands.json")
    }

    private init() {
        if let data = try? Data(contentsOf: CustomCommands.storeURL),
           let list = try? JSONDecoder().decode([CustomCommand].self, from: data) {
            commands = list
        } else {
            commands = CustomCommands.samples
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(commands) else { return }
        try? data.write(to: CustomCommands.storeURL)
    }

    func reload() {
        guard let data = try? Data(contentsOf: CustomCommands.storeURL),
              let list = try? JSONDecoder().decode([CustomCommand].self, from: data) else { return }
        commands = list
    }

    static let samples: [CustomCommand] = [
        CustomCommand(name: "Copy names to clipboard",
                      script: "printf '%s\\n' \"$FE_NAMES\" | pbcopy",
                      icon: Icon.copy.rawValue, applies: .selection, refreshAfter: false),
        CustomCommand(name: "Make a dated backup",
                      script: "cp -R \"$FE_FIRST\" \"$FE_FIRST.$(date +%Y-%m-%d).bak\"",
                      icon: Icon.compress.rawValue, applies: .selection),
    ]

    // MARK: Running

    func applicable(to explorer: Explorer) -> [CustomCommand] {
        let selection = explorer.selectedItems
        return commands.filter { command in
            switch command.applies {
            case .selection: return !selection.isEmpty
            case .files: return selection.contains { !$0.isDirectory }
            case .folders: return selection.contains { $0.isDirectory }
            case .folder: return explorer.currentDirectory != nil
            }
        }
    }

    func run(_ command: CustomCommand, in explorer: Explorer) {
        let selection = explorer.selectedItems
        let paths = selection.map(\.url.path)
        var environment = ProcessInfo.processInfo.environment
        environment["FE_SELECTION"] = paths.joined(separator: "\n")
        environment["FE_NAMES"] = selection.map(\.name).joined(separator: "\n")
        environment["FE_FIRST"] = paths.first ?? ""
        environment["FE_DIR"] = explorer.currentDirectory?.path ?? ""
        environment["FE_COUNT"] = "\(paths.count)"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command.script]
        process.environment = environment
        process.currentDirectoryURL = explorer.currentDirectory ?? Places.home
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        explorer.flash(tr("Running %@", command.name))
        DispatchQueue.global(qos: .userInitiated).async {
            do { try process.run() } catch {
                DispatchQueue.main.async {
                    explorer.sheet = .error(tr("Could not run “%1$@”.\n%2$@", command.name, error.localizedDescription))
                }
                return
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let status = process.terminationStatus

            DispatchQueue.main.async {
                if status != 0 {
                    explorer.sheet = .error(tr("“%1$@” exited with status %2$@.", command.name, status)
                                            + (output.isEmpty ? "" : "\n\n\(output)"))
                } else {
                    explorer.flash(output.isEmpty ? tr("%@ finished", command.name)
                                                  : String(output.prefix(120)))
                }
                if command.refreshAfter { explorer.reload() }
            }
        }
    }
}

// MARK: - Settings section

struct CustomCommandsSettings: View {
    @ObservedObject var store = CustomCommands.shared
    @State private var editing: CustomCommand?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(tr("Commands run in zsh with your selection in the environment:")
                     + " $FE_SELECTION, $FE_NAMES, $FE_FIRST, $FE_DIR, $FE_COUNT.")
                    .font(Win.body(11)).foregroundStyle(Win.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                WinButton(padding: 10, height: 26) {
                    let fresh = CustomCommand()
                    store.commands.append(fresh)
                    editing = fresh
                } content: {
                    HStack(spacing: 6) {
                        Glyph(icon: .plus, size: 11, color: Win.text, weight: 1.4)
                        Text(tr("New command")).font(Win.body(11)).foregroundStyle(Win.text)
                    }
                }
                .overlay(WinRR(radius: 4).stroke(Win.stroke, lineWidth: 1))

                WinButton(padding: 10, height: 26) {
                    NSWorkspace.shared.activateFileViewerSelecting([CustomCommands.storeURL])
                } content: {
                    Text(tr("Show commands.json")).font(Win.body(11)).foregroundStyle(Win.text)
                }
                .overlay(WinRR(radius: 4).stroke(Win.stroke, lineWidth: 1))
                Spacer()
            }

            ForEach(store.commands) { command in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Glyph(icon: command.iconCase, size: 16,
                              color: Win.textSecondary, weight: 1.15)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(command.name).font(Win.body(12)).foregroundStyle(Win.text)
                            Text(command.applies.label)
                                .font(Win.body(11)).foregroundStyle(Win.textTertiary)
                        }
                        Spacer(minLength: 8)
                        WinButton(padding: 8, height: 26) {
                            editing = editing?.id == command.id ? nil : command
                        } content: {
                            Text(editing?.id == command.id ? tr("Done") : tr("Edit"))
                                .font(Win.body(11)).foregroundStyle(Win.text)
                        }
                        .overlay(WinRR(radius: 4).stroke(Win.stroke, lineWidth: 1))
                        WinButton(tooltip: tr("Delete"), padding: 6, height: 26) {
                            store.commands.removeAll { $0.id == command.id }
                            if editing?.id == command.id { editing = nil }
                        } content: {
                            Glyph(icon: .delete, size: 13, color: Win.textSecondary, weight: 1.15)
                        }
                    }

                    if editing?.id == command.id {
                        editor(for: command)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(WinRR(radius: 5).fill(Win.controlFill.opacity(0.5)))
            }
        }
    }

    @ViewBuilder
    private func editor(for command: CustomCommand) -> some View {
        let binding = Binding<CustomCommand>(
            get: { store.commands.first { $0.id == command.id } ?? command },
            set: { updated in
                if let i = store.commands.firstIndex(where: { $0.id == command.id }) {
                    store.commands[i] = updated
                }
            })

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                LabelledField(label: tr("Name"), text: binding.name, width: 190)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Applies to")).font(Win.body(11)).foregroundStyle(Win.textTertiary)
                    WinSegmented(options: CustomCommand.Applies.allCases.map { ($0.shortLabel, $0) },
                                 selection: binding.applies)
                }
                Spacer(minLength: 0)
            }
            Text(tr("Script")).font(Win.body(11)).foregroundStyle(Win.textTertiary)
            TextEditor(text: binding.script)
                .font(.system(size: 11, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 70)
                .background(WinRR(radius: 4).fill(Win.field))
                .overlay(WinRR(radius: 4).stroke(Win.stroke, lineWidth: 1))
            HStack(spacing: 7) {
                WinCheckbox(checked: binding.wrappedValue.refreshAfter) {
                    binding.wrappedValue.refreshAfter.toggle()
                }
                Text(tr("Refresh the folder afterwards"))
                    .font(Win.body(11)).foregroundStyle(Win.textSecondary)
            }
        }
    }
}
