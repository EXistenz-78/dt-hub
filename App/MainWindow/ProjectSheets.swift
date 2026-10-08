import AppKit
import HubCore
import HubKit
import SwiftUI

/// The words for what went wrong with a project name or a project.
enum ProjectText {
  static func message(_ error: ProjectNameError) -> String {
    switch error {
    case .empty: String(localized: "project.error.empty")
    case .forbiddenCharacter: String(localized: "project.error.forbidden")
    case .leadingDot: String(localized: "project.error.dot")
    case .tooLong: String(localized: "project.error.long")
    case .looksLikeADate: String(localized: "project.error.date")
    case .alreadyExists: String(localized: "project.error.exists")
    }
  }

  static func message(_ error: ProjectManagerError) -> String {
    switch error {
    case .busy: String(localized: "project.error.busy")
    case .notFound: String(localized: "project.error.exists")
    case .catalog(.invalidName(let name)): message(name)
    case .catalog(.cannotWrite(let reason)): String(format: String(localized: "project.error.write"), reason)
    }
  }
}

/// A name field with the rules of a project name, and Create. `title` and `allowsCancel` let the same form serve the
/// "New project…" sheet and the sheet that asks for the first project.
struct NewProjectForm: View {
  let projects: ProjectManager
  let title: LocalizedStringKey
  var allowsCancel = true
  var onCancel: () -> Void = {}
  var onCreated: () -> Void = {}
  @State private var name = ""
  @State private var failure: String?

  /// The rules that can be checked while typing (the folders of the output folder that are not projects are only
  /// known when the project is made).
  private var typingProblem: String? {
    guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
    if case .failure(let error) = ProjectName.validate(name, existing: projects.projects.map(\.name)) {
      return ProjectText.message(error)
    }
    return nil
  }

  var body: some View {
    VStack(alignment: .leading, spacing: DS.rowGap) {
      Text(title).font(.headline)
      TextField("project.name.placeholder", text: $name)
        .textFieldStyle(.roundedBorder)
        .onSubmit(create)
        .onChange(of: name) { failure = nil }
      Text(verbatim: failure ?? typingProblem ?? " ")
        .font(.caption)
        .foregroundStyle(DS.remove)
        .frame(minHeight: 16, alignment: .leading)
      HStack(spacing: DS.controlGap) {
        Spacer(minLength: 0)
        if allowsCancel {
          Button("project.cancel", action: onCancel)
            .buttonStyle(DSPillButtonStyle())
            .keyboardShortcut(.cancelAction)
        }
        Button("project.create", action: create)
          .buttonStyle(DSPillButtonStyle(prominent: true))
          .keyboardShortcut(.defaultAction)
          .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || typingProblem != nil)
      }
    }
  }

  private func create() {
    guard typingProblem == nil, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
    Task {
      if await projects.create(named: name) {
        onCreated()
      } else {
        failure = projects.lastError.map(ProjectText.message) ?? ""
      }
    }
  }
}

/// "New project…" from the header menu.
struct NewProjectSheet: View {
  let projects: ProjectManager
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NewProjectForm(projects: projects, title: "project.new", onCancel: { dismiss() }, onCreated: { dismiss() })
      .padding(20)
      .frame(width: 380)
  }
}

/// What the window shows while no project is open: the first launch, a changed output folder, a project that went
/// away. It cannot be dismissed; it closes when a project opens.
struct ProjectGateSheet: View {
  let projects: ProjectManager
  @State private var creating = false

  var body: some View {
    Group {
      if projects.projects.isEmpty || creating {
        NewProjectForm(
          projects: projects, title: projects.projects.isEmpty ? "project.sheet.create.title" : "project.new",
          allowsCancel: !projects.projects.isEmpty, onCancel: { creating = false })
      } else {
        VStack(alignment: .leading, spacing: DS.rowGap) {
          Text("project.sheet.choose.title").font(.headline)
          ScrollView {
            VStack(alignment: .leading, spacing: 4) {
              ForEach(projects.projects) { project in
                Button {
                  Task { await projects.open(project) }
                } label: {
                  Label(title: { Text(verbatim: project.name) }, icon: { Image(systemName: "folder") })
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
              }
            }
          }
          .frame(maxHeight: 220)
          HStack {
            Spacer(minLength: 0)
            Button("project.new") { creating = true }.buttonStyle(DSPillButtonStyle(prominent: true))
          }
        }
      }
    }
    .padding(20)
    .frame(width: 380)
    .interactiveDismissDisabled()
  }
}
