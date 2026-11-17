import SwiftUI

struct FilterSheet: View {
    @Environment(TrainingStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @Binding var instructorFilter: String
    @Binding var search: String
    @Binding var hideCancelled: Bool
    @Binding var includeCompleted: Bool
    @Binding var showWeekends: Bool
    let myName: String

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass").chalk(Chalk.dim)
                        TextField("Course, customer, opportunity…", text: $search)
                            .font(Chalk.font(16))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !search.isEmpty {
                            Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain)
                                .chalk(Chalk.dim)
                        }
                    }
                } header: { header("Search") }
                .listRowBackground(Chalk.boardDeep.opacity(0.6))

                Section {
                    row(title: "Everyone", color: Chalk.white, value: "", count: store.trainings.count)
                    row(title: "Just me (\(myName))", color: Chalk.yellow, value: Prefs.mineToken,
                        count: count(for: myName))
                    ForEach(store.instructors) { person in
                        row(title: person.name, color: Chalk.tint(person.hex, fallbackSeed: person.name),
                            value: person.name, count: count(for: person.name))
                    }
                } header: { header("Instructor") }
                .listRowBackground(Chalk.boardDeep.opacity(0.6))

                Section {
                    Toggle("Hide cancelled & pending reschedule", isOn: $hideCancelled)
                    Toggle("Include Completed Courses board", isOn: $includeCompleted)
                    Toggle("Show weekends", isOn: $showWeekends)
                } header: { header("Show") }
                .font(Chalk.font(15))
                .tint(Chalk.green)
                .listRowBackground(Chalk.boardDeep.opacity(0.6))
            }
            .scrollContentBackground(.hidden)
            .background(ChalkboardBackground())
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        withAnimation {
                            instructorFilter = ""
                            search = ""
                            hideCancelled = true
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationBackground(Chalk.boardDeep)
    }

    private func header(_ text: String) -> some View {
        Text(text).font(Chalk.font(13, bold: true, relativeTo: .footnote)).chalk(Chalk.dim)
    }

    private func count(for name: String) -> Int {
        store.trainings.filter { $0.instructor.caseInsensitiveCompare(name) == .orderedSame }.count
    }

    private func row(title: String, color: Color, value: String, count: Int) -> some View {
        Button {
            withAnimation(Chalk.spring) { instructorFilter = value }
        } label: {
            HStack(spacing: 10) {
                Circle().fill(color).frame(width: 10, height: 10).shadow(color: color, radius: 2)
                Text(title).font(Chalk.font(16)).chalk()
                Spacer()
                Text("\(count)").font(Chalk.font(13)).chalk(Chalk.dim)
                if instructorFilter == value {
                    Image(systemName: "checkmark").chalk(Chalk.yellow)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
