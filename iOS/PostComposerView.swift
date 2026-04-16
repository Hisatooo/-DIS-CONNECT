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
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // ── ヘッダー ──
                    HStack {
                        Button("キャンセル") { dismiss() }
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                        Spacer()
                        Button {
                            Task { await postNewPost() }
                        } label: {
                            Text("投稿")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 8)
                                .background(Color.white)
                                .clipShape(Capsule())
                        }
                        .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPosting)
                        .opacity(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    Divider().background(Color.white.opacity(0.08))

                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            // テキスト入力（テキストのみ）
                            TextEditor(text: $bodyText)
                                .frame(minHeight: 180)
                                .scrollContentBackground(.hidden)
                                .foregroundColor(.white)
                                .font(.system(size: 16))
                                .tint(.white)
                                .padding(.horizontal, 16)
                                .padding(.top, 16)

                            // デトックス時間添付トグル（前回セッションがある場合のみ表示）
                            if !lasttuneTime.isEmpty {
                                Button {
                                    attachDetoxTime.toggle()
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: attachDetoxTime ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 22))
                                            .foregroundColor(attachDetoxTime ? .blue : Color(hex: "6B7280"))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("デトックス時間を添付")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.white)
                                            Text(formatTime(lasttuneTime))
                                                .font(.system(size: 13))
                                                .foregroundColor(Color(hex: "6B7280"))
                                        }
                                        Spacer()
                                    }
                                    .padding(14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.white.opacity(attachDetoxTime ? 0.08 : 0.04))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(
                                                        attachDetoxTime ? Color.blue.opacity(0.5) : Color.white.opacity(0.08),
                                                        lineWidth: 1
                                                    )
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                            }
                        }
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .preferredColorScheme(.dark)
        .onAppear { loadLasttuneTime() }
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
