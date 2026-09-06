import SwiftUI
import RulebookKit

/// One condition row: field picker, then whatever editor that field needs.
///
/// Conditions are not uniform — `.subject` wants text and a match mode,
/// `.hasAttachment` is a switch, `.size` is two numbers, `.importance` is an
/// enum. A single "field / operator / value" row can only express the first,
/// which is why this switches on kind.
struct ConditionEditor: View {
    @Binding var condition: RuleCondition
    let model: RuleEditorModel
    let joiner: String
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(joiner)
                    .font(DS.Font.sectionHeader)
                    .tracking(DS.Metric.sectionTracking)
                    .foregroundStyle(DS.Palette.ink60)
                Spacer()
                Button("Remove", action: onRemove)
                    .font(DS.Font.captionBold)
                    .foregroundStyle(DS.Palette.destructive)
            }

            fieldPicker
            valueEditor
        }
        .padding(.vertical, 14)
        .padding(.horizontal, DS.Metric.gutter)
    }

    // MARK: - Field

    private var fieldPicker: some View {
        Picker(selection: kindBinding) {
            ForEach(model.conditionKinds, id: \.self) { kind in
                Text(model.label(for: kind)).tag(kind)
            }
        } label: {
            Text("Field")
        }
        .pickerStyle(.menu)
        .tint(DS.Palette.accent700)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var kindBinding: Binding<ConditionKind> {
        Binding(
            get: { condition.kind },
            // Changing the field resets the value: a subject substring means
            // nothing as an importance level.
            set: { condition = .blank($0) }
        )
    }

    // MARK: - Value

    @ViewBuilder
    private var valueEditor: some View {
        switch condition {
        case .from, .recipient, .subject, .body, .subjectOrBody:
            textMatchEditor

        case .header(let name, let match):
            if model.profile.capabilities.supportsNamedHeaders {
                TextField("Header name — e.g. X-Mailer", text: Binding(
                    get: { name ?? "" },
                    set: { condition = .header(name: $0.isEmpty ? nil : $0, match: match) }
                ))
                .textFieldStyle(RuleFieldStyle())
            }
            textMatchEditor

        case .hasAttachment(let value):
            Toggle("Has an attachment", isOn: Binding(
                get: { value },
                set: { condition = .hasAttachment($0) }
            ))
            .font(DS.Font.body)
            .tint(DS.Palette.accent)

        case .size(let constraint):
            SizeEditor(constraint: constraint) { condition = .size($0) }

        case .importance(let value):
            enumPicker("Importance", Importance.allCases, value) { condition = .importance($0) }

        case .sensitivity(let value):
            enumPicker("Sensitivity", Sensitivity.allCases, value) { condition = .sensitivity($0) }

        case .addressed(let scope):
            enumPicker("Addressed", AddressedScope.allCases, scope) { condition = .addressed($0) }

        case .messageKind(let kind, let expected):
            enumPicker("Message type", MessageKind.allCases, kind) {
                condition = .messageKind($0, expected)
            }
            Toggle("Must be this type", isOn: Binding(
                get: { expected },
                set: { condition = .messageKind(kind, $0) }
            ))
            .font(DS.Font.body)
            .tint(DS.Palette.accent)

        case .actionFlag(let flag):
            enumPicker("Flagged for", ActionFlag.allCases, flag) { condition = .actionFlag($0) }

        case .hasLabels(let values):
            TextField("Categories, comma separated", text: Binding(
                get: { values.joined(separator: ", ") },
                set: { text in
                    let parts = text.split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    condition = .hasLabels(parts)
                }
            ))
            .textFieldStyle(RuleFieldStyle())

        case .rawQuery(let provider, let query):
            TextField("Provider query", text: Binding(
                get: { query },
                set: { condition = .rawQuery(provider: provider, query: $0) }
            ))
            .textFieldStyle(RuleFieldStyle())
            Text("Passed to \(provider.rawValue) untouched. Not portable to other providers.")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Palette.ink60)
        }
    }

    /// Text plus a match mode. The mode picker lists only what the provider
    /// supports — and there is no negation anywhere in `MatchMode`, which is
    /// why exceptions exist.
    @ViewBuilder
    private var textMatchEditor: some View {
        if let match = condition.stringMatch {
            if model.matchModes.count > 1 {
                Picker(selection: Binding(
                    get: { match.mode },
                    set: { condition = condition.replacing(match: .init(match.anyOf, mode: $0)) }
                )) {
                    ForEach(model.matchModes, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                } label: {
                    Text("Operator")
                }
                .pickerStyle(.menu)
                .tint(DS.Palette.accent700)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            TextField("Value — e.g. accounts@", text: Binding(
                get: { match.anyOf.first ?? "" },
                set: { condition = condition.replacing(match: .init([$0], mode: match.mode)) }
            ))
            .textFieldStyle(RuleFieldStyle())
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            if match.anyOf.count > 1 {
                Text("Matches any of \(match.anyOf.count) values.")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Palette.ink60)
            }
        }
    }

    private func enumPicker<T: Hashable & RawRepresentable>(
        _ title: String,
        _ options: [T],
        _ selection: T,
        set: @escaping (T) -> Void
    ) -> some View where T.RawValue == String {
        Picker(selection: Binding(get: { selection }, set: set)) {
            ForEach(options, id: \.self) { option in
                Text(option.rawValue.humanised).tag(option)
            }
        } label: {
            Text(title)
        }
        .pickerStyle(.menu)
        .tint(DS.Palette.accent700)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Size

/// Bytes in the model, megabytes in the UI. The neutral model is bytes because
/// providers disagree — Graph is kilobytes, Gmail is bytes.
private struct SizeEditor: View {
    let constraint: SizeConstraint
    let onChange: (SizeConstraint) -> Void

    var body: some View {
        HStack(spacing: 8) {
            field("At least", bytes: constraint.minimumBytes) {
                onChange(.init(minimumBytes: $0, maximumBytes: constraint.maximumBytes))
            }
            field("At most", bytes: constraint.maximumBytes) {
                onChange(.init(minimumBytes: constraint.minimumBytes, maximumBytes: $0))
            }
        }
    }

    private func field(_ label: String, bytes: Int?, set: @escaping (Int?) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(DS.Font.caption).foregroundStyle(DS.Palette.ink60)
            TextField("MB", text: Binding(
                get: { bytes.map { String(format: "%g", Double($0) / 1_048_576) } ?? "" },
                set: { text in
                    guard let mb = Double(text), mb > 0 else { return set(nil) }
                    set(Int(mb * 1_048_576))
                }
            ))
            .keyboardType(.decimalPad)
            .textFieldStyle(RuleFieldStyle())
        }
    }
}

// MARK: - Shared field style

struct RuleFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(DS.Font.body)
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(DS.Palette.surface, in: .rect(cornerRadius: DS.Metric.controlRadius))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Metric.controlRadius)
                    .strokeBorder(DS.Palette.hairline, lineWidth: 1)
            }
    }
}

extension MatchMode {
    var displayName: String {
        switch self {
        case .contains: "contains"
        case .equals: "is exactly"
        case .startsWith: "starts with"
        case .endsWith: "ends with"
        }
    }
}

extension String {
    /// `meetingRequest` → "Meeting request", for enum cases shown in pickers.
    var humanised: String {
        let spaced = reduce(into: "") { result, character in
            if character.isUppercase && !result.isEmpty { result.append(" ") }
            result.append(character)
        }
        return spaced.prefix(1).uppercased() + spaced.dropFirst().lowercased()
    }
}
