import Foundation

@Observable
class SearchState {
    var isActive = false
    var query = ""
    var total: Int = 0
    var selected: Int = 0
    var focusTrigger: Int = 0

    func dismiss(surface: ghostty_surface_t?) {
        guard isActive else { return }
        if let surface {
            let action = "end_search"
            action.withCString { ptr in
                ghostty_surface_binding_action(surface, ptr, UInt(action.utf8.count))
            }
        }
        isActive = false
        query = ""
        total = 0
        selected = 0
    }
}
