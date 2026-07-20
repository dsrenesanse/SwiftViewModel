//
//  UsersViewModel.swift
//  SwiftViewModelExample
//
//  Created by Dan on 20/07/2026.
//

import Foundation
import SwiftViewModel
import SwiftClonable

/// Placeholder data from https://jsonplaceholder.typicode.com
struct User: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let username: String
    let email: String
}

struct Post: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let userId: Int
    let title: String
    let body: String
}

@Clonable
@Observable
final class UsersViewModel: ViewModel<UsersViewModel> {

    var users: [User] = []
    var postsByUser: [Int: [Post]] = [:]
    var loadingPostsFor: Set<Int> = []
    var isLoadingUsers = false
    var errorMessage: String? = nil
    var counter = "0"
    var activity: [String] = []
    
    override init() {
        super.init()
    }

    override func initialize() {
        fetchUsers()
    }

    override func deinitialize() {
       super.deinitialize()
    }

    func fetchUsers() {
        isLoadingUsers = true
        process { state in
            // `state` is a deep copy made by @Clonable's copy() - the slow part
            // below can never race with what the UI does to the live instance.
            do {
                let users: [User] = try await Self.get("users")
                return { live in
                    live.users = users
                    live.isLoadingUsers = false
                    live.errorMessage = nil
                    live.log("✓ got \(users.count) users")
                }
            } catch {
                return { live in
                    live.isLoadingUsers = false
                    live.errorMessage = error.localizedDescription
                    live.log("✗ users failed")
                }
            }
        }
    }

    func fetchPosts(for user: User) {
        guard !loadingPostsFor.contains(user.id) else { return }
        loadingPostsFor.insert(user.id)
        // Tap several rows quickly: each fetch runs in parallel on its own snapshot.
        process { state in
            do {
                let posts: [Post] = try await Self.get("posts?userId=\(user.id)")
                return { live in
                    live.postsByUser[user.id] = posts
                    live.loadingPostsFor.remove(user.id)
                    live.log("✓ \(posts.count) posts for \(user.username)")
                }
            } catch {
                return { live in
                    live.loadingPostsFor.remove(user.id)
                    live.log("✗ posts failed for \(user.username)")
                }
            }
        }
    }

    func slowIncrement() {
        processSync { state in
            try? await Task.sleep(for: .seconds(1))
            let next = state.counter + "0"
            return { live in
                live.counter = next
            }
        }
    }

    private func log(_ line: String) {
        activity.append(line)
        if activity.count > 20 {
            activity.removeFirst(activity.count - 20)
        }
    }

    private static func get<Value: Decodable>(_ path: String) async throws -> Value {
        let url = URL(string: "https://jsonplaceholder.typicode.com/\(path)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(Value.self, from: data)
    }
}
