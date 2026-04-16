import SwiftUI
import Firebase
import FirebaseAuth

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @EnvironmentObject var notificationViewModel: NotificationViewModel
    @State private var selectedTabIndex = 0
    @State private var isShowingPostComposer = false
    @State private var navigationUser: UserProfile?
    @State private var navigationPost: Post?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {

                // ── カスタムヘッダー（FriendsViewと同じスタイル） ──
                HStack {
                    Text("Home")
                        .font(.system(size: 36, weight: .black))
                        .foregroundColor(.white)
                    Spacer()
                    NavigationLink(destination: ActivityView(notificationVM: notificationViewModel)) {
                        let hasUnread = notificationViewModel.notifications.contains { !$0.isRead }
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "bell")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                            if hasUnread {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 2, y: -2)
                            }
                        }
                        .padding(4)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 24)
                .padding(.bottom, 14)

                TopTabBarView(selectedTabIndex: $selectedTabIndex) {
                    Task { await viewModel.fetchAllData() }
                }
                TabView(selection: $selectedTabIndex) {
                    TimelineView(
                        posts: viewModel.recommendedPosts,
                        viewModel: viewModel,
                        onProfileTap: { navigationUser = $0 },
                        onPostTap: { navigationPost = $0 }
                    )
                    .tag(0)
                    TimelineView(
                        posts: viewModel.followingPosts,
                        viewModel: viewModel,
                        onProfileTap: { navigationUser = $0 },
                        onPostTap: { navigationPost = $0 }
                    )
                    .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .background(Color.black.ignoresSafeArea())
            .navigationBarHidden(true)
            .navigationDestination(isPresented: Binding(
                get: { navigationUser != nil },
                set: { if !$0 { navigationUser = nil } }
            )) {
                if let user = navigationUser {
                    if user.id == Auth.auth().currentUser?.uid {
                        ProfileView()
                    } else {
                        FriendsProfileView(user: user)
                    }
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { navigationPost != nil },
                set: { if !$0 { navigationPost = nil } }
            )) {
                if let post = navigationPost { CommentView(post: post) }
            }

            Button(action: { isShowingPostComposer = true }) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(width: 56, height: 56)
                    .background(Color.white)
                    .clipShape(Circle())
                    .shadow(color: .white.opacity(0.2), radius: 8, y: 4)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 110)
        }
        .sheet(isPresented: $isShowingPostComposer) {
            PostComposerView()
        }
    }
}

// MARK: - タイムライン
struct TimelineView: View {
    let posts: [Post]
    let viewModel: HomeViewModel
    let onProfileTap: (UserProfile) -> Void
    let onPostTap: (Post) -> Void

    var body: some View {
        ZStack {
            if posts.isEmpty {
                EmptyTimelineView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(posts) { post in
                            PostRowView(
                                post: post,
                                viewModel: viewModel,
                                onProfileTap: onProfileTap,
                                onPostTap: onPostTap
                            )
                            .id(post.id)
                            Divider().background(Color.white.opacity(0.08))
                        }
                        if viewModel.isLoadingMore {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .padding(.vertical, 20)
                        }
                    }
                    .padding(.bottom, 100)
                }
                .refreshable { await viewModel.fetchAllData() }
            }
        }
        .background(Color.black)
    }
}

// MARK: - 空のタイムライン
struct EmptyTimelineView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 44))
                .foregroundColor(.white.opacity(0.2))
            VStack(spacing: 6) {
                Text("timeline_empty_title")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                Text("timeline_empty_desc")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "6B7280"))
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

// MARK: - 投稿セル
struct PostRowView: View {
    let post: Post
    @ObservedObject var viewModel: HomeViewModel
    let onProfileTap: (UserProfile) -> Void
    let onPostTap: (Post) -> Void

    @State private var isLiked = false
    @State private var likeCount: Int
    @State private var showingDeleteConfirm = false

    init(post: Post, viewModel: HomeViewModel,
         onProfileTap: @escaping (UserProfile) -> Void,
         onPostTap: @escaping (Post) -> Void) {
        self.post = post
        self.viewModel = viewModel
        self.onProfileTap = onProfileTap
        self.onPostTap = onPostTap
        _likeCount = State(initialValue: post.like)
        _isLiked = State(initialValue: post.id.map { viewModel.likedPostIDs.contains($0) } ?? false)
    }

    var body: some View {
        Button(action: { onPostTap(post) }) {
            HStack(alignment: .top, spacing: 12) {
                ProfileImageView(user: post.author)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .onTapGesture {
                        if let user = post.author { onProfileTap(user) }
                    }

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 4) {
                        Text(post.author?.displayName ?? String(localized: "common_loading"))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .onTapGesture {
                                if let user = post.author { onProfileTap(user) }
                            }
                        Text("@\(post.author?.id ?? "")")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "6B7280"))
                            .lineLimit(1)
                        Text("·")
                            .foregroundColor(Color(hex: "6B7280"))
                        Text(post.postDate.dateValue().toRelativeString())
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "6B7280"))
                        Spacer()
                        Menu {
                            Button(action: {
                                if let user = post.author { onProfileTap(user) }
                            }) {
                                Label("menu_view_profile", systemImage: "person.circle")
                            }
                            Button(role: .destructive, action: {}) {
                                Label("menu_report", systemImage: "exclamationmark.bubble")
                            }
                            if viewModel.canDelete(post) {
                                Button(role: .destructive) {
                                    showingDeleteConfirm = true
                                } label: {
                                    Label("投稿を削除", systemImage: "trash")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 14))
                                .foregroundColor(Color(hex: "6B7280"))
                                .padding(.vertical, 4)
                                .padding(.leading, 8)
                        }
                        .buttonStyle(.plain)
                    }

                    Text(post.body)
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)

                    if let timeString = post.time, !timeString.isEmpty {
                        DetoxTimeCard(timeString: timeString.toTimeFormat())
                            .padding(.top, 10)
                    }

                    HStack(spacing: 0) {
                        Button(action: { onPostTap(post) }) {
                            Image(systemName: "bubble.left")
                                .font(.system(size: 16))
                                .foregroundColor(Color(hex: "6B7280"))
                                .frame(height: 36)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Button(action: toggleLike) {
                            HStack(spacing: 5) {
                                Image(systemName: isLiked ? "heart.fill" : "heart")
                                    .font(.system(size: 16))
                                    .foregroundColor(isLiked ? .red : Color(hex: "6B7280"))
                                    .scaleEffect(isLiked ? 1.1 : 1.0)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isLiked)
                                if likeCount > 0 {
                                    Text("\(likeCount)")
                                        .font(.system(size: 13))
                                        .foregroundColor(isLiked ? .red : Color(hex: "6B7280"))
                                }
                            }
                            .frame(height: 36)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Button(action: {}) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16))
                                .foregroundColor(Color(hex: "6B7280"))
                                .frame(height: 36)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                    .padding(.trailing, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(ScalableListRowStyle())
        .onChange(of: viewModel.likedPostIDs) { _, newIDs in
            if let id = post.id { isLiked = newIDs.contains(id) }
        }
        .alert("この投稿を削除しますか？", isPresented: $showingDeleteConfirm) {
            Button("削除", role: .destructive) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task { await viewModel.deletePost(post) }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この操作は取り消せません")
        }
    }

    private func toggleLike() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            isLiked.toggle()
            likeCount += isLiked ? 1 : -1
        }
        Task { await viewModel.toggleLike(post: post) }
    }
}

// MARK: - ボタンスタイル
struct ScalableListRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.white.opacity(configuration.isPressed ? 0.04 : 0))
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - デトックス時間カード
struct DetoxTimeCard: View {
    let timeString: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "timer")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(hex: "6B7280"))
            Text("detox_time_last_session")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "6B7280"))
            Spacer()
            Text(timeString)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.1))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

// MARK: - プロフィール画像
struct ProfileImageView: View {
    let user: UserProfile?

    var body: some View {
        ZStack {
            if let iconUrl = user?.iconUrl, !iconUrl.isEmpty, let url = URL(string: iconUrl) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().interpolation(.medium)
                        .aspectRatio(contentMode: .fill).clipShape(Circle())
                } placeholder: {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.08))
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                }
            } else {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Color(hex: "6B7280"))
                    )
            }
        }
    }
}

// MARK: - 上部タブバー
struct TopTabBarView: View {
    @Binding var selectedTabIndex: Int
    var onTabTapped: () -> Void
    let tabs: [LocalizedStringKey] = ["tab_all", "tab_following"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs.indices, id: \.self) { index in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedTabIndex = index }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onTabTapped()
                }) {
                    VStack(spacing: 6) {
                        Text(tabs[index])
                            .font(.system(size: 15, weight: selectedTabIndex == index ? .semibold : .regular))
                            .foregroundColor(selectedTabIndex == index ? .white : Color(hex: "6B7280"))
                        Rectangle()
                            .frame(height: 2)
                            .foregroundColor(selectedTabIndex == index ? .white : .clear)
                            .cornerRadius(1)
                    }
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
            }
        }
        .background(Color.black)
        .overlay(
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5),
            alignment: .bottom
        )
    }
}

extension Color {
    static let appBackground = Color.black
}

extension Date {
    func toRelativeString() -> String {
        let cal = Calendar.current
        let c = cal.dateComponents([.minute, .hour, .day, .weekOfMonth, .month, .year],
                                   from: self, to: Date())
        if let v = c.year,        v >= 1 { return "\(v)年前" }
        if let v = c.month,       v >= 1 { return "\(v)ヶ月前" }
        if let v = c.weekOfMonth, v >= 1 { return "\(v)週間前" }
        if let v = c.day,         v >= 1 { return "\(v)日前" }
        if let v = c.hour,        v >= 1 { return "\(v)時間前" }
        if let v = c.minute,      v >= 1 { return "\(v)分前" }
        return "いまさっき"
    }
}

#Preview { HomeView() }
