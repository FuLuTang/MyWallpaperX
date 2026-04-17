import SwiftUI
import AppKit
import Combine

struct SteamWorkshopActiveWebInspectorView: View {
    let record: SteamWorkshopDownloadRecord

    @ObservedObject private var service = SteamWorkshopService.shared

    private var runtimeModel: ResolvedWebRuntimeModel? {
        service.resolvedWebRuntimeModel(for: record)
    }

    private var visibleDefinitions: [SteamWorkshopWebPropertyDefinition] {
        guard let runtimeModel else { return [] }
        let visibleKeys = Set(runtimeModel.visiblePropertyKeys)
        return runtimeModel.descriptor.propertyDefinitions.filter { visibleKeys.contains($0.key) }
    }

    private var resolvedRuntimeValuesByKey: [String: SteamWorkshopWebPropertyValue] {
        runtimeModel?.resolvedRuntimeValues ?? [:]
    }

    private var visibleOptionsByKey: [String: [SteamWorkshopWebPropertyOption]] {
        runtimeModel?.visibleOptionsByKey ?? [:]
    }

    var body: some View {
        let definitions = visibleDefinitions

        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    headerSection

                    diagnosticsSection

                    if !definitions.isEmpty {
                        propertySection(definitions: definitions)
                    } else {
                        emptySection
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 2)
                .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(record.title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("当前正在播放的 Web 壁纸属性")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            if record.isDependencyBackedWeb,
               let hostEntryURL = record.webDependencyHostEntryURL {
                Text("补丁宿主：\(hostEntryURL.lastPathComponent)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            if let entryURL = record.webEntryURL {
                Text(record.isDependencyBackedWeb ? "实际播放入口：\(entryURL.lastPathComponent)" : entryURL.lastPathComponent)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
    }

    private func propertySection(definitions: [SteamWorkshopWebPropertyDefinition]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .overlay(Color.white.opacity(0.035))

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("运行中属性")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("这里的修改会直接热更新到当前 Web 壁纸宿主")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Button("重置") {
                    service.resetWebPropertyValues(for: record)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            ForEach(definitions) { definition in
                SteamWorkshopWebPropertyControlRow(
                    definition: definition,
                    value: resolvedRuntimeValuesByKey[definition.key] ?? definition.defaultValue,
                    visibleOptions: visibleOptionsByKey[definition.key] ?? [],
                    onPreview: { previewValue in
                        service.previewWebPropertyValue(previewValue, for: definition, record: record)
                    },
                    onChange: { newValue in
                        service.updateWebPropertyValue(newValue, for: definition, record: record)
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var diagnosticsSection: some View {
        if let snapshot = runtimeModel?.diagnosticsSnapshot {
            SteamWorkshopActiveWebInspectorDiagnosticsSection(
                snapshot: snapshot,
                fallbackResourceKeys: runtimeModel?.fallbackResourceKeys ?? []
            )
        }
    }

    private var emptySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .overlay(Color.white.opacity(0.035))

            Text("当前 Web 壁纸没有声明可编辑的 User Properties")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
