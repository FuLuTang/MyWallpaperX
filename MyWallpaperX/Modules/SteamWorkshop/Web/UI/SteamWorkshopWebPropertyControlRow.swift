import SwiftUI
import AppKit

struct SteamWorkshopWebPropertyControlRow: View {
    let definition: SteamWorkshopWebPropertyDefinition
    let value: SteamWorkshopWebPropertyValue
    let visibleOptions: [SteamWorkshopWebPropertyOption]
    let onPreview: (SteamWorkshopWebPropertyValue) -> Void
    let onChange: (SteamWorkshopWebPropertyValue) -> Void
    @State var filePickerError: String?
    @State private var sliderDraftValue: Double?
    @State private var colorDraftValue: String?
    @State private var colorCommitTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                if definition.kind != .group && definition.kind != .label {
                    Text(definition.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                Spacer(minLength: 8)
                if definition.kind != .group && definition.kind != .label {
                    Text(valueSummary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            control

            if let filePickerError {
                Text(filePickerError)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.red)
            }

            if let footnote = propertyFootnote {
                Text(footnote)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.10))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.7)
        }
    }

    @ViewBuilder
    private var control: some View {
        switch definition.kind {
        case .slider:
            sliderControl
        case .color:
            colorControl
        case .toggle:
            toggleControl
        case .combo:
            comboControl
        case .file:
            fileControl(selectsDirectories: false)
        case .directory:
            fileControl(selectsDirectories: true)
        case .label, .group:
            staticTextControl
        case .text, .unknown:
            textControl
        }
    }

    private var sliderControl: some View {
        let minimum = definition.minimumValue ?? 0
        let currentValue = value.numberValue ?? definition.defaultValue.numberValue ?? minimum
        let maximum = definition.maximumValue ?? max(minimum + 1, currentValue)

        return Slider(
            value: Binding(
                get: { sliderDraftValue ?? currentValue },
                set: { newValue in
                    let normalized = normalizedSliderValue(from: newValue)
                    sliderDraftValue = normalized
                    onPreview(.number(normalized))
                }
            ),
            in: minimum...maximum,
            onEditingChanged: { editing in
                if !editing {
                    let committedValue = sliderDraftValue ?? currentValue
                    sliderDraftValue = nil
                    onChange(.number(committedValue))
                }
            }
        )
        .onChange(of: value) { _, newValue in
            if sliderDraftValue == nil {
                return
            }
            guard let resolvedValue = newValue.numberValue else {
                sliderDraftValue = nil
                return
            }
            if abs(resolvedValue - (sliderDraftValue ?? resolvedValue)) > 0.000_001 {
                sliderDraftValue = nil
            }
        }
    }

    private var colorControl: some View {
        HStack(spacing: 12) {
            ColorPicker(
                "",
                selection: Binding(
                    get: { colorValue },
                    set: { newColor in
                        let colorString = Self.colorString(from: newColor)
                        colorDraftValue = colorString
                        onPreview(.string(colorString))
                        scheduleColorCommit(colorString)
                    }
                ),
                supportsOpacity: false
            )
            .labelsHidden()

            TextField(
                "R G B",
                text: Binding(
                    get: { colorDraftValue ?? value.stringValue ?? definition.defaultValue.stringValue ?? "" },
                    set: {
                        colorDraftValue = $0
                        cancelScheduledColorCommit()
                        onChange(.string($0))
                    }
                )
            )
            .textFieldStyle(.roundedBorder)
        }
        .onChange(of: value) { _, newValue in
            if colorDraftValue == newValue.stringValue {
                colorDraftValue = nil
            }
        }
        .onDisappear {
            cancelScheduledColorCommit()
        }
    }

    private var toggleControl: some View {
        Toggle(
            "",
            isOn: Binding(
                get: { value.boolValue ?? definition.defaultValue.boolValue ?? false },
                set: { onChange(.bool($0)) }
            )
        )
        .toggleStyle(.switch)
        .labelsHidden()
    }

    private var comboControl: some View {
        let selectionBinding = Binding(
            get: {
                if visibleOptions.contains(where: { $0.value == value }) {
                    return value
                }
                return visibleOptions.first?.value ?? value
            },
            set: { onChange($0) }
        )

        return Group {
            if visibleOptions.isEmpty {
                Text("当前没有可选项")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Picker("", selection: selectionBinding) {
                    ForEach(visibleOptions) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(comboRefreshID)
            }
        }
    }

    private func fileControl(selectsDirectories: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button(selectsDirectories ? "选择文件夹" : "选择文件") {
                    presentPathPicker(selectsDirectories: selectsDirectories)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if currentPath.isEmpty == false {
                    Button("清空") {
                        onChange(.string(""))
                        filePickerError = nil
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer(minLength: 0)
            }

            TextField(
                selectsDirectories ? "选择目录路径" : "选择文件路径",
                text: Binding(
                    get: { currentPath },
                    set: {
                        filePickerError = nil
                        onChange(.string($0))
                    }
                )
            )
            .textFieldStyle(.roundedBorder)
        }
    }

    private var staticTextControl: some View {
        Text(definition.title)
            .font(definition.kind == .group ? .system(size: 13, weight: .semibold) : .system(size: 12))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    private var textControl: some View {
        TextField(
            definition.title,
            text: Binding(
                get: {
                    if let stringValue = value.stringValue {
                        return stringValue
                    }
                    if let numberValue = value.numberValue {
                        return Self.formattedNumber(numberValue, allowsFractional: true, precision: definition.fractionalPrecision)
                    }
                    if let boolValue = value.boolValue {
                        return boolValue ? "true" : "false"
                    }
                    return ""
                },
                set: { onChange(.string($0)) }
            )
        )
        .textFieldStyle(.roundedBorder)
    }

    private var colorValue: Color {
        Self.color(from: colorDraftValue ?? value.stringValue ?? definition.defaultValue.stringValue ?? "0 0 0")
    }

    private var currentPath: String {
        value.stringValue ?? definition.defaultValue.stringValue ?? ""
    }

    private var comboRefreshID: String {
        let optionIDs = visibleOptions.map(\ .id).joined(separator: "|")
        return [definition.key, String(value.hashValue), optionIDs].joined(separator: "::")
    }

    private var valueSummary: String {
        if definition.kind == .slider,
           let sliderDraftValue {
            return Self.formattedNumber(
                sliderDraftValue,
                allowsFractional: definition.allowsFractionalValues,
                precision: definition.fractionalPrecision
            )
        }
        if definition.kind == .color,
           let colorDraftValue {
            return SteamWorkshopService.normalizedWebDisplayText(colorDraftValue)
        }
        if let stringValue = value.stringValue {
            return SteamWorkshopService.normalizedWebDisplayText(stringValue)
        }
        if let numberValue = value.numberValue {
            return Self.formattedNumber(
                numberValue,
                allowsFractional: definition.allowsFractionalValues,
                precision: definition.fractionalPrecision
            )
        }
        if let boolValue = value.boolValue {
            return boolValue ? "开" : "关"
        }
        return "-"
    }

    private var propertyFootnote: String? {
        switch definition.kind {
        case .slider:
            return nil
        case .combo:
            guard visibleOptions.isEmpty == false else { return nil }
            return "\(visibleOptions.count) options"
        case .color:
            return "Wallpaper Engine RGB string"
        case .file:
            return "Wallpaper Engine file path string"
        case .directory:
            if let mode = definition.directoryMode {
                return "Wallpaper Engine directory path string  ·  mode \(mode)"
            }
            return "Wallpaper Engine directory path string"
        case .label, .group, .toggle, .text, .unknown:
            return nil
        }
    }

    private func normalizedSliderValue(from newValue: Double) -> Double {
        if definition.allowsFractionalValues {
            let precision = SteamWorkshopService.effectiveWebSliderPrecision(for: definition) ?? 2
            if precision >= 0 {
                let scale = pow(10.0, Double(precision))
                return (newValue * scale).rounded() / scale
            }
            return newValue
        }
        return newValue.rounded()
    }

    private func scheduleColorCommit(_ colorString: String) {
        cancelScheduledColorCommit()
        colorCommitTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            onChange(.string(colorString))
            if colorDraftValue == colorString {
                colorDraftValue = nil
            }
            colorCommitTask = nil
        }
    }

    private func cancelScheduledColorCommit() {
        colorCommitTask?.cancel()
        colorCommitTask = nil
    }

}
