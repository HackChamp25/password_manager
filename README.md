# 🔐 Secure Password Manager - Production Edition

A **world-class, production-ready** password manager with a modern cross-platform Flutter UI and secure Python backend. Store and manage all your passwords securely with just one master password. Built with enterprise-grade security and a professional user experience.

![Version](https://img.shields.io/badge/version-1.0.0-blue)
![Python](https://img.shields.io/badge/python-3.8%2B-green)
![Flutter](https://img.shields.io/badge/flutter-3.0%2B-blue)
![License](https://img.shields.io/badge/license-MIT-orange)

## 🎯 Features

### 🔒 Security Features
- ✅ **AES-256 Encryption**: Military-grade encryption for all data
- ✅ **PBKDF2 Key Derivation**: 600,000 iterations (industry standard)
- ✅ **HMAC Integrity**: Tamper detection for vault files
- ✅ **Encrypted Usernames**: Both usernames and passwords encrypted
- ✅ **Atomic Operations**: Prevents data corruption
- ✅ **Brute Force Protection**: Rate limiting with exponential backoff
- ✅ **Secure Memory**: Best-effort sensitive data clearing

### 💻 Application Features
- 📱 **Cross-Platform UI**: Modern Flutter interface for desktop and mobile
- 🔍 **Search & Filter**: Quickly find your credentials
- 🎲 **Password Generator**: Create strong, secure passwords instantly
- 📊 **Password Strength Checker**: Verify password quality
- 📋 **One-Click Copy**: Copy usernames and passwords to clipboard
- 🔐 **Auto-Lock**: Lock vault for security
- ✏️ **Edit & Delete**: Full CRUD operations for credentials
- 🌐 **REST API**: FastAPI backend for secure communication

## 🚀 Quick Start

### Installation

```bash
# Clone or download the repository
cd password_manager

# Install Python dependencies
pip install -r requirements.txt

# Install Flutter (if not already installed)
# Follow: https://flutter.dev/docs/get-started/install

# Navigate to Flutter app
cd flutter

# Install Flutter dependencies
flutter pub get

# Run the application
python run.bat  # Windows
# or
./run.sh        # Linux/macOS
```

**Or use the launcher scripts:**
- Windows: Double-click `run.bat` (starts both backend and frontend)
- Linux/macOS: `./run.sh` (starts both backend and frontend)

### First Run

1. Launch the application
2. Enter a **strong master password** (minimum 8 characters)
   - This is your only password to remember!
   - Make it strong and unique
3. Start adding your credentials

## 📸 Screenshots

### Login Screen
Enter your master password to unlock your secure vault.

### Main Interface
- **Left Panel**: List of all your stored credentials with search
- **Right Panel**: View and manage selected credential details
- **Menu Bar**: Export, import, and password generation tools

## 🔒 Security Architecture

The application uses a **client-server architecture** with secure REST API communication:

- **Backend (Python/FastAPI)**: Handles all cryptographic operations and vault storage
- **Frontend (Flutter)**: Provides modern UI and communicates with backend via HTTP

```
[Master Password] + [32-byte Salt] 
        │
        ▼
  ┌──────────────────────────────┐
  │  PBKDF2HMAC (SHA256, 600k)   │
  └──────────────────────────────┘
        │
        ▼
  [256-bit Master Key]
        │
        ├──► [Fernet Key] ──► Encrypt/Decrypt (AES-256)
        │
        └──► [HMAC Key] ──► Integrity Verification (HMAC-SHA256)
```

## 📋 Usage Guide

### Adding Credentials
1. Click **"➕ Add New"** button
2. Enter site name, username, and password
3. Use **"🎲 Generate"** to create a strong password
4. Click **"Save"**

### Viewing Credentials
1. Select a credential from the list
2. View details in the right panel
3. Check **"Show"** to reveal password
4. Click **"📋 Copy"** buttons to copy to clipboard

### Generating Passwords
1. Go to **Tools → Generate Password...**
2. Customize length and character types
3. Click **"🎲 Generate"**
4. Copy the generated password

### Exporting/Importing
- **File → Export Vault...**: Backup your vault to JSON
- **File → Import Vault...**: Restore from backup

## 🏗️ Project Structure

```
password_manager/
├── src/
│   ├── api/
│   │   └── main.py        # FastAPI backend server
│   ├── core/
│   │   ├── crypto.py      # Cryptographic functions
│   │   ├── vault.py       # Vault management
│   │   └── config.py      # Configuration
│   └── utils/
│       ├── password_generator.py  # Password generation
│       └── logger.py      # Logging
├── flutter/               # Flutter frontend application
│   ├── lib/
│   │   ├── main.dart      # Flutter app entry point
│   │   ├── models/        # Data models
│   │   ├── providers/     # State management
│   │   ├── screens/       # UI screens
│   │   └── utils/         # Utilities
│   ├── pubspec.yaml       # Flutter dependencies
│   └── ...
├── vault/                 # Encrypted vault storage
├── logs/                  # Application logs
├── config/                # Configuration files
├── requirements.txt        # Python dependencies
├── setup.py               # Package setup
└── readme.md             # This file
```

## 📚 Documentation

- **[SECURITY.md](SECURITY.md)**: Detailed security documentation
- **[INSTALL.md](INSTALL.md)**: Installation and troubleshooting guide

## ⚠️ Important Security Notes

- **Master Password**: Never share your master password with anyone
- **Backup**: Regularly export your vault as backup
- **Updates**: Keep the application updated
- **System Security**: Ensure your system is secure and malware-free
- **Local Only**: This is a local application - no cloud sync or network features

## 🛠️ Development

### Requirements
- Python 3.8+
- cryptography >= 41.0.0

### Building from Source

```bash
# Install in development mode
pip install -e .

# Run tests (if available)
python -m pytest
```

## 📝 License

MIT License - See LICENSE file for details

## 🙏 Acknowledgments

Built with security best practices inspired by:
- Bitwarden
- KeePass
- 1Password

## 🔄 Version History

- **v1.0.0** (Current): Production release with GUI, password generator, and full security features

---

**Made with ❤️ for secure password management**
