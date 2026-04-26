# Secure Password Manager

Cross-platform Flutter client with a FastAPI + Python backend. One master password protects a local encrypted vault (PBKDF2 + Fernet + HMAC).

## Requirements

- **Python** 3.8+
- **Flutter** 3.x (for the desktop/mobile UI)
- Dependencies: see `requirements.txt` (Python) and `flutter/pubspec.yaml` (Dart)

## Install dependencies

From the repository root (installs the backend package and all Python dependencies):

```bash
pip install -e .
```

To install only the pinned set from the lock file without the editable package:

```bash
pip install -r requirements.txt
```

**Flutter (Dart) packages:**

```bash
cd flutter
flutter pub get
```


## Run

**Windows:** double-click or run `run.bat` from the repo root. It starts the API, then opens the app in **Microsoft Edge** (so you do not need Visual Studio for the Windows desktop toolchain). Ensure `flutter` is on your `PATH`, or keep the SDK under `Downloads\flutter_windows_*` so the script can find it.

For a **native Windows .exe** instead of the browser, install [Visual Studio](https://visualstudio.microsoft.com/downloads/) with the **Desktop development with C++** workload, then run: `cd flutter` and `flutter run -d windows`.

**Linux/macOS:** `chmod +x run.sh && ./run.sh` (adjust the Flutter device in `run.sh` if needed).

**API only** (for debugging) — if you used `pip install -e .`, you can run from any directory with no `PYTHONPATH`:

```bash
python -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

If the package is not installed, set `PYTHONPATH` to the `backend` folder (see `run.bat` / `run.sh`).

The Flutter app expects the API at `http://127.0.0.1:8000`.

## Project layout

```
password_manager/
├── backend/app/          # FastAPI app package (import as `app`)
│   ├── main.py
│   ├── paths.py
│   ├── core/             # vault, crypto, config
│   └── utils/
├── flutter/              # Flutter application
├── vault/                # Local encrypted data (created at runtime, gitignored)
├── config/               # Local settings (gitignored)
├── requirements.txt
├── pyproject.toml
└── README.md
```

## Flutter not found in the terminal?

- **PowerShell:** do not run `where flutter` — `where` is `Where-Object`, not a file search. Use **`where.exe flutter`** or **`Get-Command flutter`**. Or run **`. ./tools/init_flutter_path.ps1`** once per session to refresh `PATH` from the registry and prepend the SDK under `Downloads`.
- **cmd.exe:** `where flutter` is correct. **`run.bat`** calls **`tools/flutter_path.bat`** so Flutter is found even if the IDE terminal has a stale `PATH`.
- Restart the terminal (or Cursor) after changing Windows **User** `Path`.

## License

See `LICENSE`.
