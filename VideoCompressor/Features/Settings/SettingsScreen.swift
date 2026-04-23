import SwiftUI

public struct SettingsScreen: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var minimumSizeMB: Double = 50

    public init() {}

    public var body: some View {
        Form {
            Section("Presets") {
                NavigationLink(destination: PresetsScreen()) {
                    Label("Presets bearbeiten", systemImage: "slider.horizontal.3")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("**Komprimieren**: reduziert Videos für deine eigene Mediathek und maximiert die Einsparung.")
                    Text("**Teilen**: arbeitet auf eine feste Zielgrösse hin, damit ein Export in Uploads, Chats oder Mail passt.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Mindestgrösse für Mediathek-Filter") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("≥ \(Int(minimumSizeMB)) MB")
                    Slider(value: $minimumSizeMB, in: 5...500, step: 5)
                        .onChange(of: minimumSizeMB) { _, new in
                            environment.settings.settings.libraryMinimumSizeBytes = Int64(new * 1024 * 1024)
                        }
                }
            }

            Section {
                Picker("Standard nach erfolgreichem Export", selection: Binding(
                    get: { environment.settings.settings.defaultDeleteBehavior },
                    set: { environment.settings.settings.defaultDeleteBehavior = $0 }
                )) {
                    ForEach(AppSettings.DefaultDeleteBehavior.allCases, id: \.self) { v in
                        Text(v.displayName).tag(v)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("**Jedes Mal fragen**: Nach erfolgreicher Komprimierung erscheint ein Dialog, ob das Original gelöscht werden soll.")
                    Text("**Behalten**: Originale werden nie automatisch entfernt. Du kannst pro Export manuell entscheiden.")
                    Text("**Löschen**: Toggle ist vorbelegt. Vor dem Start kommt trotzdem eine Sicherheits-Bestätigung.")
                    Text("Hinweis: iOS verschiebt gelöschte Videos in „Zuletzt gelöscht“. VideoCompressor kann diesen Schritt nicht überspringen.")
                        .padding(.top, 2)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("Verhalten beim Löschen des Originals")
            }

            Section("Spezialformat-Warnungen") {
                Picker("Verhalten", selection: Binding(
                    get: { environment.settings.settings.specialFormatWarning },
                    set: { newValue in
                        environment.settings.settings.specialFormatWarning = newValue
                        if newValue == .warnOnce {
                            environment.settings.settings.specialFormatWarningWasShown = false
                        }
                    }
                )) {
                    ForEach(AppSettings.SpecialFormatWarning.allCases, id: \.self) { v in
                        Text(v.displayName).tag(v)
                    }
                }
                Text("Spezialformate wie Cinematic, Spatial oder Slow Motion können beim Re-Encode Metadaten verlieren. „Einmalig warnen“ zeigt die Bestätigung beim nächsten solchen Export genau einmal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Einstellungen")
        .onAppear {
            minimumSizeMB = Double(environment.settings.settings.libraryMinimumSizeBytes) / (1024.0 * 1024.0)
        }
    }
}
