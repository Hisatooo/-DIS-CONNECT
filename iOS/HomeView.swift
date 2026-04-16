import SwiftUI
import Firebase
import FirebaseAuth
import FirebaseFirestore

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @State private var selectedTab = 0
    @State private var showComposer = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    TopTabBarView(selectedTab: $selectedTab)
                    Divider()

                    if selectedTab == 0 {
                        feedList
                    } else {
                        detoxFeedList
                    }
                }

                Button {
                    showComposer = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(width: 56, height: 56)
                        .background(Color.white)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 24)
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showComposer) {
                PostComposerView()
            }
            .onAppear { viewModel.fetchPosts() }
        }
    }

    private var feedList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.posts) { post in
                    PostRowView(post: post, viewModel: viewModel)
                    Divider()
                }
            }
        }
    }

    private var detoxFeedList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.posts.filter { $0.time != nil }) { post in
                    PostRowView(post: post, viewModel: viewModel)
                    Divider()
                }
                if viewModel.posts.filter({ $0.time != nil }).isEmpty {
                    Text("デトックス投稿はまだありません")
                        .foregroundStyle(.secondary)
                        .padding(.top, 60)
                }
            }
        }
    }
}

// MARK: - Tab Bar

struct TopTabBarView: View {
    @Binding var selectedTab: Int
    private let tabs = ["フィード", "デトックス"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs.indices, id: \.self) { i in
                Button {
                    selectedTab = i
                } label: {
                    VStack(spacing: 0) {
                        Text(tabs[i])
                            .font(.subheadline.weight(selectedTab == i ? .semibold : .regular))
                            .foregroundStyle(selectedTab == i ? .primary : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        Rectangle()
                            .fill(selectedTab == i ? Color.primary : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Post Row

struct PostRowView: View {
    let post: Post
    @ObservedObject var viewModel: HomeViewModel
    @State private var liked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(post.userName ?? "User")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(post.relativeTime)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let time = post.time {
                        Text(formatDetoxTime(time))
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }

                    Text(post.body)
                        .font(.subheadline)
                        .padding(.top, 2)

                    HStack(spacing: 24) {
                        Label("\(post.commentCount ?? 0)", systemImage: "bubble.left")
                        Button {
                            liked.toggle()
                            viewModel.toggleLike(post: post)
                        } label: {
                            Label("\(post.like + (liked ? 1 : 0))", systemImage: liked ? "heart.fill" : "heart")
                                .foregroundStyle(liked ? .red : .secondary)
                        }
                        Image(systemName: "arrow.2.squarepath")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func formatDetoxTime(_ code: String) -> String {
        guard code.count == 4,
              let h = Int(code.prefix(2)),
              let m = Int(code.suffix(2)) else { return code }
        if h == 0 { return "デトックス \(m)分" }
        if m == 0 { return "デトックス \(h)時間" }
        return "デトックス \(h)時間\(m)分"
    }
}
