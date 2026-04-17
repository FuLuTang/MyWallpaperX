//
//  SteamWorkshopDownloadsView.swift
//  MyWallpaperX
//

import SwiftUI
import Combine

struct SteamWorkshopDownloadsView: View {
    var body: some View {
        SteamWorkshopDownloadsContentView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SteamWorkshopDownloadsContentView: View {
    @ObservedObject private var service = SteamWorkshopService.shared

    var body: some View {
        VStack(spacing: 0) {
            AppKitSteamWorkshopDownloadsGridView(
                service: service,
                onOpen: { item in
                    service.presentItemDetail(item)
                },
                onSetAsWallpaper: { record in
                    service.setAsWallpaper(record)
                },
                onReveal: { record in
                    service.revealItem(record)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .inspectorHostBridge(
            module: .steamWorkshop,
            selectedItem: service.selectedDownloadInspectorItem,
            makePresentation: { item in
                let subtitle = item.author.isEmpty ? "Steam 下载" : item.author
                return .infoPanel(
                    cardID: item.id,
                    title: item.title,
                    subtitle: subtitle,
                    preferredWidth: 356,
                    focusPolicy: .preserveCurrentResponder
                )
            },
            onSelectionCleared: {
                service.dismissDownloadInspector()
            },
            content: { item in
                SteamWorkshopItemDetailSheet(item: item)
            }
        )
        .onAppear {
            if service.downloads.isEmpty {
                service.reloadInstalledItems()
            }
        }
        .onDisappear {
            InspectorHostActions.postClose(module: .steamWorkshop)
            service.dismissDownloadInspector()
        }
        .overlay {
            if service.isLoginSheetPresented {
                SteamWorkshopLoginOverlay()
                    .transition(.opacity.animation(.easeOut(duration: 0.16)))
            }
        }
        .alert("下载失败", isPresented: Binding(
            get: { service.downloadError != nil },
            set: { if !$0 { service.downloadError = nil } }
        )) {
            Button("确定", role: .cancel) {
                service.downloadError = nil
            }
        } message: {
            Text(service.downloadError ?? "")
        }
    }
}
