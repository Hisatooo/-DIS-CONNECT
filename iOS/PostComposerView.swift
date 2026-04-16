import SwiftUI
import Firebase
import FirebaseAuth
import FirebaseFirestore

struct PostComposerView: View {
    @Environment(\.dismiss) var dismiss
    @State private var bodyText = ""
    @State private var isPosting = false
    @State private var attachDetoxTime = false
    @State private var lasttuneTime = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        TextEditor(text: $bodyText)
                            .frame(minHeight: 150)
                            .padding(.horizontal)
                            .scrollContentBackground(.hidden)

                        if !lasttuneTime.isEmpty {
                            Button {
                                attachDetoxTime.toggle()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: attachDetoxTime ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(attachDetoxTime ? .blue : .secondary)
                                    Text("デトックス時間を添付 · \(formatTime(lasttuneTime))")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical)
                }

                Divider()
            }
            .navigationTitle("新規投稿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("投稿") {
                        Task { await postNewPost() }
                    }
                    .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPosting)
                    .fontWeight(.bold)
                }
            }
            .onAppear { loadLasttuneTime() }
        }
    }

    private func loadLasttuneTime() {
        if let time = UserDefaults.standard.string(forKey: "detox.lastTuneTime"), !time.isEmpty {
            lasttuneTime = time
        }
    }

    private func formatTime(_ code: String) -> String {
        guard code.count == 4,
              let h = Int(code.prefix(2)),
              let m = Int(code.suffix(2)) else { return code }
        if h == 0 { return "\(m)分" }
        if m == 0 { return "\(h)時間" }
        return "\(h)時間\(m)分"
    }

    private func postNewPost() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isPosting = true
        defer { isPosting = false }

        var postData: [String: Any] = [
            "userID": uid,
            "body": bodyText.trimmingCharacters(in: .whitespacesAndNewlines),
            "Posts": Timestamp(date: Date()),
            "like": 0,
            "commentCount": 0
        ]
        if attachDetoxTime && !lasttuneTime.isEmpty {
            postData["time"] = lasttuneTime
        }

        do {
            try await Firestore.firestore().collection("posts").addDocument(data: postData)
            dismiss()
        } catch {
            print("Post error: \(error)")
        }
    }
}
