import Foundation
import Observation

@MainActor @Observable
final class QuickStatusDraft {
    var projectID: UUID?
    var day = Date.now
    var text = ""
    var isSaving = false
    var error: String?
}
