import SwiftUI

extension FileBrowserView {
    func requestPatchCreation(
        for entry: FileEntry,
        bundleID: String?,
        containerPath: String,
        patchDraftCoordinator: PatchDraftCoordinator,
        activityText: Binding<String?>,
        operationNotice: Binding<FileReplacementNotice?>,
        language: AppLanguage
    ) {
        guard let bundleID else {
            operationNotice.wrappedValue = FileReplacementNotice(
                title: language.text("patch.create_from_browser_failed"),
                message: language.text("patch.error.invalid_bundle")
            )
            return
        }
        let itemURL = URL(fileURLWithPath: entry.path, isDirectory: entry.isDirectory)
        let containerURL = URL(fileURLWithPath: containerPath, isDirectory: true)
        activityText.wrappedValue = language.text("patch.preparing_from_browser")
        let suggestedName = entry.isDirectory
            ? entry.name
            : itemURL.deletingPathExtension().lastPathComponent
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let draft = try PatchDraftService.makeDraft(
                    bundleID: bundleID,
                    containerRoot: containerURL,
                    itemURL: itemURL,
                    suggestedName: suggestedName
                )
                DispatchQueue.main.async {
                    activityText.wrappedValue = nil
                    patchDraftCoordinator.present(draft)
                }
            } catch let error as PatchPackageError {
                DispatchQueue.main.async {
                    activityText.wrappedValue = nil
                    operationNotice.wrappedValue = FileReplacementNotice(
                        title: language.text("patch.create_from_browser_failed"),
                        message: language.text(error.localizationKey)
                    )
                }
            } catch {
                DispatchQueue.main.async {
                    activityText.wrappedValue = nil
                    operationNotice.wrappedValue = FileReplacementNotice(
                        title: language.text("patch.create_from_browser_failed"),
                        message: language.text("patch.error.invalid_project")
                    )
                }
            }
        }
    }
}
