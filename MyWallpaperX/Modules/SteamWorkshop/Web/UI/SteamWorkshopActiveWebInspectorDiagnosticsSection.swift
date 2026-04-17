import SwiftUI

struct SteamWorkshopActiveWebInspectorDiagnosticsSection: View {
    let snapshot: ResolvedWebRuntimeDiagnosticsSnapshot
    let fallbackResourceKeys: [String]

    private var playbackStatus: String {
        snapshot.isActivePlayback ? "播放中" : "未激活"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .overlay(Color.white.opacity(0.035))

            Text("运行诊断")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            SteamWorkshopInlineNotice(
                icon: "waveform.path.ecg",
                text: "入口：\(snapshot.entryRelativePath)  ·  当前状态：\(playbackStatus)"
            )

            SteamWorkshopInlineNotice(
                icon: "folder",
                text: "资源根：\(snapshot.rootPath)"
            )

            SteamWorkshopInlineNotice(
                icon: "slider.horizontal.3",
                text: "属性来源：\(snapshot.propertySource)  ·  可见属性：\(snapshot.visiblePropertyCount)  ·  preset 覆盖：\(snapshot.presetOverrideCount)"
            )

            if !fallbackResourceKeys.isEmpty {
                SteamWorkshopInlineNotice(
                    icon: "shippingbox.circle",
                    text: "preset fallback 资源键：\(fallbackResourceKeys.count)  ·  \(fallbackResourceKeys.joined(separator: ", "))"
                )
            }

            SteamWorkshopInlineNotice(
                icon: "shippingbox",
                text: "项目类型：\(snapshot.sourceKind)  ·  入口来源：\(snapshot.entrySource)  ·  样本结构：\(snapshot.sampleStructure)"
            )

            SteamWorkshopInlineNotice(
                icon: "doc.text.magnifyingglass",
                text: "校验 issue：\(snapshot.validationIssueCount)  ·  properties JSON：\(snapshot.propertyPayloadSize) bytes"
            )

            if !snapshot.runtimeRiskFlags.isEmpty {
                SteamWorkshopInlineNotice(
                    icon: "exclamationmark.triangle",
                    text: "风险标记：\(snapshot.runtimeRiskFlags.map(\.displayName).joined(separator: "、"))"
                )
            }

            if !snapshot.unmetPreconditionMessages.isEmpty {
                ForEach(snapshot.unmetPreconditionMessages, id: \.self) { message in
                    SteamWorkshopInlineNotice(icon: "key", text: message)
                }
            }

            if let lastPlaybackFailureMessage = snapshot.lastPlaybackFailureMessage,
               !lastPlaybackFailureMessage.isEmpty {
                SteamWorkshopInlineErrorNotice(message: "最近一次失败：\(lastPlaybackFailureMessage)", retry: { })
            }
        }
    }
}
