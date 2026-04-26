# 🔐 Secure Password Manager - Flutter Edition

A **world-class, production-ready password manager** built with Flutter and Dart. Store and manage all your passwords securely with just one master password. Features end-to-end encryption, beautiful modern UI, and comprehensive password management tools.

## ✨ Features

- **🔐 Military-Grade Encryption**: AES-256 encryption for all stored credentials
- **🔑 Master Password Protection**: Secure your entire vault with one strong master password
- **🎨 Beautiful Modern UI**: Premium dark theme with intuitive interface
- **🎲 Password Generator**: Create strong, cryptographically secure passwords instantly
- **📚 Credential Management**: Add, edit, search, and organize passwords
- **💾 Local Storage**: All data stored locally using encrypted SharedPreferences
- **🔒 Auto-Lock**: Automatically lock vault after inactivity
- **📋 One-Click Copy**: Securely copy usernames and passwords to clipboard
- **⚡ Fast & Responsive**: Built with Flutter for smooth performance
- **🛡️ Security Features**: Password strength checker, duplicate detection, secure deletion

## 🚀 Getting Started

### Prerequisites

- **Flutter SDK** 3.0.0 or higher
- **Dart** 3.0.0 or higher
- **Android Studio** or **VS Code** with Flutter extension
- **iOS** development tools (for macOS/iOS builds)

### Installation

1. **Clone the repository**
```bash
cd d:\Cybersecurity\projects\password_manager_flutter
```

2. **Install dependencies**
```bash
flutter pub get
```

3. **Run the app (Desktop - Windows, macOS, Linux)**
```bash
# For Windows
flutter run -d windows

# For macOS
flutter run -d macos

# For Linux
flutter run -d linux
```

4. **Run on Android**
```bash
flutter run -d android
```

5. **Run on iOS** (macOS only)
```bash
flutter run -d ios
```

## 📱 App Structure

```
lib/
├── main.dart                 # App entry point & theme configuration
├── models/
│   └── credential.dart      # Credential data model
├── providers/
│   └── vault_provider.dart  # State management using Provider
├── screens/
│   ├── login_screen.dart    # Login/Master password screen
│   ├── home_screen.dart     # Main credentials vault screen
│   ├── add_credential_screen.dart    # Add new credential
│   └── edit_credential_screen.dart   # Edit existing credential
└── utils/
    └── crypto_utils.dart    # Encryption & password generation utilities
```

## 🎨 UI Design

The app features a **premium dark theme** with:
- **Color Palette**: Deep navy background (#0f172a), cyan accent (#00d9ff), purple secondary (#7c3aed)
- **Layout**: Responsive split-view design (desktop) and mobile-optimized layouts
- **Components**: Modern cards, smooth animations, intuitive interactions
- **Typography**: Clean, professional Segoe UI font family

## 🔐 Security Architecture

### Master Password Flow
1. User sets a strong master password on first launch
2. Password is processed through PBKDF2-like derivation (1000 iterations)
3. Derived key is used for AES-256 encryption
4. All credentials are encrypted using this key
5. Master password is never stored, only verified

### Credential Storage
- All credentials stored locally using **SharedPreferences**
- Each credential encrypted individually with AES-256
- HMAC for integrity verification
- Automatic secure deletion on lock

## 🎮 Usage

### First Time Setup
1. Launch the app
2. Enter a **strong master password** (minimum 8 characters)
3. Confirm the password strength indicator reaches "Strong" or higher
4. Click "Set New Password"

### Unlocking the Vault
1. Enter your master password
2. Click "Unlock Vault"
3. Your credentials are decrypted and displayed

### Managing Credentials
- **Add**: Click "Add" button → Fill in site, username, password → Save
- **Search**: Use the search bar to find credentials by site or username
- **Edit**: Select a credential → Click "Edit" → Modify → Update
- **Delete**: Select a credential → Click "Delete" → Confirm
- **Generate Password**: Click "Generate" in add/edit screens for random password

### Password Generator
- Customize length (8-128 characters)
- Include/exclude uppercase, lowercase, digits, symbols
- Real-time strength indicator
- One-click copy to clipboard

### Lock Vault
- Click the lock icon in the header
- Vault is automatically cleared from memory
- Click "Unlock" to access credentials again

### Reset Vault
- If you forget your master password, use "Reset Vault"
- ⚠️ **Warning**: This permanently deletes all stored credentials
- After reset, create a new master password

## 📊 Password Strength Scoring

The app evaluates password strength based on:
- Length (8, 12, 16+ characters)
- Character variety (uppercase, lowercase, digits, symbols)
- Overall entropy

**Strength Levels**:
- **Very Weak** (0-20): Red
- **Weak** (20-40): Orange
- **Moderate** (40-60): Amber
- **Strong** (60-80): Light Green
- **Very Strong** (80-100): Green

## 🛠️ Development

### Building for Release

**Android APK**
```bash
flutter build apk --release
```

**iOS App**
```bash
flutter build ios --release
```

**Windows Executable**
```bash
flutter build windows --release
```

### Running Tests
```bash
flutter test
```

### Code Analysis
```bash
flutter analyze
```

## 📋 Feature Roadmap

### Current Features (v1.0.0)
- ✅ Master password authentication
- ✅ Credential CRUD operations
- ✅ Local encryption storage
- ✅ Password generation
- ✅ Search functionality
- ✅ Auto-lock on inactivity
- ✅ Password strength checker

### Planned Features (v1.1.0)
- 🔄 Cloud backup & sync
- 🌐 Export/Import vault
- 📊 Security audit report
- 🔔 Breach notifications
- 👥 Multi-device sync
- 🗑️ Trash/Recovery bin

## 🔒 Security Considerations

### ✅ What's Protected
- Credentials encrypted with AES-256
- Master password never stored
- Passwords cleared from memory on lock
- Local storage only (no cloud)

### ⚠️ Limitations
- Master password recovery not possible (by design)
- Backup should be encrypted separately
- Device security depends on OS encryption
- Screen sharing could expose unencrypted credentials

## 📝 License

This project is part of the Secure Password Manager suite.

## 🤝 Contributing

To contribute improvements:
1. Create a feature branch
2. Make your changes
3. Test thoroughly
4. Submit a pull request

## 📞 Support

For issues, questions, or suggestions:
- Check the README and documentation
- Review the code comments
- Test on the latest Flutter stable channel

## 🎉 Made with ❤️

Built as a production-ready password manager with focus on security, usability, and beautiful design.

---

**Now replacing Tkinter completely with this premium Flutter app!** 🚀
