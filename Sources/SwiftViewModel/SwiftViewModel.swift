//
//  SwiftViewModel.swift
//  SwiftViewModel
//
//  Created by Dan on 2026/02/16.
//

import SwiftClonable
import SwiftUI

@MainActor
open class ViewModel<T: Clonable> {

    @ObservationIgnored
    private var pending: Task<Void, Never>?

    @ObservationIgnored
    private var pendingStorage = [UUID: Task<Void, Never>]()

    public init() {
        if (self as! T).isCopy {
            return
        }
        initialize()
    }

    open func initialize() {
        
    }

    open func deinitialize() {

    }

    public func process(
        computation: @escaping (_ state: T) async -> (_ state: T) -> Void
    ) {
        let key = UUID()
        let task = Task { [weak self] in
            guard let copy = (self as? T)?.copy() else { return }
            let update = await computation(copy)
            self?.pendingStorage.removeValue(forKey: key)
            if self != nil {
                update(self as! T)
            }
        }
        pendingStorage[key] = task
    }

    public func processSync(
        computation: @escaping (_ state: T) async -> (_ state: T) -> Void
    ) {
        let key = UUID()
        let old = pending
        pending = Task { [weak self] in
            await old?.value
            guard let copy = (self as? T)?.copy() else { return }
            let update = await computation(copy)
            self?.pendingStorage.removeValue(forKey: key)
            if self != nil {
                update(self as! T)
            }
        }
        pendingStorage[key] = pending
    }

    isolated deinit {
        if (self as! T).isCopy {
            return
        }
        pending?.cancel()
        let storage = pendingStorage
        for task in storage.values {
            task.cancel()
        }
        deinitialize()
    }
}

public actor SyncProcessor {
    public init() {}

    private var pending = [UUID: Task<Sendable?, Never>]()

    public func process<T>(action: Task<T, Never>) async -> T? {
        let key = UUID()
        let capturedPendings = Array(pending.values)
        let task = Task<Sendable?, Never> { [weak self] in
            guard self != nil else { return nil }
            let result = await action.value
            guard self != nil else { return nil }
            for pending in capturedPendings {
                let _ = await pending.value
                guard self != nil else { return nil }
            }
            return result
        }
        pending[key] = task
        let result = await task.value
        pending.removeValue(forKey: key)
        return (result as? T)
    }
}
