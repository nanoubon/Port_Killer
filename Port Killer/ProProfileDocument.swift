import SwiftUI
import UniformTypeIdentifiers

struct ProProfileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var profile: ProProfile

    init(profile: ProProfile) {
        self.profile = profile
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        profile = try JSONDecoder.portKillerProfile.decode(ProProfile.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder.portKillerProfile.encode(profile)
        return .init(regularFileWithContents: data)
    }
}
