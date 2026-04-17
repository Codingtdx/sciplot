import Foundation

extension ComposerSession {
    func schedulePreview() {
        asyncCoordination.preview.schedule(delayNanoseconds: previewDelayNanoseconds) { [weak self] revision in
            guard let self else { return }
            await self.requestPreview(revision: revision)
        }
    }

    func requestPreview(revision: Int) async {
        guard let client else {
            return
        }

        isPreviewing = true
        defer {
            if asyncCoordination.preview.isLatest(revision) {
                isPreviewing = false
            }
        }

        do {
            let response = try await client.composePreview(project)
            guard asyncCoordination.preview.isLatest(revision), !Task.isCancelled else {
                return
            }
            previewResponse = response
            errorMessage = nil
        } catch {
            guard asyncCoordination.preview.isLatest(revision), !Task.isCancelled else {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    func mutateProject(actionName: String, mutation: (inout ComposerRequestPayload) -> Void) {
        let previous = project
        mutation(&project)
        exportURL = nil
        errorMessage = nil
        registerUndo(previousProject: previous, actionName: actionName)
        schedulePreview()
    }

    func commitProject(
        _ nextProject: ComposerRequestPayload,
        previousProject: ComposerRequestPayload,
        actionName: String
    ) {
        project = nextProject
        exportURL = nil
        errorMessage = nil
        registerUndo(previousProject: previousProject, actionName: actionName)
        schedulePreview()
    }

    func registerUndo(previousProject: ComposerRequestPayload, actionName: String) {
        guard let undoManager else {
            return
        }

        let currentProject = project
        undoManager.registerUndo(withTarget: self) { session in
            session.project = previousProject
            session.registerUndo(previousProject: currentProject, actionName: actionName)
            session.exportURL = nil
            session.schedulePreview()
        }
        undoManager.setActionName(actionName)
    }
}
