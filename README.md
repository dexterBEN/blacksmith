  # Blacksmith

A Proof of Concep(POC) to test building application with the game engine [GODOT](https://godotengine.org/fr/).

I'm using the package [godot_dart](https://github.com/fuzzybinary/godot_dart)

---

## 🎯 Project Context & Objectives

The main goals of this project are:

- Build an **interactive isometric grid** where resources can be placed dynamically
- Expose a **modular cloud backend API**
- Execute **real cloud operations** (currently: Google Cloud Storage bucket creation)
- Validate a **portable development workflow using devcontainers**

---

## 🧱 Global Architecture Overview

<img width="1024" height="1536" alt="image" src="https://github.com/user-attachments/assets/fabe8b5e-746d-4cfc-a46f-41fc0b10e33c" />

## 🐳 Devcontainers

Both frontend and backend are fully containerized using **VS Code devcontainers**:

### Frontend Devcontainer
- Dart SDK
- Godot integration
- GetIt / build_runner
- Portable across Linux / Windows / WSL / VM

### Backend Devcontainer
- .NET 8 SDK
- Google Cloud SDK
- Environment variables:
  - `ASPNETCORE_URLS`
  - `GOOGLE_APPLICATION_CREDENTIALS`
- Automatic dependency installation through `postCreateCommand`

This ensures:
- Identical environments across machines
- No local dependency pollution
- Easy onboarding for new contributors


```plantuml

@startuml
title Blacksmith - Resource Model (Initial)

skinparam classAttributeIconSize 0
skinparam shadowing false

' =========================
' Enums
' =========================
enum ResourceType {
  Database
  VirtualMachine
  Docker
  VPN
  Storage
  Other
}

enum CloudProvider {
  GCP
  AWS
  Azure
}

enum CloudServiceKind {
  Storage
  Compute
  Database
  Network
  Other
}

' =========================
' Core Entity
' =========================
class Resource {
  +id: UUID
  +name: String
  +type: ResourceType
  +positionX: int
  +positionY: int
  +createdAt: DateTime
}

' =========================
' Cloud Extension (0..1)
' =========================
class CloudResource {
  +resourceId: UUID  <<PK, FK>>
  +provider: CloudProvider
  +serviceKind: CloudServiceKind
  +accountOrProjectId: String
  +region: String
  +externalId: String
  +createdAt: DateTime
}

' Relationship: a Resource may have 0..1 CloudResource extension
Resource "1" o-- "0..1" CloudResource : cloudExtension

note right of CloudResource
  Extension table:
  Only exists if the Resource is cloud-managed.
  resourceId is both PK and FK to Resource.id
end note

note bottom of Resource
  positionX / positionY are grid coordinates.
  type is an enum (Option A).
end note

@enduml
```



