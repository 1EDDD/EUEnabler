import SwiftUI

struct ContentView: View {
    @StateObject private var manager = EligibilityManager()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 10) {
                        Image(systemName: "globe.europe.africa.fill")
                            .font(.system(size: 42, weight: .medium))
                            .foregroundStyle(.blue)
                        Text("EU Enabler")
                            .font(.largeTitle.bold())
                        Text("iOS 27 · SystemGroup")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)

                    VStack(alignment: .leading, spacing: 12) {
                        Label("Device compatibility", systemImage: "iphone")
                            .font(.headline)
                        HStack {
                            Text("Current iOS")
                            Spacer()
                            Text(manager.systemVersion)
                                .monospacedDigit()
                                .foregroundStyle(manager.isSupported ? .green : .orange)
                        }
                        HStack {
                            Text("Access method")
                            Spacer()
                            Text("worse_query")
                                .font(.caption.monospaced())
                        }
                        HStack {
                            Text("Eligibility file")
                            Spacer()
                            Text("SystemGroup")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))

                    VStack(alignment: .leading, spacing: 12) {
                        Label("Status", systemImage: "waveform.path")
                            .font(.headline)
                        Text(manager.statusMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let error = manager.errorMessage {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))

                    Button {
                        manager.apply()
                    } label: {
                        HStack {
                            if manager.isWorking {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "checkmark.shield.fill")
                            }
                            Text("Enable EU eligibility")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!manager.isSupported || manager.isWorking)

                    Button(role: .destructive) {
                        manager.reset()
                    } label: {
                        Label("Restore original eligibility", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .disabled(manager.isWorking)

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Before applying", systemImage: "info.circle")
                            .font(.headline)
                        Text("The app backs up the current eligibility file before changing it. Keep the backup in the app’s Documents folder. A restart may be needed before iOS refreshes eligibility.")
                        Text("This build updates the SystemGroup eligibility.plist. It does not modify the older MobileAsset Config.plist.")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                }
                .padding()
            }
            .navigationTitle("EU Enabler")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(.blue)
    }
}
