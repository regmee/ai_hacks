---
name: ios-clean-arch
description: >
  Enforces Clean Architecture (Uncle Bob) for iOS feature modules. Use this skill
  whenever the user is generating, editing, or reviewing code in a Clean Architecture module.
  Triggers on: "add use case", "create repository", "new feature in clean arch module",
  "domain layer", "data layer", "presentation layer", or any code task in a Clean Arch module.
  The dependency rule is absolute: outer layers depend on inner layers, never the reverse.
  Domain layer must have zero framework imports.
---

# iOS Clean Architecture Skill

## Module Contract

This module uses **Clean Architecture**. The **Dependency Rule** is non-negotiable:
source code dependencies point **inward only**.

```
  ┌─────────────────────────────┐
  │      Presentation Layer     │  ← ViewModels, Views
  │  ┌───────────────────────┐  │
  │  │     Domain Layer      │  │  ← UseCases, Entities, Repository Protocols
  │  │  ┌─────────────────┐  │  │
  │  │  │   (nothing)     │  │  │  ← Domain imports NOTHING
  │  │  └─────────────────┘  │  │
  │  └───────────────────────┘  │
  │      Data Layer             │  ← Repository Implementations, DTOs, API clients
  └─────────────────────────────┘
```

---

## Layer Structure

```
Feature/
├── Domain/                            # ← Zero framework imports. Pure Swift only.
│   ├── Entities/
│   │   └── FeatureItem.swift          # Core business models
│   ├── UseCases/
│   │   ├── FetchFeatureItemsUseCase.swift
│   │   └── UpdateFeatureItemUseCase.swift
│   └── Repositories/
│       └── FeatureRepositoryProtocol.swift   # Protocol only — no implementation
│
├── Data/                              # ← Implements Domain protocols
│   ├── Repositories/
│   │   └── FeatureRepositoryImpl.swift
│   ├── DataSources/
│   │   ├── FeatureRemoteDataSource.swift
│   │   └── FeatureLocalDataSource.swift
│   └── DTOs/
│       └── FeatureItemDTO.swift        # API/DB models — mapped to Domain entities
│
├── Presentation/                      # ← Depends on Domain only, never Data
│   ├── ViewModel/
│   │   └── FeatureViewModel.swift
│   └── View/
│       └── FeatureView.swift
│
└── DI/
    └── FeatureAssembly.swift          # Wires everything together
```

---

## Hard Rules

### Domain Layer
- **Zero framework imports** — no UIKit, SwiftUI, Combine, Foundation networking, CoreData
- `import Foundation` is allowed only for value types (UUID, Date, etc.)
- Entities are plain Swift structs/enums
- UseCases are structs or final classes with a single `execute()` method
- Repository protocols defined here — implementations live in Data

```swift
// ✅ Correct Domain UseCase
struct FetchFeatureItemsUseCase {
    private let repository: FeatureRepositoryProtocol

    init(repository: FeatureRepositoryProtocol) {
        self.repository = repository
    }

    func execute() async throws -> [FeatureItem] {
        try await repository.fetchItems()
    }
}

// ✅ Correct Repository Protocol (Domain layer)
protocol FeatureRepositoryProtocol {
    func fetchItems() async throws -> [FeatureItem]
    func save(_ item: FeatureItem) async throws
}
```

### Data Layer
- Implements `FeatureRepositoryProtocol` from Domain
- Contains DTOs — always map DTOs → Domain Entities before returning
- **Never expose DTOs to Presentation or Domain**
- Can import: Networking libs, CoreData, SwiftData, Alamofire, etc.
- No business logic here — data transformation only

```swift
// ✅ Correct Repository Implementation
final class FeatureRepositoryImpl: FeatureRepositoryProtocol {
    private let remoteDataSource: FeatureRemoteDataSourceProtocol
    private let localDataSource: FeatureLocalDataSourceProtocol

    init(remote: FeatureRemoteDataSourceProtocol, local: FeatureLocalDataSourceProtocol) {
        self.remoteDataSource = remote
        self.localDataSource = local
    }

    func fetchItems() async throws -> [FeatureItem] {
        let dtos = try await remoteDataSource.getItems()
        return dtos.map { $0.toDomain() }   // ← Always map to Domain entity
    }
}

// ❌ Wrong — returning DTO to caller, or adding business logic in repository
```

### Presentation Layer
- ViewModels call UseCases — **never** Repository implementations directly
- No `import` of Data layer types
- ViewModel owns state (`@Published` or `@Observable`)
- `@MainActor` required on ViewModels

```swift
// ✅ Correct ViewModel
@MainActor
final class FeatureViewModel: ObservableObject {
    @Published private(set) var items: [FeatureItem] = []

    private let fetchItemsUseCase: FetchFeatureItemsUseCase  // ← UseCase, not Repository

    init(fetchItemsUseCase: FetchFeatureItemsUseCase) {
        self.fetchItemsUseCase = fetchItemsUseCase
    }

    func loadItems() async {
        items = (try? await fetchItemsUseCase.execute()) ?? []
    }
}

// ❌ Wrong — ViewModel holding a reference to FeatureRepositoryImpl
```

### DI / Assembly
- All wiring happens in `FeatureAssembly` or equivalent
- No `init()` calls to concrete types outside the assembly
- Use constructor injection throughout

---

## Testing Expectations
- **Domain**: pure unit tests — no mocks of frameworks needed
- **Data**: mock DataSources, test DTO mapping
- **Presentation**: mock UseCases, test ViewModel state transitions
- **Integration**: wire real layers together in integration tests

---

## Code Review Checklist
- [ ] Domain layer has any UIKit/SwiftUI/Combine/CoreData import → hard reject
- [ ] DTO leaking into Presentation or Domain layer
- [ ] ViewModel holds a concrete Repository (not UseCase)
- [ ] Business logic found in Repository implementation
- [ ] Data layer type imported in Presentation layer
- [ ] Missing DTO → Entity mapping in Repository
- [ ] Concrete type instantiated outside Assembly
