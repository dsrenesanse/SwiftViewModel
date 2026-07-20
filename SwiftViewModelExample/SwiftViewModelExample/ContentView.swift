//
//  ContentView.swift
//  SwiftViewModelExample
//
//  Created by Dan on 20/07/2026.
//

import SwiftUI

struct ContentView: View {
    @State private var isModelAlive = true

    var body: some View {
        NavigationStack {
            Group {
                if isModelAlive {
                    UsersListView()
                } else {
                    ContentUnavailableView(
                        "View model destroyed",
                        systemImage: "xmark.bin",
                        description: Text("deinit cancelled every pending task and called deinitialize() — check the Xcode console. Tap Revive for a fresh one.")
                    )
                }
            }
            .navigationTitle("SwiftViewModel")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    // Destroying the screen releases the model: pending work is
                    // cancelled in deinit and deinitialize() fires.
                    Button(isModelAlive ? "Destroy" : "Revive") {
                        isModelAlive.toggle()
                    }
                }
            }
        }
    }
}

private struct UsersListView: View {
    @State private var model = UsersViewModel()

    var body: some View {
        List {
            counterSection
            usersSection
            activitySection
        }
    }

    private var counterSection: some View {
        @Bindable var model = model
        return Section {
            HStack {
                Text("Counter")
                Spacer()
                Text(model.counter)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Button("Slow +1 (1s of work)") {
                model.slowIncrement()
            }
        } header: {
            Text("processSync — serialized")
        } footer: {
            Text("Each tap computes on a snapshot for a second, then applies its update. Updates queue up and land strictly in order — mash the button and the counter never skips.")
        }
    }

    private var usersSection: some View {
        Section {
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            ForEach(model.users) { user in
                UserRow(model: model, user: user)
            }
        } header: {
            HStack {
                Text("process — parallel")
                if model.isLoadingUsers {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        } footer: {
            Text("Users come from jsonplaceholder.typicode.com. Tap rows to fetch their posts — every fetch runs in parallel against its own snapshot. Pull to refresh the list.")
        }
    }

    private var activitySection: some View {
        Section("Activity") {
            if model.activity.isEmpty {
                Text("Nothing yet")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(model.activity.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption.monospaced())
            }
        }
    }
}

private struct UserRow: View {
    let model: UsersViewModel
    let user: User

    var body: some View {
        Button {
            model.fetchPosts(for: user)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(user.name)
                    .foregroundStyle(.primary)
                Text(user.email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let posts = model.postsByUser[user.id] {
                    Text("\(posts.count) posts — “\(posts.first?.title ?? "")”")
                        .font(.caption2)
                        .foregroundStyle(.tint)
                        .lineLimit(1)
                } else if model.loadingPostsFor.contains(user.id) {
                    Text("Loading posts…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
