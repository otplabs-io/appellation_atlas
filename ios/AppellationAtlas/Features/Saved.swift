import SwiftData
import SwiftUI

/// A place you starred, with your own notes. Kept with SwiftData and synced through your iCloud account, so it follows
/// you between iPhone and iPad. CloudKit asks that every field have a default and none be unique.
@Model
final class SavedPlace {
    var placeID: String = ""
    var note: String = ""
    var savedAt: Date = Date()
    var editedAt: Date = Date()

    init(placeID: String) {
        self.placeID = placeID
    }
}

extension ModelContainer {
    /// Syncs with iCloud when the app is signed for it, and keeps working on the device alone when it is not.
    static func atlas() -> ModelContainer {
        let schema = Schema([SavedPlace.self])
        if let c = try? ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)) { return c }
        return try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .none))
    }
}

/// Star a place: the round button beside its name.
struct StarButton: View {
    let placeID: String
    @Environment(\.modelContext) private var context
    @Query private var saved: [SavedPlace]

    init(placeID: String) {
        self.placeID = placeID
        _saved = Query(filter: #Predicate<SavedPlace> { $0.placeID == placeID })
    }

    var body: some View {
        let on = !saved.isEmpty
        Button {
            if on { saved.forEach(context.delete) } else { context.insert(SavedPlace(placeID: placeID)) }
        } label: {
            Image(systemName: on ? "star.fill" : "star").font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Palette.gold4[4])
                .frame(width: 44, height: 44)
                .background(Palette.card, in: Circle())
                .overlay(Circle().stroke(Palette.landEdge, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: on)
        .accessibilityLabel(on ? "Remove from saved places" : "Save this place")
    }
}

/// Your notes on a saved place, under its summary: tap to write or edit them.
struct SavedNote: View {
    let placeID: String
    @Query private var saved: [SavedPlace]
    @State private var editing = false

    init(placeID: String) {
        self.placeID = placeID
        _saved = Query(filter: #Predicate<SavedPlace> { $0.placeID == placeID })
    }

    var body: some View {
        if let item = saved.first {
            Group {
                if item.note.isEmpty {
                    Button { editing = true } label: { Label("Add notes", systemImage: "square.and.pencil") }
                        .font(.text(13, .heavy, relativeTo: .footnote)).foregroundStyle(Palette.teal)
                } else {
                    Text(item.note).font(.atlasBody).foregroundStyle(Palette.ink)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.goldTint.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                        .onTapGesture { editing = true }
                        .accessibilityLabel("Your notes: \(item.note)")
                        .accessibilityHint("Double tap to edit")
                }
            }
            .sheet(isPresented: $editing) { NotesEditor(place: item) }
        }
    }
}

struct NotesEditor: View {
    @Bindable var place: SavedPlace
    @Environment(\.dismiss) private var dismiss
    @Environment(Atlas.self) private var atlas
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            TextEditor(text: $place.note)
                .focused($focused)
                .font(.body)
                .padding(.horizontal, 12)
                .navigationTitle(atlas.name(place.placeID))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { place.editedAt = Date(); dismiss() } }
                }
                .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Your saved places, newest first.
struct SavedList: View {
    @Query(sort: \SavedPlace.savedAt, order: .reverse) private var saved: [SavedPlace]
    @Environment(Atlas.self) private var atlas
    @Environment(Nav.self) private var nav

    var body: some View {
        if !saved.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Saved places").font(.atlasSection).foregroundStyle(Palette.ink)
                ForEach(saved) { s in
                    Button { nav.go(s.placeID) } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "star.fill").foregroundStyle(Palette.gold4[4]).font(.caption)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(atlas.name(s.placeID)).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                                let sub = [atlas.kind(s.placeID), atlas.places[s.placeID]?.country ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")
                                if !sub.isEmpty { Text(sub).font(.atlasNote).foregroundStyle(Palette.soft) }
                                if !s.note.isEmpty { Text(s.note).font(.atlasNote).foregroundStyle(Palette.ink).lineLimit(2) }
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
