# Cipher Nest — Architecture & Cybersecurity Interview Guide

A single, deep document covering the full architecture, every cryptographic
choice, the rationale behind each decision, and the interview questions you
should be ready to answer when you say *"I built a desktop password manager
with end-to-end encryption."*

> Read this top-to-bottom once. Then re-read sections **3 (Crypto Core)**,
> **4 (MDK Architecture)** and **12 (Interview Q&A)** the night before any
> security interview.

---

## Table of Contents

1. [Executive Summary / 60-second Pitch](#1-executive-summary--60-second-pitch)
2. [Threat Model](#2-threat-model)
3. [The Cryptographic Core](#3-the-cryptographic-core)
4. [The Master Data Key (MDK) Architecture](#4-the-master-data-key-mdk-architecture)
5. [On-disk File Layout](#5-on-disk-file-layout)
6. [Lifecycle Walkthrough](#6-lifecycle-walkthrough)
7. [Defense-in-Depth Beyond Crypto](#7-defense-in-depth-beyond-crypto)
8. [Native Windows Integration](#8-native-windows-integration)
9. [Code Tour — What Lives Where](#9-code-tour--what-lives-where)
10. [Why Flutter Desktop?](#10-why-flutter-desktop)
11. [What's NOT in Scope (Honest Tradeoffs)](#11-whats-not-in-scope-honest-tradeoffs)
12. [Cybersecurity Interview Q&A](#12-cybersecurity-interview-qa)
13. [Glossary](#13-glossary)

---

## 1. Executive Summary / 60-second Pitch

> **Cipher Nest** is a Windows desktop password manager built in Flutter
> (Dart) with a small native C++ runner. Every credential lives in a
> per-user encrypted file using **AES-256-GCM**. The encryption key is
> *never* the user's master password — instead, a random 32-byte
> **Master Data Key (MDK)** encrypts the vault, and the MDK itself is
> independently wrapped under three keys:
>
> - one derived from the **master password** via **PBKDF2-HMAC-SHA256**
>   with **600,000 iterations**;
> - one derived from a **24-word BIP-39 recovery phrase** via PBKDF2 with
>   **200,000 iterations**;
> - one optional **device key** unlocked through **Windows Hello**
>   (fingerprint / face / PIN) for fast quick-unlock.
>
> This **dual-wrap** design is the same pattern MetaMask and 1Password
> use — it makes password rotation, recovery and biometric unlock
> *non-destructive* operations on the underlying vault.
>
> The app is **zero-knowledge**: nothing leaves the machine, no telemetry,
> no cloud, no backend. Defense-in-depth includes brute-force backoff,
> best-effort memory zeroing of derived keys, clipboard auto-clear after
> 30–45 seconds, atomic file writes, OS-level dark mode, and a screen-
> capture protection flag.

---

## 2. Threat Model

Stating an explicit threat model is the single thing that separates a real
security project from a hobby toy. Be ready to recite this in interviews.

### In-scope adversaries

| Adversary | Defense |
|---|---|
| **Offline thief who steals the vault file(s)** | Files are AES-256-GCM ciphertexts. Brute-forcing the master password requires PBKDF2-600k per guess. |
| **Same-machine attacker without the master password** | Cannot decrypt without the password (or recovery phrase, or Hello consent + DPAPI-equivalent device gating). Reading raw vault files is useless. |
| **Casual shoulder-surfer / opportunistic copier** | Auto-lock, clipboard auto-clear, password masked by default. |
| **User who forgets the master password** | Can recover with the 24-word phrase non-destructively. The vault contents are preserved; only the password salt and password-wrap rotate. |
| **User who wipes / re-installs Windows but kept their phrase + backup file** | `.cnest` backup file + 24 words = full restore on any machine. |

### Out-of-scope (explicitly)

| Threat | Why we don't claim defense |
|---|---|
| **Active malware running as the same Windows user** | Once the vault is unlocked, MDK is in process memory. Any in-process attacker (DLL injection, debugger, keylogger, screen scraper that bypasses DWM flags) wins. This is fundamental for any local app. |
| **Hardware key extraction (cold boot, RAM dump on an unlocked machine)** | We do `bestEffortZero` on derived keys after use, but Dart objects can be moved by the GC. Strong defense requires HSM/TPM, which we leave to a future enhancement. |
| **Compromised OS (rootkit)** | If the OS is owned, every assumption breaks. |
| **User using the same weak master password elsewhere that leaks** | Nothing we can do — but the app warns about weak masters and shows a strength meter on creation. |
| **Quantum adversary** | AES-256 is *partially* resistant (Grover halves effective bits → 128-bit equivalent). PBKDF2-SHA256 is fine. We do not use post-quantum primitives. |

---

## 3. The Cryptographic Core

All primitives live in `flutter/lib/core/local_vault/local_crypto.dart`.

### 3.1 PBKDF2-HMAC-SHA256 — Key Stretching

> **What it is.** A *password-based key derivation function* defined in
> RFC 2898 / RFC 8018. It takes a low-entropy secret (a password) and a
> random salt, and runs HMAC-SHA256 thousands of times to produce a
> high-entropy fixed-length key.

```dart
const int pbkdf2Iterations       = 600_000;  // master password
const int phrasePbkdf2Iterations = 200_000;  // recovery phrase
```

Output length: **32 bytes** (256 bits) — exactly what AES-256 wants.

**Why so many iterations?**
The whole point of PBKDF2 is to make every guess *expensive*.

- 600,000 PBKDF2-HMAC-SHA256 iterations is the value 1Password chose in
  2023 and Bitwarden defaults to in 2024+. It costs roughly **300 ms on
  a modern CPU**, which is invisible to the user but turns a 10⁹ guesses/sec
  GPU attack into a 3,000 guesses/sec attack — six orders of magnitude
  worse for the attacker.
- 200,000 iterations is enough for the recovery phrase because the phrase
  itself already carries **264 bits of entropy** (24 words × log₂(2048) =
  24 × 11). PBKDF2 isn't trying to compensate for low entropy here; it's
  just acting as a uniform key derivation function.

**Why a salt?**

- A 32-byte random salt prevents pre-computed **rainbow table** attacks.
- It also ensures two users with the same password produce different
  derived keys.
- Salts are stored *in the clear* in `salt.salt` and `salt.phrase`. They're
  not secret — they just need to be unique per vault.

**Why not Argon2 / scrypt?**

You should mention this in interviews:

- **Argon2id** is theoretically better — it's memory-hard, which makes
  GPU/ASIC attacks far less effective. PBKDF2 is *only* CPU-hard.
- We picked PBKDF2 because:
  1. The PointyCastle Dart library has a battle-tested PBKDF2
     implementation. Argon2 wrappers in Dart are less mature.
  2. PBKDF2 is **FIPS 140-3 compliant**; many enterprise security reviews
     require FIPS-approved primitives.
  3. 600k iterations is competitive in practice with the recommended
     Argon2id parameters at our memory budget.
- A future enhancement would be to migrate to Argon2id and bump the
  password-wrap version (the format is `gcm1.<nonce>.<ct+tag>` — the
  `gcm1` prefix is exactly the kind of versioning hook that lets us
  add `argon2id-aesgcm1` later without breaking old vaults).

### 3.2 AES-256-GCM — Authenticated Encryption (AEAD)

> **What it is.** AES (Advanced Encryption Standard) in **Galois/Counter
> Mode**. AES is a 128-bit block cipher; in counter mode each block is
> XOR'd against `AES(key, counter ‖ nonce)`. GCM adds a Galois-field
> universal hash (GHASH) that produces a **128-bit authentication tag**
> over the ciphertext + associated data. That tag is verified on decrypt.

```dart
String encryptVaultSecret(Uint8List raw32Key, Uint8List plaintext) {
  if (raw32Key.length != 32) throw StateError('AES-256-GCM key must be 32 bytes');
  final nonce  = _secureRandomBytes(12);                            // 96-bit IV
  final cipher = GCMBlockCipher(AESEngine())
    ..init(true, AEADParameters(KeyParameter(raw32Key), 128, nonce, Uint8List(0)));
  final out = cipher.process(plaintext);
  return 'gcm1.${_b64UrlNoPad(nonce)}.${_b64UrlNoPad(out)}';
}
```

**Why GCM and not CBC, CTR, ECB?**

| Mode | Verdict | Why |
|---|---|---|
| **ECB** | NEVER | Same plaintext block → same ciphertext block. Trivial pattern leakage. The famous "ECB penguin." |
| **CBC** | Bad on its own | Confidentiality only. No integrity → vulnerable to **padding oracle attacks** (Vaudenay 2002). Needs a separate HMAC ("encrypt-then-MAC"), more code paths, more bugs. |
| **CTR** | Confidentiality only | Same problem as CBC: malleable ciphertext. Bit-flips in the ciphertext flip the same bits in the plaintext on decrypt. |
| **GCM** | ✅ AEAD | Confidentiality + integrity in one primitive. Hardware-accelerated (AES-NI + PCLMULQDQ). Standardized in NIST SP 800-38D. |

**Nonce / IV rules — get these right or fail interviews.**

- **96-bit (12-byte) nonce** is the GCM standard length; using anything
  else triggers a slower internal GHASH path.
- The nonce is generated with `Random.secure()` (CSPRNG: BCryptGenRandom
  on Windows under the hood) for **every** encryption. Never reuse a
  (key, nonce) pair under GCM — you completely break confidentiality
  *and* allow universal forgery (forbidden attack on GCM's GHASH).
- The nonce does not need to be secret — we ship it as plaintext with
  the ciphertext. It just needs to be unique.

**Why a 128-bit auth tag?**

- The tag is the second output of GCM. On decrypt, GCM recomputes the
  tag and compares it to the one in the token; mismatch → throws.
- 128 bits is the maximum and the recommended length. NIST allows 96/104/112,
  but truncated tags weaken authentication.
- With a 128-bit tag, the chance of a forged ciphertext being accepted is
  2⁻¹²⁸ — astronomical.

**Token format — `gcm1.<nonceB64Url>.<ct+tagB64Url>`**

- The leading `gcm1` is a *cryptographic version tag*. If we ever change
  the cipher, salt scheme, or KDF, we bump it (`gcm2`, `xchacha1`, etc.).
- During decrypt we sniff the prefix:
  - `gcm1.…` → AES-256-GCM path
  - anything else → Fernet legacy path (still supported for old vaults)
- Versioned crypto formats are a hallmark of *real* security software.
  Mention this in interviews.

### 3.3 Legacy Fernet Compatibility

The original prototype used Python's **Fernet** scheme (AES-128-CBC +
HMAC-SHA256, base64-encoded). We kept the decrypt path so existing
vaults still open, but every new write is GCM.

```dart
// Legacy Fernet compatibility for existing vaults.
final f = enc.Fernet(enc.Key(Uint8List.fromList(raw32Key)));
return Uint8List.fromList(f.decrypt(fernetStringToEncrypted(t), ttl: 86400 * 3650));
```

On the first successful unlock of a legacy vault, every entry is
re-encrypted to GCM in `_migrateLegacyEntryTokens` — opportunistic
crypto upgrade.

### 3.4 HMAC-SHA256 — Integrity (legacy holdover)

For Fernet vaults we also computed a separate HMAC over the entire
`vault.json` payload to detect tampering of the file. With AES-GCM,
**every entry is already authenticated** by the GCM tag, so this layer
is redundant but kept for backward compatibility.

The integrity key is derived from the MDK so it doesn't need its own
storage:

```dart
// SHA256("HMAC_KEY_DERIVATION" + base64UrlSafe(MDK))
Uint8List deriveIntegrityKeyBytes(Uint8List raw32) { … }
```

Domain separation via the literal `"HMAC_KEY_DERIVATION"` ensures the
HMAC key cannot collide with any other key derived from the MDK.

### 3.5 BIP-39 Recovery Phrases

> **What it is.** Bitcoin Improvement Proposal 39: a standardized
> wordlist of 2048 carefully-chosen English words (no four-letter
> prefixes overlap, no easily-confused pairs, all common dictionary
> words). Used by every major wallet on earth.

- **Wordlist:** `flutter/lib/core/local_vault/bip39_wordlist.dart` — the
  canonical 2048 words from the BIP-39 spec.
- **Length:** 24 words → 24 × log₂(2048) = **264 bits of entropy**. (The
  formal BIP-39 spec packs 256 bits of entropy + 8-bit checksum into
  24 words; we don't store a checksum because we re-validate the phrase
  by trying to decrypt `wrap.phrase`, which is itself an AES-GCM
  authenticated check.)
- **Generation:** `Random.secure()` picks each word uniformly. CSPRNG
  on Windows is `BCryptGenRandom` (the OS RNG), so this is genuinely
  random.
- **Normalization:** Whitespace is collapsed, words lowercased, leading/
  trailing spaces trimmed before hashing. This makes the phrase forgiving
  to user typing (extra spaces, copy-paste artifacts, casing).

```dart
String normalizeRecoveryPhrase(String input) {
  final tokens = input.trim().toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  return tokens.join(' ');
}
```

**Why a phrase instead of a random hex / base64 string?**

- 264 bits of entropy is the same whether you express it as 24 words or
  66 hex characters, but **humans can transcribe words far more
  reliably**. This is a security property: a phrase you write down and
  read back without errors is more secure than a hex string you mistype.
- Words also self-checksum: if a word isn't in the dictionary, we reject
  the entire phrase before even touching crypto.

---

## 4. The Master Data Key (MDK) Architecture

This is the single most important diagram to be able to draw on a
whiteboard in an interview. **Practice it.**

```
                 ┌─────────────────────────────┐
   Master Pwd  ──▶ PBKDF2(600k, salt.salt) ──▶ K_pwd ──┐
                 └─────────────────────────────┘       │
                                                       ▼
                                            ┌──────────────────────┐
                                            │ AES-GCM(K_pwd, MDK)  │ ─▶ wrap.pwd
                                            └──────────────────────┘
                                                       ▲
                 ┌──────────────────────────────┐      │
   24-word    ──▶ PBKDF2(200k, salt.phrase) ──▶ K_phrase ─┐
   phrase       └──────────────────────────────┘          │
                                                          ▼
                                            ┌──────────────────────┐
                                            │ AES-GCM(K_phrase,MDK)│ ─▶ wrap.phrase
                                            └──────────────────────┘
                                                       ▲
                 ┌──────────────────────────┐          │
   Windows    ──▶ unlocks K_device (random) ──────────┐│
   Hello       └──────────────────────────┘            │
                                                       ▼
                                            ┌──────────────────────┐
                                            │ AES-GCM(K_device,MDK)│ ─▶ wrap.device
                                            └──────────────────────┘

                  ┌────────────────────────────────────────┐
                  │       MDK (random 32 bytes)            │
                  │   actually encrypts every credential   │
                  └────────────────────────────────────────┘
                                  │
                                  ▼
       AES-GCM(MDK, vault.json bytes) ─────▶ vault.json on disk
       AES-GCM(MDK, "VERIFY_MASTER_KEY_2024") ─▶ verify.key
```

### Why MDK exists (the killer interview question)

**Q: "Why don't you just encrypt the vault directly with PBKDF2(password)?"**

If you did that:
- **Password rotation = re-encrypt the entire vault.** Every entry must
  be decrypted with the old key and re-encrypted with the new one.
  Slow. Risky if interrupted (partial state).
- **Recovery is impossible without copying the password somewhere.**
  You'd have to either store the password in a "second slot" (copying a
  secret = bad) or destroy the vault on forget.
- **Adding biometric = re-encrypt the entire vault again.**

With the MDK indirection layer:
- The MDK never changes. The vault data on disk *never re-encrypts*
  during password / phrase / biometric changes.
- "Change password" = generate a new salt, derive a new K_pwd, write
  one new `wrap.pwd` file. Microseconds.
- "Recover with phrase" = decrypt `wrap.phrase` with K_phrase → MDK →
  re-wrap MDK with a fresh K_pwd. Vault data untouched.
- "Enable Hello" = generate K_device, write `wrap.device`. Vault data
  untouched.

This is the **same pattern used by**:
- **MetaMask / Ethereum wallets** — seed phrase wraps the wallet key.
- **1Password** — Secret Key + master password jointly derive the
  account-unlock key, which wraps the per-vault keys.
- **Bitwarden** — master key wraps the user-symmetric-key, which wraps
  cipher keys.
- **iOS / macOS Keychain** — class keys wrap data keys, which wrap
  individual items. Each protection class has different "wrap unwrap"
  rules.
- **LUKS (Linux disk encryption)** — multiple key slots, each wrapping
  the master key, supporting password change + multiple unlock methods.

> When asked "tell me about the design of your encryption layer," **lead
> with this**. It demonstrates you understand cryptographic engineering,
> not just primitives.

### The verify token

```dart
const _verifyPlain = 'VERIFY_MASTER_KEY_2024';
…
final verifyToken = encryptVaultSecret(mdk, utf8.encode(_verifyPlain));
```

`verify.key` is a known plaintext encrypted under the MDK. After any
unwrap, we decrypt `verify.key` with the candidate MDK and compare
constant-time against `_verifyPlain` (`ListEquality<int>().equals`).

**Why?** Because GCM throws on tag mismatch but a wrong key combined
with a corrupted ciphertext could in theory throw the same error as a
corrupted file. The verify token gives us a clean, unambiguous "key was
correct" signal.

The constant-time comparison via `ListEquality.equals` is the standard
Dart way to avoid timing leaks on the verify check.

---

## 5. On-disk File Layout

All paths resolve from `LocalVaultPaths.vaultRoot()`:
- **Windows:** `%LOCALAPPDATA%\SecurePasswordManager\vault\`
- **macOS:**   `~/Library/Application Support/SecurePasswordManager/vault/`
- **Linux:**   `$XDG_DATA_HOME/SecurePasswordManager/vault/` (or `~/.local/share/...`)

```
SecurePasswordManager/
├── settings.json          # plain JSON: theme, auto-lock minutes,
│                          # phrase_confirmed_at timestamp
└── vault/
    ├── salt.salt          # 32 random bytes — PBKDF2 salt for password
    ├── salt.phrase        # 32 random bytes — PBKDF2 salt for recovery phrase
    ├── wrap.pwd           # "gcm1.<nonce>.<ct+tag>" : AES-GCM(K_pwd, MDK)
    ├── wrap.phrase        # "gcm1.<nonce>.<ct+tag>" : AES-GCM(K_phrase, MDK)
    ├── verify.key         # "gcm1.<nonce>.<ct+tag>" : AES-GCM(MDK, "VERIFY_MASTER_KEY_2024")
    ├── vault.json         # the encrypted credential list (per-entry encrypted)
    ├── key.device         # OPTIONAL — 32 random bytes (K_device) if Hello enrolled
    ├── wrap.device        # OPTIONAL — "gcm1.<nonce>.<ct+tag>" : AES-GCM(K_device, MDK)
    └── intrusion.log      # plaintext JSON: failure counter + event history
                           #   (metadata only — no secrets, written before unlock)
```

### vault.json structure (after decrypting fields)

```json
{
  "version": 2,
  "entries": [
    {
      "site": "github.com",
      "username": "akashjoshi",
      "password": "gcm1.<nonce>.<ct+tag>",   // each field encrypted with MDK
      "url": "gcm1.<nonce>.<ct+tag>",
      "notes": "gcm1.<nonce>.<ct+tag>",
      "favorite": false,
      "category": "Development",

      // OPTIONAL — only present when the user has opted into built-in
      // 2FA for this entry. The base32 TOTP shared secret is encrypted
      // exactly like the password.
      "totpSecret": "gcm1.<nonce>.<ct+tag>",
      "totpDigits": 6,
      "totpPeriod": 30,
      "totpAlgorithm": "SHA1",
      "totpIssuer": "GitHub"
    }
  ],
  "hmac": "<base64 hmac-sha256 over the entries blob>"  // legacy belt-and-braces
}
```

> The TOTP shared secret receives the same AES-256-GCM treatment as
> the password. It is **never** written to disk in plaintext, never
> logged, and is wiped from memory on lock alongside the rest of the
> decrypted vault.

### Atomic writes

Every file write goes through `atomicWriteBytes`:

```dart
final tmp = File('.<name>.tmp.<microseconds>');
await tmp.writeAsBytes(data, flush: true);   // fsync
if (await f.exists()) await f.delete();
await tmp.rename(f.path);                    // atomic on the same volume
```

**Why?** Power-loss safety. If the machine crashes mid-write, you either
have the old file or the new file — never a half-written corrupt one.
This is the same pattern SQLite, Git, and modern databases use.

---

## 6. Lifecycle Walkthrough

### 6.1 First-time setup (`setupNewVault`)

1. Validate `password.length >= 8`.
2. Generate a fresh **MDK** = 32 random bytes.
3. Generate a fresh **password salt** (32 bytes).
4. Generate a fresh **phrase salt** (32 bytes).
5. Generate a fresh **24-word recovery phrase**.
6. Derive `K_pwd = PBKDF2(password, salt.salt, 600k)`.
7. Derive `K_phrase = PBKDF2(phrase, salt.phrase, 200k)`.
8. Compute and write five files: `salt.salt`, `salt.phrase`, `wrap.pwd`,
   `wrap.phrase`, `verify.key`.
9. Zero the K_pwd and K_phrase byte arrays from memory
   (`bestEffortZero`).
10. Store the MDK in memory; vault is now unlocked.
11. **Return the recovery phrase to the UI**, which forces the user
    through a "type back word #N" challenge before continuing.

### 6.2 Unlock with master password (`unlock`)

1. Rate-limit check: ≥ 5 failures triggers exponential backoff
   `2^attempts` seconds.
2. Read `salt.salt`, derive `K_pwd`.
3. If `wrap.pwd` exists (modern vault):
   - `MDK = AES-GCM-decrypt(K_pwd, wrap.pwd)`. GCM throws on bad tag →
     incorrect password.
4. Else (legacy vault, no wraps):
   - Treat `K_pwd` itself as the MDK candidate.
   - Verify against `verify.key`.
   - On success, generate a phrase, build the wraps, **upgrade the vault
     in place**, and surface the freshly-generated phrase to the UI for
     the user to write down.
5. Verify MDK against `verify.key`.
6. Zero `K_pwd`. Vault is unlocked.

### 6.3 Unlock with Windows Hello (`unlockWithBiometric`)

1. UI calls `BiometricService.authenticate()` → Dart method channel
   invokes the C++ runner → WinRT `UserConsentVerifier.RequestVerification
   Async` → Windows shows the Hello prompt.
2. On user consent (fingerprint / face / PIN match):
   - Read `key.device` (raw K_device bytes).
   - `MDK = AES-GCM-decrypt(K_device, wrap.device)`.
   - Verify against `verify.key`.
3. Vault unlocks without typing the master password.

### 6.4 Recover with phrase (`recoverWithPhrase`)

1. Validate the phrase is exactly 24 words and every word is in the
   BIP-39 dictionary.
2. Derive `K_phrase = PBKDF2(phrase, salt.phrase, 200k)`.
3. `MDK = AES-GCM-decrypt(K_phrase, wrap.phrase)`. Wrong phrase ⇒ tag
   mismatch ⇒ "Phrase does not unlock this vault."
4. Generate a brand-new password salt; derive new `K_pwd` from the new
   master password.
5. `wrap.pwd ← AES-GCM(K_pwd, MDK)`. Overwrite atomically.
6. Vault becomes unlocked under the new password. **All entries are
   preserved** because we never re-encrypted them — we only re-wrapped
   the MDK.

### 6.5 Rotate recovery phrase (`rotateRecoveryPhrase`)

1. Vault must be unlocked (we have the MDK).
2. Generate a new phrase + new phrase salt.
3. Derive `K_phrase_new`.
4. `wrap.phrase ← AES-GCM(K_phrase_new, MDK)`. Overwrite.
5. Show the new phrase via the same one-time reveal + challenge flow.

### 6.6 Backup export (`exportEncryptedBackup`)

Produces a single self-contained `.cnest` JSON document:

```json
{
  "magic":      "CNEST-BACKUP-1",
  "createdAt":  "2026-04-29T...Z",
  "phraseSalt": "<base64>",
  "phraseWrap": "gcm1.<nonce>.<ct+tag>",
  "vaultBlob":  "gcm1.<nonce>.<ct+tag>"   // AES-GCM(MDK, vault.json bytes), fresh nonce
}
```

The vault data is **re-encrypted with a fresh nonce** when you export,
giving each backup snapshot independent IV-uniqueness. Anyone with the
24-word phrase can restore on any machine.

### 6.7 Backup import (`importEncryptedBackup`)

1. Parse the JSON, check the `magic`.
2. Derive `K_phrase` from the supplied phrase + the phrase salt that
   ships *inside* the backup file.
3. Unwrap MDK from `phraseWrap`.
4. Decrypt `vaultBlob` with MDK.
5. Generate fresh password salt, derive `K_pwd` from the user-supplied
   new password, wrap MDK, write a fresh `verify.key`.
6. Write all files atomically. Vault is now restored and unlocked under
   the new password.

### 6.8 Lock & auto-lock

`AppSettingsProvider` runs a `Timer` with a configurable idle window
(default 5 minutes). `SessionGuard` listens for any pointer event in the
app and calls `bumpActivity()` to reset the timer.

When the timer fires, it invokes `VaultProvider.lock()` which calls
`bestEffortZero` on the MDK and integrity key, sets them to `null`, and
returns to the login screen.

### 6.9 Legacy migration

A "legacy" vault is one created by the older Fernet-only prototype —
it has `salt.salt` and `verify.key` but no `wrap.pwd`. The unlock path
detects this and:

1. Validates the password against the verify token.
2. Generates a phrase, wraps MDK two ways.
3. Upgrades each entry from Fernet to AES-GCM in
   `_migrateLegacyEntryTokens`.
4. Surfaces the freshly-generated phrase to the UI.

This migration is **transparent** — the user never sees an upgrade
dialog, just sees their vault open and a "save your new recovery
phrase" prompt.

---

## 7. Defense-in-Depth Beyond Crypto

Crypto alone doesn't make a secure app. These are the operational
defenses that turn the algorithm into a product.

### 7.1 Brute-force throttling

Two layers — **per-session rate limiting** (in-memory, defends against
fast online guessing) and **persistent lockout** (on-disk, defends
against patient cross-session brute force).

#### Per-session rate limit

```dart
const _maxLoginAttempts = 5;
const _loginDelayBase = 2;

bool _checkRateLimit() {
  if (_failedAttempts < _maxLoginAttempts) return false;
  final pow = (_failedAttempts - _maxLoginAttempts).clamp(0, 5);
  final waitMs = 1000 * _loginDelayBase * (1 << pow);   // 2,4,8,16,32,64 sec
  return DateTime.now().millisecondsSinceEpoch - _lastAttemptMs < waitMs;
}
```

After 5 failed unlocks within a single app session, the user must wait
2s → 4s → 8s → 16s → 32s → 64s on each successive failure. This is on
top of the PBKDF2 cost. Resets when the app restarts.

#### Persistent lockout (intrusion log driven)

The in-memory counter is cleared on app restart, so it cannot defend
against an attacker who scripts repeated process launches. We also
maintain a **persistent failure counter** in `vault/intrusion.log` —
plaintext JSON metadata only, no secrets, writable before the vault is
unlocked.

```text
const int lockoutThreshold = 10;
```

Once `cumulativeFailures >= 10` (since the last successful unlock), the
password unlock path is **sealed off** entirely: `unlock()` returns
immediately without even running PBKDF2. The user must use one of:

- the **24-word recovery phrase** (proves possession of the original
  setup secret),
- **Windows Hello** if previously enrolled (proves the legitimate user
  is at the keyboard via biometric consent),
- **backup restore** with the phrase + a new password.

Each of these resets the cumulative counter and emits a
`lockout_cleared` event into the log. The login screen renders a red
"Vault sealed" banner and disables the password field while the
lockout is active.

### 7.1b Intrusion log (failed-unlock forensics)

`flutter/lib/services/intrusion_log.dart` records every unlock outcome
with a UTC timestamp. The log is plaintext JSON because:

1. It must be writable **before the vault is unlocked** (we can't
   encrypt it under the MDK).
2. It contains **metadata only** — outcomes, timestamps, methods,
   reasons. There is no secret to leak.
3. An attacker reading it learns "this person typed the wrong password
   N times" — useless to them.

```jsonc
// vault/intrusion.log
{
  "version": 1,
  "cumulativeFailures": 7,            // resets on any successful unlock
  "totalFailuresSinceUnlock": 7,      // same, captured at next success
  "previousFailuresAtLastUnlock": 3,  // shown in the post-unlock snackbar
  "lastSuccessfulUnlockAt": "2026-04-29T08:55:12Z",
  "lockoutActive": false,
  "events": [
    { "ts": "...", "kind": "fail",            "reason": "wrong_password" },
    { "ts": "...", "kind": "fail",            "reason": "wrong_password" },
    { "ts": "...", "kind": "lockout_engaged"                              },
    { "ts": "...", "kind": "success",         "method": "phrase"          },
    { "ts": "...", "kind": "lockout_cleared"                              }
  ]
}
```

Events are FIFO-capped at 100 to keep the file bounded.

The Security center page renders the log with timestamps, methods, and
failure reasons; the legitimate user can clear it after unlock.

After a successful unlock we surface a red snackbar **only** if there
were prior failed attempts:
*"Heads up: 3 failed unlock attempt(s) since you were last here."*

#### Why this is the right shape (interview ammunition)

We deliberately rejected three "sexier" alternatives that come up in
brainstorms:

| Alternative | Why we rejected it |
|---|---|
| **Snap webcam photo of attacker + SMS to owner's phone** | Covert biometric capture has GDPR / CCPA / wiretap exposure in many jurisdictions. SMS requires a paid provider whose API key would have to ship in the binary — trivially extractable, your account drained by spammers. Embeds a phone number (sensitive PII). And the camera is often physically covered or in use, so it fails silently. |
| **Cloud-based "suspicious login" alert (à la Google account)** | Requires an always-on server, breaks the headline zero-knowledge / no-network claim, and fundamentally changes the threat model. |
| **Wipe the vault after N failures** | A trivial denial-of-service vector — the attacker doesn't even need to know your password to destroy your data. |

The intrusion-log + lockout design accomplishes the real goal ("be
aware of intrusion attempts and stop them") without any of those
problems. It is **fully offline, fully local, requires no third-party
account, has no embedded secrets, and cannot be weaponized for DoS**.

### 7.2 Memory hygiene (`bestEffortZero`)

```dart
void bestEffortZero(Uint8List? b) {
  if (b == null) return;
  b.fillRange(0, b.length, 0);
}
```

Called after every use of K_pwd, K_phrase, K_device. Be honest about its
limits in interviews:

- This zeroes the **bytes of that specific Uint8List**.
- Dart's GC may have already moved or copied the bytes elsewhere.
- The plain-text password string itself lives in the `TextField` widget's
  internal buffer until the controller is cleared.
- **Real defense requires the OS-level secure memory APIs**
  (`VirtualLock` + `RtlSecureZeroMemory` on Windows, `mlock` + explicit
  zero on Linux). We don't claim to do this; we say "best effort" in the
  function name on purpose.

### 7.3 Clipboard auto-clear

```dart
Future<void> copyAndScheduleClear(String text, {
  Duration clearAfter = const Duration(seconds: 45),
}) async {
  await Clipboard.setData(ClipboardData(text: text));
  _clearTimer?.cancel();
  _clearTimer = Timer(clearAfter, () async {
    final current = await Clipboard.getData('text/plain');
    if (current?.text == text) {
      await Clipboard.setData(const ClipboardData(text: ''));
    }
  });
}
```

Note the **only-clear-if-still-ours** check — if the user copied
something else after, we leave it alone. Recovery phrases use a 30s
window; passwords use 45s.

### 7.4 Auto-lock on inactivity

Configurable from Settings: 1, 5, 15, 30, 60 minutes, or Never. Default
5 minutes. Resets on any pointer event via `SessionGuard`.

### 7.5 Constant-time comparison on the verify token

`ListEquality<int>().equals(dec, expectedBytes)` runs a fixed-time loop
under the hood. Using `==` on lists or strings would early-return on the
first mismatching byte, leaking the position of the first wrong byte
through timing — not relevant for `verify.key` *in this app* (we don't
expose a network API), but it's the right habit and worth mentioning.

### 7.6 Atomic, fsync'd writes

Already covered in §5. Prevents corruption on power loss / crash.

### 7.7 Screenshot / screen-share protection

`flutter/windows/runner/win32_window.cpp` exposes
`EnableScreenCaptureProtection(hwnd)` which calls
`SetWindowDisplayAffinity(hwnd, WDA_EXCLUDEFROMCAPTURE)` when enabled.
This makes the window appear black in screenshots and during Zoom /
Teams screen-share. Currently behind a build-time flag
(`kEnableScreenCaptureProtection`), since aggressive enforcement breaks
remote support workflows. Easy toggle.

### 7.8 Zero telemetry, no network

The application binary contains no HTTP client wired to any analytics
endpoint. The MSIX manifest declares `internetClient` capability for
the optional dev-time backend, but the shipped flow never makes a
network call.

### 7.9 Built-in TOTP / 2FA (RFC 6238)

Cipher Nest ships its own RFC 6238 TOTP generator. When the user
opts in for a credential, the entry stores the shared base32 secret
and the rotating 6-digit code is shown right next to the password.

**Why ship our own and not require an external authenticator?**

The realistic alternative for most users is *no* second factor at
all — adoption of separate authenticator apps is famously low. By
making TOTP available one tap away from the password we materially
raise the ceiling of accounts that actually have 2FA, without sending
the secret anywhere off the machine.

**What's implemented:**

- `lib/services/totp.dart` — pure-Dart RFC 6238 + RFC 4226 +
  base32 codec + `otpauth://` URI parser. No network, no plugins.
  Defaults: SHA-1, 6 digits, 30-second period (matches
  Google Authenticator / Authy / Microsoft Auth / 1Password).
- The shared secret is encrypted with AES-256-GCM under the **same
  MDK** as the password, with the same per-field random nonce. It is
  never written in plaintext to disk and never logged.
- The Add/Edit credential screens accept either a raw base32 secret
  or a full `otpauth://totp/Issuer:account?secret=...&...` URI; if a
  URI is pasted we auto-extract digits/period/algorithm/issuer.
- The vault detail panel renders a copy-able rotating code with a
  drain-down progress arc; color shifts to amber in the last 5s so
  the user knows the code is about to roll.
- The Security Center surfaces 2FA coverage as an info card and
  explicitly tells the user to keep the second factor for their most
  critical accounts (primary email, banking, crypto exchange) on a
  separate device.

**The single-basket caveat (and why we still ship this):**

Storing both factors in one vault means an attacker who recovers BOTH
the encrypted vault file AND the master password owns both factors
for those accounts. That is a real downgrade compared to a hardware
key. We address it with three safeguards:

1. A **first-time disclosure dialog** the moment the user enables
   TOTP on any entry — it explains the trade-off plainly and asks
   for explicit acknowledgement (persisted in
   `app_settings.totp_disclosure_shown`).
2. A **persistent insight** in the Security Center listing how many
   accounts share the same basket and recommending an external
   factor for high-value accounts.
3. The full MDK architecture from §4 — a stolen vault file is still
   gibberish without the master password (or recovery phrase or
   device key for biometric).

We chose **SHA-1** as the default HMAC because TOTP truncates to 6
digits anyway, hash collision/preimage resistance is irrelevant in
this construction, and SHA-1 is the only algorithm 99% of consumer
services actually emit. SHA-256 / SHA-512 are supported and selected
automatically when an `otpauth://` URI specifies them.

---

## 8. Native Windows Integration

### 8.1 Windows Hello via WinRT (no plugin)

Flutter's plugin ecosystem is great on mobile but problematic on Windows
desktop where adding *any* native plugin requires Windows Developer Mode
(symlink support) on the build machine. To avoid that friction we
implemented Windows Hello directly in the runner:

- `windows/runner/biometric_channel.h/.cpp` — registers a Flutter method
  channel called `cipher_nest/biometric` and exposes:
  - `isAvailable()` → `bool`
  - `authenticate({reason: String})` → `bool`
- Implementation calls
  `winrt::Windows::Security::Credentials::UI::UserConsentVerifier::CheckAvailabilityAsync()`
  and `RequestVerificationAsync(reason)` on a worker `std::thread` so
  the platform thread doesn't block while Hello shows its UI.
- `WindowsApp.lib` is linked from the runner's `CMakeLists.txt`.
- The Dart side (`lib/services/biometric_service.dart`) is a thin
  wrapper around `MethodChannel`.

This is the same pattern the official `local_auth_windows` plugin uses
internally — we just inline it instead of taking the dependency.

### 8.2 Dark titlebar (DWM)

`win32_window.cpp` calls
`DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, …)` to make
the non-client area (titlebar, borders) match our dark theme. Without
this, Windows draws a stark white titlebar that breaks the design.

### 8.3 Window display affinity

`SetWindowDisplayAffinity` (see §7.7).

---

## 9. Code Tour — What Lives Where

```
flutter/lib/
├── main.dart                              — bootstrap, MultiProvider
├── theme/app_theme.dart                   — Material 3 theme tokens
│
├── core/local_vault/
│   ├── local_crypto.dart                  ★ PBKDF2, AES-GCM, helpers
│   ├── local_vault_paths.dart             — file path resolver
│   ├── local_vault_manager.dart           ★ MDK architecture, lifecycle
│   ├── recovery_phrase.dart               — BIP-39 generate/normalize/validate
│   └── bip39_wordlist.dart                — 2048 official BIP-39 words
│
├── providers/                             — ChangeNotifier state
│   ├── app_settings_provider.dart         — theme, auto-lock, phrase confirmed-at
│   └── vault_provider.dart                — UI-facing wrapper around vault manager
│
├── services/
│   ├── biometric_service.dart             — Dart side of the Hello channel
│   ├── secure_clipboard.dart              — copy + auto-clear
│   ├── intrusion_log.dart                 — persistent failed-unlock log + lockout
│   ├── totp.dart                          ★ RFC 6238 TOTP + base32 + otpauth parser
│   └── vault_insights.dart                — reuse / weak-password / 2FA coverage
│
├── models/credential.dart                 — Credential value object (incl. TOTP fields)
│
├── utils/crypto_utils.dart                — local password generator + strength meter
│
├── widgets/
│   ├── session_guard.dart                 — pointer listener → bumpActivity
│   ├── totp_code_field.dart               — rotating 6-digit code + drain ring
│   ├── totp_setup_section.dart            — Add/Edit "enable 2FA" section + disclosure
│   └── vault_lock_animation.dart          — login screen lock visual
│
└── screens/
    ├── login_screen.dart                  — entry UI, recovery flows, Hello chip
    ├── app_shell.dart                     — navigation rail / bar
    ├── vault_page.dart                    — credential list + detail + banner
    ├── add_credential_screen.dart
    ├── edit_credential_screen.dart
    ├── password_generator_page.dart
    ├── security_center_page.dart          — vault insights view
    └── settings_page.dart                 — Recovery & Backup, Hello, theme, auto-lock

flutter/windows/runner/
├── main.cpp                               — wWinMain
├── flutter_window.cpp/h                   — registers BiometricChannel
├── biometric_channel.cpp/h                ★ WinRT UserConsentVerifier bridge
├── win32_window.cpp/h                     — dark titlebar, screen capture flag
└── CMakeLists.txt                         — links WindowsApp.lib

backend/                                   — optional Python FastAPI reference
                                              (NOT shipped; for learning only)
```

★ = "memorize this file path" for the interview.

---

## 10. Why Flutter Desktop?

Be ready to defend the stack choice. Honest tradeoffs:

| Pro | Con |
|---|---|
| Single Dart codebase compiles to Windows / macOS / Linux | Larger binary than native (~30 MB) |
| Excellent rendering / animation = better UX than Electron | Plugin ecosystem on desktop is uneven |
| Strong typing, sound null safety, good crypto libs (PointyCastle, encrypt) | Need to drop into C++ for OS APIs (e.g. Hello) |
| AOT-compiled to native code → no JIT, no JS interpreter footprint | Hot reload only in debug |
| Material 3 + Cupertino out of the box → consistent UI | Custom titlebar / chrome tweaks need native code |

The choice was made because:
1. The threat model is *local data on a desktop machine* — Flutter
   compiles to a native binary that can read/write files via
   `dart:io`, no browser sandbox to fight.
2. Flutter's animation framework let us spend time on UX (lock
   animations, matrix-rain background, banner system) without
   building it pixel by pixel.
3. Cross-platform code reuse for the (optional) future macOS / Linux
   builds.

---

## 11. What's NOT in Scope (Honest Tradeoffs)

In an interview, **volunteering what your project doesn't do** is one
of the strongest signals of engineering maturity. Be ready with this
list:

- ❌ **No TPM/HSM-bound key.** K_device is just a file under per-user
  ACLs + Hello consent. A future enhancement is to wrap K_device with
  Windows DPAPI-NG (`NCRYPT_USE_VIRTUAL_ISOLATION_FLAG`) so it lives in
  a Virtualization-Based-Security-protected enclave. Not done yet.
- ❌ **No Argon2id.** PBKDF2-SHA256 is not memory-hard. (See §3.1.)
- ❌ **No FIDO2 / YubiKey.** Doable on Windows but requires CTAP2 over
  HID, which is a multi-day effort. Tracked as a future enhancement.
- ❌ **Memory zeroing is best-effort, not guaranteed.** Dart GC can
  copy/move bytes. (See §7.2.)
- ❌ **The vault file's existence is not hidden.** Disk forensics will
  always find `vault.json`. We protect *contents*, not *metadata*.
- ❌ **No browser autofill extension.** Out of scope for v1.
- ❌ **No cloud sync.** By design — this is a local-only zero-knowledge
  product.
- ❌ **No multi-user / sharing.** One vault per OS user.
- ❌ **No formal security audit.** A real product would commission one.

---

## 12. Cybersecurity Interview Q&A

This section is the gold. Practice answering each question out loud.

### A. Foundations

**Q1. Why don't you use the user's password directly as the AES key?**

Two reasons:
1. **Length / entropy.** AES-256 needs exactly 32 bytes of high-entropy
   key material. Human passwords are short and biased. A KDF stretches
   them into the right shape.
2. **Brute-force cost.** A KDF (PBKDF2 with 600k iterations) makes every
   guess expensive. If you used the password directly via a fast hash
   like SHA-256, an attacker with a GPU could try billions of guesses
   per second.

**Q2. Walk me through PBKDF2-HMAC-SHA256 in one minute.**

PBKDF2 takes (password, salt, iteration count, output length) and
applies HMAC-SHA256 in a chain: PRF₁ = HMAC(password, salt ‖ 0x00000001),
then PRFᵢ₊₁ = HMAC(password, PRFᵢ), and the output's first block is the
XOR of all PRFs. Each "block" of output costs (iterations) HMAC calls.
For a 32-byte output (one SHA-256 block) at 600k iterations, that's
600,000 HMAC-SHA256 invocations per password guess. Salt prevents
rainbow tables; iteration count tunes the cost.

**Q3. Why GCM instead of CBC + HMAC?**

GCM is an **AEAD** (Authenticated Encryption with Associated Data)
construction — confidentiality and integrity in one primitive. CBC
needs a separately-keyed HMAC (encrypt-then-MAC), which is two
implementations to get right and historically bug-prone. GCM is also
hardware-accelerated on every modern CPU via AES-NI + PCLMULQDQ, and
the spec is explicit (NIST SP 800-38D), giving fewer footguns.

**Q4. What is a nonce, and what happens if you reuse one?**

A nonce ("number used once") is the per-encryption value that mixes
into the cipher's keystream. In GCM specifically, it's 96 bits and goes
into the CTR-mode counter. Reusing a (key, nonce) pair under GCM:
- **Breaks confidentiality**: XOR of two ciphertexts = XOR of plaintexts,
  trivially recoverable.
- **Breaks authenticity**: with two messages under the same (K, N),
  GHASH's secret subkey H can be solved from the captured tags,
  enabling **universal forgery** of any future message under that K.
This is called the GCM "forbidden attack." We avoid it by generating
a fresh 12 random bytes for every encryption from `Random.secure()`.

**Q5. Could you have used a counter-based nonce instead of random?**

Yes — and at very high message rates (think IPsec / TLS) it's actually
preferred to avoid the birthday-bound risk of accidental collision in
random nonces. For a password manager that encrypts per credential
and per write (a few thousand times in the lifetime of the vault), a
random 96-bit nonce gives a collision probability of ~2⁻⁵⁰ even with
2¹⁵ encryptions, which is negligible.

**Q6. How is your salt different from a password "pepper"?**

A salt is **stored in plaintext alongside the hash** to prevent
precomputation attacks. A pepper is **kept secret** (e.g. in a server-
side config or HSM) and protects against database-only compromises.
We don't use a pepper because the threat model is "attacker has the
file" — there's no separate "secret" the attacker wouldn't have.

### B. The MDK Architecture

**Q7. Draw your key hierarchy on the whiteboard. Explain it.**

(Draw the diagram in §4.) Then explain: random MDK encrypts vault, MDK
is wrapped under K_pwd, K_phrase, optionally K_device. Password rotation
rewrites only `wrap.pwd`, never the vault data.

**Q8. What attack does the MDK design prevent that single-key wouldn't?**

It prevents:
- **Loss of data on password rotation interruption.** Single-key would
  need to re-encrypt every entry; MDK rotates one tiny file.
- **Lockout on forgotten password.** Single-key has no recovery.
- **Forced data loss when adding biometric.** Single-key would have to
  re-encrypt every entry under a new "combined" key.

It does **not** prevent any cryptanalytic attack on the underlying AES
or PBKDF2 — those guarantees are unchanged. The MDK design is about
**operational** security and key management.

**Q9. Why have a separate verify.key when GCM's auth tag already
authenticates everything?**

Two reasons:
1. **Unambiguous "key correct" signal.** A GCM tag failure could in
   principle come from a corrupt file or a wrong key. The verify token
   gives us a clean "decrypted to known plaintext → key is right"
   check.
2. **Bootstrapping the legacy migration.** Old (pre-MDK) vaults treated
   K_pwd as the MDK directly. The verify token is what we use to detect
   "this is a legacy vault" before we know whether to look for `wrap.pwd`.

**Q10. What if the user's recovery phrase leaks?**

They can rotate it from Settings → "Generate new recovery phrase." We
generate a fresh phrase + salt, derive a new K_phrase, and overwrite
`wrap.phrase`. The old phrase is now useless because it doesn't decrypt
the new wrap. This is again a one-file rewrite, not a vault re-encrypt.

**Q11. Why isn't the recovery phrase derived from the master password?**

Because they need to be **independent**. The whole point of recovery is
"I forgot my master password." If the phrase were derived from the
password, forgetting one means losing the other.

### C. Threat scenarios

**Q12. Attacker steals my vault folder. What do they need to break in?**

Either:
- the **master password** (subject to PBKDF2-600k cost per guess), or
- the **24-word phrase** (264 bits of entropy — astronomically harder
  than guessing the password), or
- access to the **same Windows user account** AND the ability to satisfy
  Windows Hello (fingerprint / face / PIN) — and even then, only on the
  same physical machine where K_device was generated, because they need
  the `key.device` file too.

**Q13. Quantify the brute-force cost.**

Suppose an attacker has a high-end GPU farm doing 10⁹ SHA-256 ops/sec.
Each PBKDF2-600k attempt costs ~600,000 SHA-256 ops, so ~1,667
guesses/sec on that hardware (we ignore HMAC's 2× factor for clarity).
A truly random 8-character alphanumeric (62⁸ ≈ 2 × 10¹⁴) would take
~3,800 years average. A 12-character one is centuries × millions.
Any *human-chosen* 8-char password is much weaker due to entropy bias —
which is why the strength meter in `crypto_utils.dart` exists.

**Q14. What if Windows Hello is bypassed?**

Hello consent gates the *read* of `key.device`. If an attacker bypasses
Hello (e.g. malware running as the user can call the same WinRT API),
they could load `key.device` and unwrap the MDK. **This is why biometric
is documented as convenience, not a security replacement.** The master
password and phrase remain the source of truth.

**Q15. Could a malicious extension/process read your decrypted MDK from
memory while the vault is unlocked?**

Yes — once unlocked, the MDK lives in the Dart heap. Any process with
`PROCESS_VM_READ` on our process (or DLL injection privileges) can read
it. This is fundamental for any local app and the same is true for
1Password, KeePass, etc. Mitigations are out of scope for a Dart app:
proper defense requires running the unlock in a separate, hardened
process or using a hardware-backed enclave.

**Q16. What's your defense against keylogging?**

Honestly: **none in our app.** A keylogger sees the master password.
Defense is at the OS level (Windows Hello-only login, hardware tokens).
This is a known limitation and applies to every password manager.

**Q17. Cold-boot attack on RAM?**

Same answer as Q15. We do `bestEffortZero` after derivation but the GC
may have copies. A cold-boot attack on an unlocked machine wins. Lock
the vault when leaving the machine — that's why auto-lock exists.

**Q18. What if the user picks "password123" as their master password?**

The strength meter (`CryptoUtils.checkPasswordStrength`) returns < 40 for
that, and the login screen blocks vault creation when strength < 40 with
"Password too weak. Use mixed case, numbers, and symbols." We don't
enforce a denylist (haveibeenpwned-style) because it would require
network access and we want the app to be fully offline.

### D. Implementation deep dives

**Q19. How do you prevent timing attacks on the password verify path?**

The two timing-sensitive comparisons are:
1. The GCM auth tag comparison — done internally by PointyCastle, which
   uses constant-time tag verification.
2. The `verify.key` plaintext comparison — done with
   `ListEquality<int>().equals(...)`, which iterates the full length
   without early return.

There's no online attack surface (no network endpoint), so timing leaks
are largely academic — but the discipline is right.

**Q20. How do you handle file corruption?**

- **Atomic writes** (write-tmp + rename) prevent half-writes.
- Each AES-GCM token has its own auth tag — corruption inside a token
  throws on decrypt, surfaced as a clean error to the UI.
- The HMAC over the vault payload (legacy carry-over) catches bit-flips
  in the JSON envelope.
- `verify.key` corruption means the user can't unlock; the recovery
  phrase still works because `wrap.phrase` lives in a different file.

**Q21. What happens if the user deletes `wrap.phrase`?**

`hasRecoveryPhrase()` returns false. The Recovery banner appears,
nudging the user to "Generate new recovery phrase" from Settings, which
regenerates `wrap.phrase` from the unlocked MDK.

**Q22. Why do you keep a separate `salt.salt` and `salt.phrase`?**

Two derivations, two iteration counts (600k vs 200k), two output keys.
Using one shared salt is fine cryptographically (the input secret
differs) but separating them keeps the architecture clean and makes
rotation independent: rotate the password ⇒ rotate `salt.salt`, rotate
the phrase ⇒ rotate `salt.phrase`.

**Q23. Why store K_device on disk in the clear?**

Because there's no portable, plugin-free way for a Dart desktop app to
talk to the Windows TPM. K_device's *confidentiality* on disk relies on
two things:
1. NTFS file ACLs scoped to the per-user `%LOCALAPPDATA%`.
2. Windows Hello consent gating the **moment of read** in our app.

This is honest convenience-grade biometric, not hardware-bound. We
documented it as such and the master-password / phrase paths are
unaffected.

**Q24. Walk me through what happens at app startup.**

`main()` → `WidgetsFlutterBinding.ensureInitialized()` → `runApp(MyApp)`.
`MyApp` builds a `MultiProvider` with `AppSettingsProvider` (loads
settings.json from disk) and `VaultProvider` (creates a new
`LocalVaultManager`, no decryption yet — vault locked). Conditional on
`vault.isUnlocked`, we render `LoginScreen` or `AppShell`. Login screen
fires `isInitialized()` to know whether to show "create" vs "unlock"
flow, and `BiometricService.isAvailable() + hasBiometricUnlock()` to
know whether to show the Hello quick-unlock chip.

**Q25. How does your auto-lock work when the user is using the keyboard
but not the mouse?**

`SessionGuard` only listens to `Listener.onPointerDown`. It does **not**
catch keyboard activity. This is a known limitation — for a real
product I'd add a `Focus` listener and `RawKeyboardListener` to also
bump activity on keystrokes. Worth volunteering this as a "thing I'd
improve" in interviews.

### E. Crypto trivia / depth

**Q26. What's the difference between AES-GCM and ChaCha20-Poly1305?**

Both are AEAD constructions with comparable security goals. ChaCha20 is
a stream cipher (no AES sboxes), Poly1305 is its authenticator.
- **AES-GCM** is faster on CPUs with AES-NI (every modern x86/ARM).
- **ChaCha20-Poly1305** is faster on chips without AES acceleration
  (some embedded ARM, older mobile).
- TLS 1.3 supports both. Modern protocols often pick AES-GCM for
  desktops and ChaCha20-Poly1305 for mobile.

We picked GCM because Windows desktops have AES-NI and PointyCastle's
GCM is mature.

**Q27. What's the IV / nonce for each AES-GCM encryption in your app?**

12 random bytes from `Random.secure()` for **every** encryption call.
We store the nonce as part of the token: `gcm1.<nonceB64>.<ctTagB64>`.
The receiver doesn't need it precomputed — it parses it out.

**Q28. How big is the GHASH key, and how is it derived?**

GHASH uses a 128-bit subkey H = AES_K(0¹²⁸) — i.e. AES-encrypt the
all-zero block under the encryption key. PointyCastle handles this
internally; we never touch H directly. Important to know that **H is
key-dependent**, which is why nonce reuse leaks H and breaks
authenticity.

**Q29. What if the user's clock is wrong? Does that affect anything?**

Only the legacy Fernet decryption path passes a `ttl` of 10 years to
keep old vaults openable regardless of clock skew. AES-GCM has no
timestamp — it's pure crypto, clock-independent. The
`recoveryPhraseConfirmedAt` reminder uses local time but that's UI
nudge, not security.

**Q30. Is your CSPRNG really cryptographically secure?**

`Random.secure()` in Dart wraps the OS CSPRNG:
- Windows: `BCryptGenRandom` (CNG)
- macOS / iOS: `SecRandomCopyBytes`
- Linux: `getrandom(2)` / `/dev/urandom`

These are the same entropy sources the OS uses for TLS. The Dart
documentation explicitly states `Random.secure()` is suitable for
cryptographic use; it'll throw if the OS RNG is unavailable.

### F. Product / engineering

**Q31. How would you scale this to add cloud sync without breaking
zero-knowledge?**

Encrypt everything client-side (we already do), then upload only:
- `vault.json` (already MDK-encrypted)
- `wrap.phrase` (already AES-GCM encrypted)
- `wrap.pwd` (already AES-GCM encrypted)

Never upload `key.device` (machine-specific) or the master password /
phrase. The cloud sees opaque ciphertext only — same model Bitwarden
uses. Conflict resolution becomes the hard problem (CRDTs, last-writer-
wins per entry, etc.).

**Q32. How would you prove to an auditor that the app is doing what
this doc claims?**

- Open-source the code (already done).
- Reproducible builds (Flutter supports this via deterministic Dart
  compilation; would need to pin all dependencies).
- Commission a formal cryptographic review.
- Add a debug-mode "crypto inspector" that prints every key derivation
  and encryption call so an auditor can manually trace one unlock.

**Q33. What did you intentionally NOT add and why?**

Voice unlock — voice is a poor authenticator (replay attacks, voice
synthesis, ambient capture risks). Standard authenticators (password,
phrase, Hello) all give cryptographic guarantees voice fundamentally
can't.

**Q34. If you had two more weeks, what would you ship?**

1. **Argon2id** as the new KDF (versioned `argon2id-aesgcm1`), with a
   one-time migration on next unlock.
2. **DPAPI-NG / TPM-bound K_device** so biometric is hardware-anchored.
3. **FIDO2 / YubiKey** support for `wrap.fido2`.
4. **Browser extension** with an isolated WebExtension storage backend
   talking to the desktop app via a local socket.
5. **Encrypted, append-only audit log** of every unlock / unlock failure
   for the user to review.

### G. Curveballs

**Q35. Walk me through what happens when the user types the wrong
password.**

1. UI calls `vault.unlockWithDetails(pwd)`.
2. `LocalVaultManager.unlock(pwd)` runs PBKDF2-600k → K_pwd.
3. Tries `decryptVaultSecret(K_pwd, wrap.pwd)`. GCM tag mismatch →
   `ArgumentError` from PointyCastle.
4. `_registerFailure()` increments the in-memory `_failedAttempts`
   and records the timestamp.
5. `IntrusionLog.recordFailure(IntrusionFailureReason.wrongPassword)`
   appends an event to `vault/intrusion.log` and increments the
   *persistent* `cumulativeFailures` counter.
6. If `cumulativeFailures >= 10`, the log writes a `lockout_engaged`
   event and flips `lockoutActive = true`. The UI gets back
   `UnlockResult.lockoutActive = true` and re-renders the red "Vault
   sealed" banner; the password field becomes inert.
7. Within a single session, after ≥ 5 failures, future attempts also
   trigger `_checkRateLimit()` and return "Too many failed attempts"
   without even running PBKDF2 — saves CPU.
8. UI shows a generic "Incorrect master password" — no "wrong by N
   characters" leak.

**Q35a. Why did you reject the "snap a photo + SMS the owner" intrusion
alert?**

Four concrete reasons, in priority order:

1. **Legal exposure.** Covert biometric capture of any person — even an
   attacker — is regulated by GDPR (Article 9), CCPA, India's DPDP Act,
   and various state wiretap laws. Some jurisdictions also legally
   require the camera LED to be lit during capture. Shipping that
   feature to other users would create real liability.
2. **Architectural conflict.** SMS needs a paid third-party provider
   (Twilio, AWS SNS) whose API key would have to ship in the binary.
   `strings.exe` extracts it in 5 seconds and the account gets drained
   by spammers. It also embeds a phone number on disk — sensitive PII —
   and forces the app to make outbound network calls, breaking the
   zero-knowledge / no-telemetry claim.
3. **It doesn't actually help.** The vault is already cryptographically
   unbreakable. Most laptops have physical camera shutters or are
   closed; capture = a black frame. And most failed unlocks are *the
   legitimate user typing wrong* — the owner gets self-shot SMS spam.
4. **Better alternatives exist.** A persistent intrusion log + 10-attempt
   lockout-into-recovery achieves the actual goal (awareness + active
   defense) with zero embedded secrets, zero network, zero PII, and
   zero legal exposure.

**Q35b. What stops an attacker from just deleting `intrusion.log` to
hide their tracks?**

Nothing within our app — they have local disk access, they win that
specific game. But even if they wipe the log:

- The **persistent cumulative counter** is gone, so the lockout
  threshold resets. They get another 10 free guesses. At PBKDF2-600k per
  guess that's ≈ 50 minutes of compute on a fast CPU per 10 attempts.
- They still cannot *succeed* — the password / GCM-tag check is unaffected
  by anything in the log file.
- The legitimate user notices the missing log next time they open the
  Security center ("Last successful unlock: …" disappearing is itself a
  signal).

A determined defense would require append-only file ACLs (not portable)
or shipping events to an external observer (breaks our local-only
promise). For our threat model, a local log is the right tradeoff —
honest about what it does and doesn't catch.

**Q35c. Why is the lockout cleared by recovery phrase / biometric /
backup-restore but NOT by a successful password unlock-after-lockout?**

Because once the cumulative counter has crossed 10, *we no longer trust
the password channel*. A lockout-clearing event must demonstrate
possession of a fundamentally different secret:

- The **24-word phrase** proves the legitimate user has the original
  setup material.
- **Windows Hello** proves the user passed an OS-level biometric
  challenge that the attacker cannot script.
- A **backup file + phrase** proves both possession of the phrase and
  a matching backup snapshot.

If the password path could clear its own lockout, the lockout would be
useless against an attacker brute-forcing the password — they'd just
keep trying until they got a hit, and the counter would never persist
across "successful" attempts.

**Q36. What happens if the user starts the recovery flow but then
cancels?**

Nothing destructive happens. `recoverWithPhrase` only writes new salts /
wraps after every check passes. Cancel = no file changes. The vault
remains unlocked under the old password.

**Q37. Could a malicious backup file compromise the app on import?**

The import path:
1. JSON-decodes the file (worst case: parse error → caught).
2. Checks the `magic`.
3. Tries to derive K_phrase from the user-supplied phrase + the
   backup's claimed `phraseSalt`.
4. AES-GCM-decrypts the wrap and the blob — both will throw on tag
   mismatch.

The attacker controls bytes inside the AES-GCM ciphertext, but the auth
tag verification ensures any modified bytes are rejected. The only
risk would be a JSON parser CVE in `dart:convert`, which is tightly
maintained and battle-tested.

**Q37a. Why did you implement TOTP yourselves instead of forcing the
user to use Google Authenticator / Authy?**

Two reasons. First, the realistic alternative for most users is *no*
second factor at all — adoption of separate authenticator apps is
historically very low because of the friction of pulling out a phone.
By placing TOTP one tap from the password we materially increase the
fraction of accounts that actually have 2FA enabled. Second, building
RFC 6238 ourselves is genuinely small (`lib/services/totp.dart` is
~250 lines including the base32 codec and the `otpauth://` parser),
keeps the threat model self-contained (no network, no plugin), and
avoids a hard dependency we can't audit.

**Q37b. Doesn't keeping the password and the TOTP secret in the same
vault collapse the "two factor" property to one factor?**

For accounts where the user opts in, yes — that is an honest downgrade
versus a hardware key. We address it three ways:

1. The shared secret is encrypted under the same MDK as the password
   with AES-256-GCM. A stolen vault file alone is still useless.
2. We surface a **first-time disclosure dialog** the moment the user
   enables TOTP on any entry, explicitly stating the trade-off and
   requiring an acknowledgement.
3. The Security Center keeps a persistent insight reminding the user
   to keep the second factor for primary email, banking, and crypto
   exchanges on a separate device.

The trade-off is deliberate: we'd rather a user have soft 2FA on 30
accounts plus hardware keys on the 3 critical ones than have hardware
keys on nothing because the friction was too high.

**Q37c. Why SHA-1 as the default HMAC for TOTP in 2026?**

Because RFC 6238 mandates SHA-1 as the default and ~99% of consumer
services emit SHA-1 secrets. More importantly, SHA-1's known
weaknesses — collision resistance — are completely irrelevant in this
construction: TOTP is built on HMAC, which only relies on the
**preimage** properties of the underlying hash, and we then truncate
the output to 6 decimal digits anyway. There is no collision attack
that produces a chosen 6-digit code from a chosen secret. We
nevertheless support SHA-256 and SHA-512 and auto-select them when
an `otpauth://` URI specifies them, so services that already moved to
those algorithms still work.

**Q37d. How is the TOTP secret protected at rest, in memory, and on
copy?**

- **At rest**: encrypted with AES-256-GCM under the MDK, with a
  fresh per-field random nonce. Same envelope as the password.
- **In memory**: lives in the `Credential.totpSecret` field after
  decryption; gets wiped along with the rest of the unlocked vault
  when `lock()` runs (auto-lock or manual).
- **On copy**: the rotating *code* (not the secret) goes through
  `SecureClipboard.copyAndScheduleClear`, which schedules a
  `Clipboard.setData('')` 30 seconds later. The base32 secret itself
  is never copied to the clipboard by Cipher Nest.

**Q38. Summarize the entire stack in 30 seconds.**

> Vault entries encrypted per-field with AES-256-GCM under a random 32-byte
> Master Data Key. The MDK is independently wrapped under (a) PBKDF2-
> SHA256-600k of the master password, (b) PBKDF2-SHA256-200k of a 24-word
> BIP-39 recovery phrase, and (c) optionally a Hello-gated device key.
> Atomic writes, brute-force backoff, clipboard auto-clear, auto-lock,
> best-effort key zeroing, dark titlebar via DWM, native Windows Hello
> via WinRT method channel — no third-party plugin, no network.

---

## 13. Glossary

- **AEAD** — Authenticated Encryption with Associated Data. A primitive
  that gives both confidentiality and integrity in one go.
- **AES** — Advanced Encryption Standard (Rijndael, 2001). 128-bit block
  cipher with 128/192/256-bit key sizes.
- **Auth tag** — The MAC output of an AEAD construction. For GCM it's
  128 bits.
- **BIP-39** — Bitcoin Improvement Proposal 39. The mnemonic seed phrase
  standard.
- **CSPRNG** — Cryptographically Secure Pseudo-Random Number Generator.
- **DPAPI** — Data Protection API on Windows. OS-managed per-user key
  storage.
- **GCM** — Galois/Counter Mode. The AEAD mode of AES we use.
- **GHASH** — The Galois-field universal hash inside GCM.
- **HMAC** — Hash-based Message Authentication Code.
- **HSM** — Hardware Security Module.
- **KDF** — Key Derivation Function. PBKDF2, scrypt, Argon2, HKDF…
- **MDK** — Master Data Key. The random 32-byte key that actually
  encrypts vault entries.
- **Nonce / IV** — Number-used-once / Initialization Vector. Per-message
  unique input to the cipher.
- **PBKDF2** — Password-Based KDF #2 (RFC 8018). Iterated PRF.
- **TPM** — Trusted Platform Module. Hardware key storage chip.
- **WinRT** — Windows Runtime. The modern Windows API surface.
- **Wrap / Unwrap** — Encrypt / decrypt a key with another key.
- **Zero-knowledge** — Server (or attacker) gains no information about
  the user's secrets. In our case there's no server, but the property
  is the same: the bytes on disk leak nothing without the password or
  phrase.

---

*End of document. If a question stumps you in an interview, breathe,
restate the question, and start from the threat model. Almost every
"why did you do X" answer flows from "because of threat Y."*
