import AppKit
import Combine
import Foundation

extension SteamWorkshopService {
    func webValidationReport(for record: SteamWorkshopDownloadRecord) -> SteamWorkshopWebValidationReport? {
        let signature = webValidationSignature(for: record)
        if let cached = webValidationReportCache[record.id], cached.signature == signature {
            return cached.report
        }
        guard record.contentType == .web else {
            return nil
        }

        let descriptor = resolvedWebProjectDescriptor(for: record)
        let sampleStructure = descriptor?.sampleStructure ?? webSampleStructure(for: record)
        let sourceRecord = webPropertyDefinitionSourceRecord(for: record)
        let propertyDefinitions = descriptor?.propertyDefinitions ?? webPropertyDefinitions(for: record)
        let propertySource = descriptor?.propertySource ?? {
            if let sourceRecord, sourceRecord.id != record.id {
                return SteamWorkshopWebPropertySource.dependencyHost(itemID: sourceRecord.id)
            }
            return .ownProject
        }()
        let presetOverrideCount = descriptor?.presetOverrideMap.count ?? webPresetValues(for: record).count
        let staticContentSummary = descriptor?.staticContentSummary

        if case let .missing(itemID) = record.dependencyStatus,
           record.isDependencyBackedWeb,
           record.hasPlayableDependencyWebHost == false {
            let issue = SteamWorkshopWebValidationIssue(
                severity: .warning,
                level: .preconditionUnmet,
                message: "当前样本属于依赖型 WEB 预设壳，需先下载依赖宿主 \(itemID) 后才能运行"
            )
            return SteamWorkshopWebValidationReport(
                sampleStructure: sampleStructure,
                entryRelativePath: "",
                scannedFileCount: 0,
                issueCount: 1,
                issues: [issue],
                propertySource: propertySource,
                presetOverrideCount: presetOverrideCount
            )
        }

        guard let entryURL = descriptor?.resolvedEntryURL ?? record.webEntryURL else {
            return SteamWorkshopWebValidationReport(
                sampleStructure: sampleStructure,
                entryRelativePath: "",
                scannedFileCount: 0,
                issueCount: 1,
                issues: [.init(severity: .error, level: .fatal, message: "没有找到可播放的 HTML 入口文件")],
                propertySource: propertySource,
                presetOverrideCount: presetOverrideCount
            )
        }

        let resolvedEntryURL = entryURL.resolvingSymlinksInPath().standardizedFileURL
        let rootURL = descriptor?.effectiveRootURL ?? effectiveWebRootURL(for: record, entryURL: resolvedEntryURL)
        let entryRelativePath = descriptor?.resolvedEntryRelativePath ?? webRelativePath(for: resolvedEntryURL, under: rootURL)
        var issues: [SteamWorkshopWebValidationIssue] = []
        var emittedIssueKeys = Set<String>()
        var scannedFiles = Set<URL>()
        var pendingFiles = [resolvedEntryURL]
        var externalDependencyURLs = Set<String>()
        var usesWebMResource = staticContentSummary?.usesWebMResource ?? false
        var usesHoverOnlyInteraction = staticContentSummary?.usesHoverOnlyInteraction ?? false
        var usesGeneralProperties = staticContentSummary?.usesApplyGeneralProperties ?? false
        var usesGeneralFPS = staticContentSummary?.usesGeneralFPS ?? false
        var usesPluginBridge = staticContentSummary?.usesPluginBridge ?? false
        var usesPersistentBrowserStorage = staticContentSummary?.usesPersistentBrowserStorage ?? false
        var scannedRiskFlags = Set<ResolvedWebRuntimeRiskFlag>()

        func appendIssue(_ severity: SteamWorkshopWebValidationSeverity, _ level: SteamWorkshopWebValidationLevel, _ message: String) {
            let issue = SteamWorkshopWebValidationIssue(severity: severity, level: level, message: message)
            let key = "\(issue.level.rawValue)|\(issue.severity.rawValue)|\(issue.message)"
            guard emittedIssueKeys.insert(key).inserted else { return }
            issues.append(issue)
        }

        if record.isDependencyBackedWeb,
           let dependencyItemID = record.dependencyItemID {
            switch record.dependencyStatus {
            case .available:
                appendIssue(.info, .info, "当前样本属于依赖型 WEB 预设壳，已接入依赖宿主 \(dependencyItemID)")
            case .missing:
                appendIssue(.warning, .preconditionUnmet, "当前样本属于依赖型 WEB 预设壳，但依赖宿主 \(dependencyItemID) 尚不可用")
            case .none:
                break
            }
        }

        if record.isDependencyBackedWeb,
           let shellEntryURL = record.webOwnEntryURL,
           let shellRootURL = record.folderURL.resolvingSymlinksInPath().standardizedFileURL as URL? {
            let shellEntryRelativePath = webRelativePath(for: shellEntryURL, under: shellRootURL)
            appendIssue(.info, .info, "当前样本作为补丁壳运行：壳入口 \(shellEntryRelativePath)；实际宿主入口 \(entryRelativePath)")
        } else if record.isDependencyBackedWeb,
                  let dependencyItemID = record.dependencyItemID {
            appendIssue(.info, .info, "当前样本没有独立 HTML 壳入口，当前播放入口完全来自依赖宿主 \(dependencyItemID)")
        }

        if let sourceRecord, sourceRecord.id != record.id {
            appendIssue(.info, .info, "当前属性定义来源于依赖宿主 \(sourceRecord.id)，预设覆盖项 \(presetOverrideCount) 个")
        } else if presetOverrideCount > 0 {
            appendIssue(.info, .info, "当前样本包含 \(presetOverrideCount) 个预设覆盖项")
        }

        if let normalizedDeclaredEntry = declaredWebEntryRelativePath(for: record) {
            let declaredEntryURL = record.folderURL.appendingPathComponent(normalizedDeclaredEntry).resolvingSymlinksInPath().standardizedFileURL
            if !FileManager.default.fileExists(atPath: declaredEntryURL.path) {
                let issueLevel: SteamWorkshopWebValidationLevel = record.isDependencyBackedWeb ? .info : .fatal
                let issueSeverity: SteamWorkshopWebValidationSeverity = record.isDependencyBackedWeb ? .info : .error
                let message = record.isDependencyBackedWeb
                    ? "补丁壳自身声明入口不存在：\(normalizedDeclaredEntry)（已回退到依赖宿主入口）"
                    : "project.json 声明的入口文件不存在：\(normalizedDeclaredEntry)"
                appendIssue(issueSeverity, issueLevel, message)
            } else {
                let declaredRelativePath = webRelativePath(for: declaredEntryURL, under: rootURL)
                if declaredRelativePath != entryRelativePath {
                    appendIssue(.info, .info, "当前入口回退为：\(entryRelativePath)（project.json 声明：\(normalizedDeclaredEntry)）")
                }
            }
        }

        if !FileManager.default.fileExists(atPath: resolvedEntryURL.path) {
            appendIssue(.error, .fatal, "入口文件不存在：\(entryRelativePath)")
        }

        let maxScanFiles = 200
        while let fileURL = pendingFiles.first, scannedFiles.count < maxScanFiles {
            pendingFiles.removeFirst()
            guard scannedFiles.insert(fileURL).inserted else { continue }
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                appendIssue(.warning, .warning, "无法读取文件：\(webRelativePath(for: fileURL, under: rootURL))")
                continue
            }

            if Self.webContentUsesWebMResource(content) {
                usesWebMResource = true
            }
            if fileURL.pathExtension.localizedLowercase == "css",
               Self.webContentUsesHoverOnlyInteraction(content) {
                usesHoverOnlyInteraction = true
            }
            if Self.webContentUsesApplyGeneralProperties(content) {
                usesGeneralProperties = true
            }
            if Self.webContentUsesGeneralFPS(content) {
                usesGeneralFPS = true
            }
            if Self.webContentUsesPluginBridge(content) {
                usesPluginBridge = true
            }
            if Self.webContentUsesPersistentBrowserStorage(content) {
                usesPersistentBrowserStorage = true
            }

            for reference in Self.extractLocalWebResourceReferences(from: content, fileExtension: fileURL.pathExtension) {
                switch reference {
                case let .local(path):
                    guard let resolvedURL = Self.resolveWebResourceURL(path, relativeTo: fileURL, rootURL: rootURL) else {
                        appendIssue(.warning, .warning, "发现越界或无法解析的资源路径：\(path)")
                        continue
                    }
                    let exists = FileManager.default.fileExists(atPath: resolvedURL.path)
                    if exists == false {
                        let missingPath = webRelativePath(for: resolvedURL, under: rootURL)
                        let missingLevel = webValidationLevelForMissingResource(
                            relativePath: missingPath,
                            sampleStructure: sampleStructure,
                            referencingFileExtension: fileURL.pathExtension,
                            record: record
                        )
                        let missingMessage = webValidationMessageForMissingResource(
                            relativePath: missingPath,
                            sampleStructure: sampleStructure,
                            referencingFileExtension: fileURL.pathExtension,
                            level: missingLevel,
                            record: record
                        )
                        appendIssue(missingLevel.severity, missingLevel, missingMessage)
                        continue
                    }

                    let ext = resolvedURL.pathExtension.localizedLowercase
                    if ext == "webm" {
                        usesWebMResource = true
                    }
                    if ["html", "htm", "css", "js", "json"].contains(ext),
                       Self.shouldScanWebDependencyFile(named: resolvedURL.lastPathComponent) {
                        pendingFiles.append(resolvedURL)
                    }
                case let .external(urlString):
                    externalDependencyURLs.insert(urlString)
                    appendIssue(.warning, .warning, "依赖外部资源：\(urlString)")
                }
            }
        }

        if !scannedFiles.isEmpty {
            appendIssue(.info, .info, "已扫描 \(scannedFiles.count) 个入口/依赖文件")
        }
        let cachedExternalURLs = staticContentSummary.map {
            Set($0.externalDependencyHosts.map { "https://\($0)" })
        } ?? []
        let effectiveExternalDependencyURLs = externalDependencyURLs.union(cachedExternalURLs)
        appendWebExternalDependencyIssues(from: effectiveExternalDependencyURLs, appendIssue: appendIssue)

        if usesWebMResource {
            scannedRiskFlags.insert(.webMHeavyMedia)
        }
        if usesHoverOnlyInteraction {
            scannedRiskFlags.insert(.hoverOnlyInteraction)
        }
        if usesGeneralProperties {
            appendIssue(.info, .info, "检测到样本使用 applyGeneralProperties；当前宿主已提供基础 general properties 注入")
        }
        if usesGeneralFPS {
            appendIssue(.info, .info, "检测到样本读取 properties.fps；当前宿主仅提供占位型 fps general properties 兼容，尚未与真实全局 FPS 设置完整联动")
        }
        if usesPluginBridge {
            scannedRiskFlags.insert(.pluginBridgeApproximation)
        }
        if usesPersistentBrowserStorage {
            scannedRiskFlags.insert(.persistentBrowserStorageUsage)
        }
        if staticContentSummary?.hasOnDemandDirectoryProperty == true {
            appendIssue(.info, .info, "检测到目录属性使用 ondemand 模式；当前宿主更偏按需随机文件解析语义，尚未完全覆盖更复杂旧生态样本对目录枚举/刷新节奏的预期")
        }
        if staticContentSummary?.hasFetchAllDirectoryProperty == true {
            appendIssue(.info, .info, "检测到目录属性使用 fetchall 模式；当前宿主已提供基础文件变化通知与目录同步，但这仍属于 fetchall 定向兼容，不代表通用目录能力已完整对齐")
        }
        let localhostDependencyHosts = staticContentSummary?.localhostDependencyHosts ?? []
        let remoteExternalHosts = (staticContentSummary?.externalDependencyHosts ?? []).filter {
            !localhostDependencyHosts.contains($0)
        }
        if !localhostDependencyHosts.isEmpty {
            scannedRiskFlags.insert(.localhostDependency)
        }
        if !remoteExternalHosts.isEmpty {
            scannedRiskFlags.insert(.externalServiceDependency)
        }

        appendWebPropertyPreconditionIssues(
            preconditions: resolvedWebRuntimePreconditions(
                for: record,
                definitions: propertyDefinitions,
                effectiveValues: effectiveWebPropertyValues(for: record, definitions: propertyDefinitions)
            ),
            sampleStructure: sampleStructure,
            appendIssue: appendIssue
        )
        appendHighLoadWebSampleIssue(
            riskFlags: resolvedWebStructuralRiskFlags(for: record, sampleStructure: sampleStructure),
            appendIssue: appendIssue
        )
        appendScannedWebRuntimeRiskIssues(
            riskFlags: resolvedWebStructuralRiskFlags(for: record, sampleStructure: sampleStructure) + Array(scannedRiskFlags),
            appendIssue: appendIssue
        )

        if let failureMessage = webPlaybackFailureMessage(for: record) {
            let playbackFailureIssue = webPlaybackFailureIssue(for: failureMessage)
            appendIssue(playbackFailureIssue.severity, playbackFailureIssue.level, playbackFailureIssue.message)
        }

        let report = SteamWorkshopWebValidationReport(
            sampleStructure: sampleStructure,
            entryRelativePath: entryRelativePath,
            scannedFileCount: scannedFiles.count,
            issueCount: issues.count,
            issues: issues,
            propertySource: propertySource,
            presetOverrideCount: presetOverrideCount
        )
        webValidationReportCache[record.id] = CachedWebValidationReport(signature: signature, report: report)
        return report
    }

    func webPlaybackFailureMessage(for record: SteamWorkshopDownloadRecord) -> String? {
        if let failureRecordID = lastWebPlaybackFailureRecordID {
            guard failureRecordID == record.id else { return nil }
            return lastWebPlaybackFailureMessage
        }

        guard let entryURL = record.webEntryURL,
              let failurePath = lastWebPlaybackFailurePath else {
            return nil
        }
        let entryPath = entryURL.resolvingSymlinksInPath().standardizedFileURL.path
        guard failurePath == entryPath else { return nil }
        return lastWebPlaybackFailureMessage
    }
}
