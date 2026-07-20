# SwiftViewModel

A small base class for SwiftUI view models that lets you run async work safely, without data races and without retain cycles.

## The problem

The new `@Observable` macro turns your view model into a **class**. That is what makes observation work, but it also means your view model is a shared, mutable reference type. Two things go wrong as soon as you add async work:

1. **Threads.** If a background task reads or writes the view model while SwiftUI uses it on the main thread, you have a data race. Swift 6 strict concurrency will refuse to compile most of these, and the ones it lets through are still bugs.
2. **Retain cycles and lifetime.** A long-running task that captures `self` strongly keeps the view model alive after the screen is gone. Capture it weakly instead, and now every property access inside the task needs unwrapping.

## The idea

SwiftViewModel resolves both with one rule: **the background work never touches the real view model. It gets a copy.**

A call to `process` does three steps:

1. **Copy.** The view model clones itself on the main actor. The clone is a plain snapshot with no link back to the original.
2. **Compute.** Your closure runs off the main actor. It reads the snapshot, does the slow work (network, parsing, whatever), and returns a small update closure.
3. **Mutate in place.** The update closure runs back on the main actor, on the real view model. SwiftUI sees the change and updates the view.

Because the background work only sees a copy, there is nothing to race on. Because the tasks hold the view model weakly and the copy holds no reference to it at all, there is no retain cycle: when the view model goes away, `deinit` cancels every pending task and the update is simply never applied.

Copies come from [SwiftClonable](https://github.com/dsrenesanse/SwiftClonable). Its `@Clonable` macro writes a `copy()` method for you that deep-copies all stored properties.

## Install

Add the package in Xcode or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/dsrenesanse/SwiftViewModel", branch: "main")
]
```

Requires iOS 17 and Swift 6.

## Usage

Subclass `ViewModel` with your own type as the generic parameter, and mark the class `@Clonable`:

```swift
import SwiftUI
import SwiftViewModel
import SwiftClonable

@Observable
@Clonable
final class SearchViewModel: ViewModel<SearchViewModel> {
    var query = ""
    var results: [String] = []
    var isLoading = false

    func search() {
        isLoading = true
        process { snapshot in
            // Off the main actor. `snapshot` is a copy — read it freely,
            // the real view model can change meanwhile without conflict.
            let found = await SearchAPI.results(matching: snapshot.query)

            return { model in
                // Back on the main actor, on the real view model.
                model.results = found
                model.isLoading = false
            }
        }
    }
}
```

The view side is ordinary SwiftUI:

```swift
struct SearchView: View {
    @State private var model = SearchViewModel()

    var body: some View {
        List(model.results, id: \.self) { Text($0) }
            .searchable(text: $model.query)
            .onChange(of: model.query) { model.search() }
    }
}
```

## API

### `process`

Runs the computation right away. Several calls can run at the same time, and their updates apply in whatever order they finish. Use it when calls are independent of each other.

### `processSync`

Same shape as `process`, but each call waits for the previous `processSync` call to finish before it starts. Updates apply in the order you made the calls. Use it when order matters — for example, applying edits that build on each other.

```swift
func rename(to name: String) {
    processSync { snapshot in
        let saved = await api.rename(snapshot.id, to: name)
        return { model in
            model.name = saved.name
        }
    }
}
```

Both methods hold the view model weakly. If it is deallocated while the work runs, the work stops and the update never fires. Pending tasks are cancelled in `deinit`.

### `SyncProcessor`

A standalone actor for ordering tasks outside a view model. `process(action:)` awaits your task, then waits for every task that was already pending before returning the result. This lets tasks run concurrently while results still come back in submission order.

```swift
let processor = SyncProcessor()

let result = await processor.process(action: Task {
    await fetchPage(1)
})
```

## Rules to keep it safe

- Inside the computation closure, only read the snapshot. Do not smuggle the real view model in through a capture.
- Keep the update closure small: assign the results, nothing more. All the slow work belongs in the computation part.
- Properties of your view model must be deep-copyable. `@Clonable` handles stored properties, and copies nested `Clonable` objects too. Closures are carried over by reference, not copied.

## License

CC BY-ND 4.0. You can use the library, including commercially, with credit. You may not distribute modified versions. See [LICENSE](LICENSE) for details.
