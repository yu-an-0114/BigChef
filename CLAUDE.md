# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ChefHelper (BigChef) is an iOS app that helps cooking beginners by integrating AI and AR technologies. The app recognizes ingredients and cooking equipment through AR scanning, then uses AI to recommend personalized recipes based on available materials and serving sizes.

**Tech Stack:** SwiftUI, UIKit, ARKit, Firebase, CoreML

## Build & Run Commands

### Building the Project
```bash
# Build the project
xcodebuild -project Chef/ChefHelper.xcodeproj -scheme ChefHelper -configuration Debug build

# Clean build
xcodebuild -project Chef/ChefHelper.xcodeproj -scheme ChefHelper clean build
```

### Running the App
Open `Chef/ChefHelper.xcodeproj` in Xcode and run using Cmd+R. The app uses the ChefHelper scheme.

### Dependencies
The project uses Swift Package Manager. Dependencies are resolved automatically by Xcode and include:
- Firebase (Auth, Analytics, etc.)
- Google Generative AI
- Kingfisher (image loading)
- Various Google/Firebase support libraries

## Configuration Setup

**IMPORTANT:** Before running the app, you must configure:

1. **Config.plist**: Copy `Chef/Config.plist.template` to `Chef/Config.plist` and set:
   - `API_BASE_URL`: Backend API server address
   - `API_VERSION`: API version (default: v1)
   - `DEBUG_MODE`: Debug logging toggle
   - `TIMEOUT_INTERVAL`: Network timeout

2. **Firebase**: The project includes `Chef/GoogleService-Info.plist` (tracked in git per current setup, but normally should be excluded).

Both `Config.plist` and `GoogleService-Info.plist` are in `.gitignore` to prevent committing secrets, though the current repo has GoogleService-Info.plist tracked.

## Architecture

### Coordinator Pattern (MVVM + Coordinator)
The app uses a **Coordinator-based navigation architecture** built on top of MVVM. This is a critical architectural pattern throughout the codebase.

**Navigation Flow:**
```
AppCoordinator (root)
├── MainTabCoordinator (main app interface)
│   ├── HomeCoordinator
│   ├── ScanningCoordinator → FoodRecognitionCoordinator
│   ├── RecipeCoordinator → RecipeRecommendationCoordinator
│   ├── HistoryCoordinator
│   └── CookCoordinator
└── AuthCoordinator (login flow)
```

**Key Files:**
- `Chef/Coordinators/Coordinator.swift` - Base protocol
- `Chef/Shared/Services/AppDelegate.swift` - App entry point, creates AppCoordinator
- `Chef/ChefHelper/ChefHelperApp.swift` - SwiftUI app (returns EmptyView, navigation handled by AppCoordinator)
- `Chef/Coordinators/AppCoordinator.swift` - Root coordinator, manages auth state and switches between AuthCoordinator and MainTabCoordinator
- `Chef/Coordinators/MainTabCoordinator.swift` - Tab-based navigation with child coordinators

**Coordinator Responsibilities:**
- Coordinators own `UINavigationController` and manage child coordinators
- All coordinators are `@MainActor` for UI thread safety
- Navigation between features is handled by parent coordinators calling child coordinator methods
- Child coordinators are added/removed using `addChildCoordinator()` / `removeChildCoordinator()`

### Directory Structure

```
Chef/
├── Features/              # Feature modules (by screen/domain)
│   ├── Home/             # Home tab
│   ├── Scanning/         # Recipe scanning entry
│   ├── FoodRecognition/  # AR ingredient/equipment recognition
│   ├── RecipeRecommendation/  # AI recipe suggestions
│   ├── Recipe/           # Recipe browsing
│   ├── Cooking/          # Step-by-step cooking guidance
│   ├── DishDetail/       # Recipe detail view
│   ├── Favorites/        # Saved recipes
│   ├── History/          # Cooking history
│   ├── Settings/         # App settings
│   └── Authentication/   # Login/signup
├── Coordinators/         # Navigation coordinators (one per feature)
├── Shared/
│   ├── Services/         # Network, API, Firebase services
│   ├── Models/           # Data models (User, Recipe, AR models)
│   ├── Component/        # Reusable UI components
│   ├── Utils/            # Utilities
│   ├── Extensions/       # Swift extensions
│   └── Views/            # Shared views
├── Routing/              # Router protocols and implementations
├── AR/                   # AR-specific code (ARKit, CoreML, animations)
│   ├── Animation/        # AR animations
│   ├── model/            # 3D models for AR
│   ├── CookDetect.mlmodel  # CoreML model for object detection
│   ├── CookingARView.swift  # Main AR view
│   └── ObjectDetect.swift   # Object detection logic
├── Utilities/            # App-wide utilities
└── ChefHelper/           # App entry point
    ├── ChefHelperApp.swift  # @main app (delegates to AppDelegate)
    └── Info.plist
```

### Key Services

**Network Layer** (`Chef/Shared/Services/`):
- `NetworkSwevice.swift` [sic] - Core networking service (note: typo in filename)
- `RecipeService.swift` - Recipe CRUD operations
- `RecipeRecommendationService.swift` - AI recipe recommendation
- `FoodRecognitionService.swift` - Image-based food recognition
- `IngredientRecognitionService.swift` - Ingredient detection
- `CookQAService.swift` - Cooking Q&A assistance
- `UserService.swift` - User management
- `ImageUploder.swift` [sic] - Image upload (note: typo in filename)

**Models** (`Chef/Shared/Models/`):
- `RecipeModels.swift` - Recipe, Ingredient, Step structures
- `User.swift` - User model
- `CookQARecipeContext.swift` - Cooking context for Q&A
- `ARSimulatorModels.swift` - AR simulation models

### AR & CoreML Integration

**AR Cooking Guidance:**
- `Chef/AR/CookingARView.swift` - Main AR interface for step-by-step cooking
- `Chef/AR/ObjectDetect.swift` - Real-time object detection
- `Chef/AR/CookDetect.mlmodel` - CoreML model for detecting cooking tools/ingredients (~32MB)
- `Chef/AR/AnimationManger.swift` - Manages AR animations and visual feedback
- `Chef/AR/HandGestureController.swift` - Hand gesture recognition

The AR system overlays cooking instructions and recognizes when users complete steps by detecting ingredients and tools in the camera view.

## API Integration

Base URL configured in `Config.plist` as `API_BASE_URL`.

**Endpoints:**
- `{API_BASE_URL}/api/v1/recipes` - Recipe listing
- `{API_BASE_URL}/api/v1/favorites` - User favorites
- `{API_BASE_URL}/api/v1/auth/login` - Authentication

Services handle API communication with timeout configured via `TIMEOUT_INTERVAL` in Config.plist.

## Firebase Integration

Firebase is initialized in `AppDelegate.application(_:didFinishLaunchingWithOptions:)` via `FirebaseApp.configure()`.

**Current Auth Flow:**
The `AppCoordinator.start()` method currently bypasses authentication and goes directly to `MainTabCoordinator` regardless of auth state (see lines 41-43 in AppCoordinator.swift). The auth flow code is commented out but available.

## Important Notes

1. **Entry Point:** Unlike typical SwiftUI apps, this app uses UIKit window management via `AppDelegate` conforming to `UIWindowSceneDelegate`. The coordinator pattern starts in `AppDelegate.scene(_:willConnectTo:options:)`.

2. **Coordinators are @MainActor:** All coordinator operations must run on the main thread for UI safety.

3. **Feature Isolation:** Each feature module (Home, Recipe, Scanning, etc.) has its own coordinator. To add navigation between features, coordinate through parent coordinators (usually MainTabCoordinator or AppCoordinator).

4. **AR Testing:** AR features require a physical device with ARKit support. Simulator testing uses mock data from `ARSimulatorModels.swift`.

5. **Typos in Filenames:** Be aware of `NetworkSwevice.swift` and `ImageUploder.swift` - these typos exist in the codebase.

6. **Language:** The app is primarily in Traditional Chinese (zh-TW). UI strings and comments are in Chinese.
