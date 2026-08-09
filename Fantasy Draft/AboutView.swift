import SwiftUI

struct AboutView: View {
    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version, build) {
        case let (version?, build?):
            return "Version \(version) (Build \(build))"
        case let (version?, nil):
            return "Version \(version)"
        case let (nil, build?):
            return "Build \(build)"
        default:
            return "Version unavailable"
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            Image("fantasyfootball2-vector")
                .resizable()
                .scaledToFit()
                .frame(width: 280, height: 186)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("Fantasy football wizard illustration")

            VStack(spacing: 6) {
                Text("Fantasy Draft")
                    .font(.title.bold())

                Text("Fantasy football draft board")
                    .font(.body)
                    .foregroundStyle(.secondary)
                
                Text("Copyright David Fekke LLC © 2026")
                    .font(.body)
                    .foregroundStyle(.secondary)
                
                Text(versionText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                
            }
        }
        .padding(32)
        .frame(width: 380)
    }
}

#Preview {
    AboutView()
}
