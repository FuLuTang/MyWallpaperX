import SwiftUI

struct SteamWorkshopItemDetailWebPropertiesSection: View {
    private enum ExpansionPolicy {
        static let autoExpandThreshold = 8
    }

    let record: SteamWorkshopDownloadRecord
    let descriptor: ResolvedWebProjectDescriptor?
    @ObservedObject private var service = SteamWorkshopService.shared
    @State private var isExpanded = false
    @State private var isAdvancedExpanded = false
    @State private var didInitializeExpansion = false

    private func propertyRow(_ row: SteamWorkshopResolvedWebPropertyRowModel) -> some View {
        SteamWorkshopWebPropertyControlRow(
            definition: row.definition,
            value: row.currentValue,
            visibleOptions: row.visibleOptions,
            onPreview: { (previewValue: SteamWorkshopWebPropertyValue) in
                service.previewWebPropertyValue(previewValue, for: row.definition, record: record)
            },
            onChange: { (newValue: SteamWorkshopWebPropertyValue) in
                service.updateWebPropertyValue(newValue, for: row.definition, record: record)
            }
        )
    }

    var body: some View {
        if let descriptor {
            let previewSnapshot = sectionSnapshot(
                descriptor: descriptor,
                includeRows: false
            )
            let renderableDefinitionCount = previewSnapshot.renderableDefinitionCount
            let shouldUseCollapsedPresentation = renderableDefinitionCount > ExpansionPolicy.autoExpandThreshold
            let expandedSnapshot = sectionSnapshot(
                descriptor: descriptor,
                includeRows: isExpanded
            )
            let groupedRows = groupedRows(from: expandedSnapshot.resolvedRows)

            if renderableDefinitionCount > 0 {
            Divider()
                .overlay(Color.white.opacity(0.035))

            VStack(alignment: .leading, spacing: 12) {
                if shouldUseCollapsedPresentation {
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("WEB 属性")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Text(record.isDependencyBackedWeb
                                     ? "属性定义来自依赖宿主，当前修改会写回这个补丁壳样本"
                                     : "根据当前壁纸的 `project.json` 动态生成调节项")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }

                            Spacer(minLength: 12)

                            Text(isExpanded ? "收起" : "展开 \(renderableDefinitionCount) 项")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("WEB 属性")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(record.isDependencyBackedWeb
                             ? "属性定义来自依赖宿主，当前修改会写回这个补丁壳样本"
                             : "根据当前壁纸的 `project.json` 动态生成调节项")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }

                if isExpanded {
                    HStack {
                        Spacer(minLength: 12)

                        Button("重置") {
                            service.resetWebPropertyValues(for: record)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if groupedRows.primary.isEmpty && groupedRows.advanced.isEmpty {
                        Text("当前没有可显示的可调属性")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(groupedRows.primary) { row in
                            propertyRow(row)
                        }

                        if groupedRows.hasAdvanced {
                            Button {
                                withAnimation(.easeInOut(duration: 0.16)) {
                                    isAdvancedExpanded.toggle()
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Text(isAdvancedExpanded ? "收起高级参数" : "展开高级参数 \(groupedRows.advanced.count) 项")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if isAdvancedExpanded {
                                ForEach(groupedRows.advanced) { row in
                                    propertyRow(row)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 2)
            .onAppear {
                guard didInitializeExpansion == false else { return }
                isExpanded = shouldUseCollapsedPresentation == false
                isAdvancedExpanded = false
                didInitializeExpansion = true
            }
            }
        }
    }

    private func sectionSnapshot(
        descriptor: ResolvedWebProjectDescriptor,
        includeRows: Bool
    ) -> SteamWorkshopWebPropertySectionSnapshot {
        let values = service.effectiveWebPropertyValues(for: record, descriptor: descriptor)
        let renderableDefinitions = descriptor.propertyDefinitions.filter {
            service.shouldRenderWebPropertyControl($0)
            && service.shouldDisplayWebProperty($0, values: values)
        }

        guard includeRows else {
            return SteamWorkshopWebPropertySectionSnapshot(
                renderableDefinitionCount: renderableDefinitions.count,
                resolvedRows: []
            )
        }

        let rows = renderableDefinitions.map { definition in
            SteamWorkshopResolvedWebPropertyRowModel(
                definition: definition,
                currentValue: values[definition.key] ?? definition.defaultValue,
                visibleOptions: service.visibleWebPropertyOptions(for: definition, values: values)
            )
        }
        return SteamWorkshopWebPropertySectionSnapshot(
            renderableDefinitionCount: renderableDefinitions.count,
            resolvedRows: rows
        )
    }

    private func groupedRows(from rows: [SteamWorkshopResolvedWebPropertyRowModel]) -> SteamWorkshopWebPropertyGroups {
        let primary = rows.filter { service.isPrimaryWebPropertyControl($0.definition) }
        let advanced = rows.filter { !service.isPrimaryWebPropertyControl($0.definition) }
        return SteamWorkshopWebPropertyGroups(primary: primary, advanced: advanced)
    }
}

struct SteamWorkshopItemDetailWebDiagnosticsSection: View {
    let report: SteamWorkshopWebValidationReport
    let record: SteamWorkshopDownloadRecord?
    let descriptor: ResolvedWebProjectDescriptor?

    var body: some View {
        let resolvedEntryPath = descriptor?.resolvedEntryRelativePath ?? report.entryRelativePath
        let entrySummary = resolvedEntryPath.isEmpty ? "未解析到入口" : resolvedEntryPath

        Divider()
            .overlay(Color.white.opacity(0.035))

        VStack(alignment: .leading, spacing: 10) {
            Text("WEB 诊断")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            SteamWorkshopInlineNotice(
                icon: "square.stack.3d.up",
                text: "属性来源：\(descriptor?.propertySource.displayName ?? report.propertySource.displayName)"
                    + ((descriptor?.presetOverrideMap.count ?? report.presetOverrideCount) > 0
                        ? "  ·  壳 preset 覆盖 \(descriptor?.presetOverrideMap.count ?? report.presetOverrideCount) 条"
                        : "")
            )

            SteamWorkshopInlineNotice(
                icon: "doc.text.magnifyingglass",
                text: "样本结构：\(descriptor?.sampleStructure.displayName ?? report.sampleStructure.displayName)  ·  入口：\(entrySummary)  ·  扫描文件：\(report.scannedFileCount)"
            )

            if report.issues.isEmpty {
                SteamWorkshopValidationPill(
                    severity: .info,
                    levelTitle: SteamWorkshopWebValidationLevel.info.displayName,
                    message: "未发现明显的本地资源缺失或外部依赖风险"
                )
            } else {
                ForEach(report.issues) { issue in
                    SteamWorkshopValidationPill(
                        severity: issue.severity,
                        levelTitle: issue.level.displayName,
                        message: issue.message
                    )
                }
            }

            if let record,
               case let .missing(itemID) = record.dependencyStatus {
                SteamWorkshopValidationPill(
                    severity: .warning,
                    levelTitle: SteamWorkshopWebValidationLevel.preconditionUnmet.displayName,
                    message: record.isDependencyBackedWeb
                        ? "当前样本属于依赖型 WEB 预设壳，需先下载依赖宿主 \(itemID) 才能运行"
                        : "当前项目声明依赖包 \(itemID)，但本地未找到该依赖的可启动 WEB 入口"
                )
            }
        }
        .padding(.horizontal, 2)
    }
}
