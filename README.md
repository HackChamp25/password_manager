# Secure Password Manager

**Shippable desktop product:** a **single Flutter** app (native window on Windows, Linux, macOS). The **vault and all cryptography run inside the app** — no local Python or HTTP server is required for end users. Encrypted data is stored under the OS **application data** path (e.g. `%APPDATA%\...` on Windows) in a `SecurePasswordManager/vault` folder with the same file format as the optional reference Python backend (`salt.salt`, `verify.key`, `vault.json`).

The `backend/` tree remains an optional **Python reference** and a **dev** REST API (`backend_dev_server.bat`) for migration testing or future sync features, but **the retail app does not depend on it.**

---

## How the app works (end-to-end)

1. The user runs **one** executable (after `flutter build` / MSIX install). The UI asks for a **master password**.
2. The app **derives keys** (PBKDF2) and **unlocks** a `LocalVaultManager` in memory. Nothing is sent over the network; there is no `localhost` API in the default product build.
3. **Credentials** are read and written to disk through **Fernet-encrypted** fields and an **HMAC** on the whole vault JSON, matching the design below.

**Store packaging:** from `flutter/`, run `flutter build windows` for a normal installer folder, or `dart run msix:create` (see `msix` in `pubspec.yaml`) to produce an **MSIX** for Microsoft Store–style distribution (you will replace `identity_name` and signing with your real publisher when you are ready to publish).

---

## Core cryptographic logic (in-app, mirrors `backend/app/core/`)

The implementation is in `flutter/lib/core/local_vault/` and follows the same rules as `crypto.py` and `vault.py` for on-disk compatibility.

### 1) Key derivation (master password → keys)

- A **32-byte salt** is stored in **`salt.salt`**, created with a **CSPRNG** (Dart `Random.secure`).
- **PBKDF2-HMAC-SHA256**, **600,000** iterations → **32-byte** key material, then the same string encoding as Python for **Fernet** and the integrity step.
- **Integrity** key for the vault file: **SHA-256** of `HMAC_KEY_DERIVATION` (ASCII) + the same URL-safe key string Python uses, then **HMAC-SHA256** over the inner JSON for tamper detection.

### 2) `verify.key`

- Fernet-encrypted fixed plaintext `VERIFY_MASTER_KEY_2024` to validate the master password on unlock.

### 3) Storing entries

- **Site names** are clear-text keys; **username** and **password** are **Fernet-encrypted** strings in JSON.
- **Atomic writes** for vault files; repeated wrong password attempts are slowed down (same idea as the Python `VaultManager`).

### 4) UI-only helpers

`lib/utils/crypto_utils.dart` (strength meter, generator) has **no** access to the vault; it is presentation-only.

---

## Requirements

- **Flutter** 3.x and the **Windows** (or Linux / macOS) **desktop** toolchain: on Windows, [Visual Studio](https://visualstudio.microsoft.com/downloads/) with **“Desktop development with C++”** is required to build the native shell.
- **Optional (developers only):** Python 3.8+ and `pip install -e .` or `pip install -r requirements.txt` if you use the reference API in `backend/`.

## Install (developers)

**Flutter app (required for everyone building the product):**

```bash
cd flutter
flutter pub get
```

**Python backend (optional):**

```bash
pip install -e .
```

## Run

**From the repository root, `run.bat`** only starts the **Flutter Windows** desktop app (`flutter run -d windows`). It does **not** start Python.

**Release build (one folder to ship):**

```bash
cd flutter
flutter build windows --release
```

**MSIX (edit `msix_config` in `pubspec.yaml` for your real publisher ID, then):**

```bash
cd flutter
dart run msix:create
```

**Optional Python API** (dev / compatibility testing): `backend_dev_server.bat` after `pip install -e .` (default port `18080`).

## Project layout

```
password_manager/
├── flutter/lib/
│   ├── core/local_vault/  # Production vault + crypto (PBKDF2, Fernet, HMAC)
│   ├── providers/
│   ├── screens/
│   └── ...
├── backend/app/          # Optional reference + dev API (not required to run the app)
├── tools/                 # Path helpers for Flutter on Windows
├── run.bat                # Launches desktop app only
├── backend_dev_server.bat # Optional Python API
└── pyproject.toml
```

End-user data is **not** stored in this repo; it lives under the OS app support directory.

## Flutter not found in the terminal?

- **PowerShell:** do not run `where flutter` — `where` is `Where-Object`, not a file search. Use **`where.exe flutter`** or **`Get-Command flutter`**. Or run **`. ./tools/init_flutter_path.ps1`** once per session to refresh `PATH` from the registry and prepend the SDK under `Downloads`.
- **cmd.exe:** `where flutter` is correct. **`run.bat`** calls **`tools/flutter_path.bat`** so Flutter is found even if the IDE terminal has a stale `PATH`.
- Restart the terminal (or Cursor) after changing Windows **User** `Path`.

## License

See `LICENSE`.
