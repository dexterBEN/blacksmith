  # Blacksmith

A Proof of Concep(POC) to test building application with the game engine (GODOT)[https://godotengine.org/fr/].

I'm using the package (godot_dart)[https://github.com/fuzzybinary/godot_dart]

---

## 🎯 Project Context & Objectives

The main goals of this project are:

- Build an **interactive isometric grid** where resources can be placed dynamically
- Use a **clean front architecture** (UI → BLoC → Repository → Backend)
- Expose a **modular cloud backend API**
- Execute **real cloud operations** (currently: Google Cloud Storage bucket creation)
- Validate a **portable development workflow using devcontainers**
- Prepare a foundation for **multi-cloud support (GCP / AWS / Azure)**

This project serves both as:
- A **technical proof of concept**
- A **long-term experimentation platform** for cloud + frontend + system integration

---

## 🧱 Global Architecture Overview

Blacksmith follows a layered architecture:


