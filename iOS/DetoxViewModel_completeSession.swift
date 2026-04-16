// PATCH: Replace completeSession() in DetoxViewModel.swift with this implementation.
// This saves elapsed time to UserDefaults so PostComposerView can read it.

/*
func completeSession() {
    timer?.cancel()
    timer = nil
    isActive = false
    isGroupDetox = false

    // Save elapsed time for PostComposerView (key: "detox.lastTuneTime", format: "HHmm")
    if displayElapsedSeconds > 0 {
        let h = displayElapsedSeconds / 3600
        let m = (displayElapsedSeconds % 3600) / 60
        UserDefaults.standard.set(String(format: "%02d%02d", h, m), forKey: "detox.lastTuneTime")
    }

    updateFirestoreSessionComplete(interrupted: false)
    showPostSession = true
}
*/

// Also add this function inside the DetoxViewModel class:
/*
func loadGroupSelection(groupId: String) {
    let key = "detox.groupSelection.\(groupId)"
    guard let data = UserDefaults.standard.data(forKey: key),
          let saved = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    else { return }
    groupActivitySelection = saved
}
*/
