---
name: ios-mvvm
description: >
  Enforces MVVM architecture for iOS feature modules. Use this skill whenever
  the user is adding, editing, reviewing, or generating code in a module designated
  as MVVM. Triggers on: "add a screen", "create a view", "new feature in MVVM module",
  "generate ViewModel", "MVVM screen", or any code generation/review task in an MVVM module.
  Strictly enforces layer boundaries — no business logic in Views, no UIKit in ViewModels.
---

# iOS MVVM Architecture Skill

## Module Contract

This module uses **MVVM (Model-View-ViewModel)**. All code generated or reviewed
must respect the rules below. Violating layer boundaries is a hard error, not a warning.

---

## Layer Structure

```
Feature/
├── Model/
│   ├── FeatureItem.swift          # Plain data structs/enums, no logic
│   └── FeatureError.swift
├── ViewModel/
│   └── FeatureViewModel.swift     # All business + presentation logic lives here
├── View/
│   ├── FeatureView.swift          # SwiftUI view, binds to ViewModel only
│   └── FeatureSubview.swift
└── Service/                       # Optional: networking/persistence abstraction
    └── FeatureService.swift
```

---

## Hard Rules

### Model
- Plain Swift structs or enums only
- No imports of UIKit, SwiftUI, or Combine in Model files
- No network or persistence logic
- `Codable`, `Equatable`, `Hashable` conformances are fine

### ViewModel
- Must be a `final class` or `@Observable` struct
- Owns all state: `@Published` properties (Combine) or `@Observable` (Swift 5.9+)
- Calls Services — **never** calls network/DB directly
- No UIKit imports (`import UIKit` = immediate flag)
- No SwiftUI imports (exception: `ObservableObject` conformance only)
- All async work uses `async/await` with `@MainActor` annotation
- Inject dependencies via initializer — no singletons inside ViewModel

```swift
// ✅ Correct
@MainActor
final class FeatureViewModel: ObservableObject {
    @Published private(set) var items: [FeatureItem] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let service: FeatureServiceProtocol

    init(service: FeatureServiceProtocol) {
        self.service = service
    }

    func loadItems() async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await service.fetchItems()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

### View
- SwiftUI only — no UIKit unless wrapping via `UIViewRepresentable`
- Reads state from ViewModel, never owns business logic
- No direct Service or network calls
- No `@State` for data that belongs in ViewModel (UI-only state like focus is fine)
- Pass ViewModel via `@StateObject` (owner) or `@ObservedObject` (child)

```swift
// ✅ Correct
struct FeatureView: View {
    @StateObject private var viewModel: FeatureViewModel

    var body: some View {
        List(viewModel.items) { item in
            FeatureRowView(item: item)
        }
        .task { await viewModel.loadItems() }
        .overlay { if viewModel.isLoading { ProgressView() } }
    }
}
```

### Service
- Protocol-first: always define a `FeatureServiceProtocol`
- Implementation conforms to protocol
- Injected into ViewModel — never instantiated inside ViewModel

---

## Testing Expectations
- ViewModel: unit-tested with a mock `FeatureServiceProtocol`
- View: snapshot tests or SwiftUI previews — no logic to unit test
- Service: integration tests or mocked URLSession

---

## Code Review Checklist
When reviewing PRs in this module, flag:
- [ ] Business logic found in a View
- [ ] UIKit import in ViewModel
- [ ] ViewModel directly calling URLSession, CoreData, or UserDefaults
- [ ] Missing `@MainActor` on ViewModel with async state mutations
- [ ] Singleton accessed inside ViewModel (should be injected)
- [ ] `@State` used for data that should live in ViewModel
