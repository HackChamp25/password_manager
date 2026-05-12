# Cipher Nest — Architecture & Cybersecurity Interview Guide

A single, deep document covering the full architecture, every cryptographic
choice, the rationale behind each decision, and the interview questions you
should be ready to answer when you say *"I built a desktop password manager
with end-to-end encryption."*

> Read this top-to-bottom once. Then re-read sections **3 (Crypto Core)**,
> **4 (MDK Architecture)** and **13 (Interview Q&A)** the night before any
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
10. [UX Architecture & Stability Engineering](#10-ux-architecture--stability-engineering)
11. [Why Flutter Desktop?](#11-why-flutter-desktop)
12. [What's NOT in Scope (Honest Tradeoffs)](#12-whats-not-in-scope-honest-tradeoffs)
13. [Cybersecurity Interview Q&A](#13-cybersecurity-interview-qa)
14. [Glossary](#14-glossary)

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
>
> Beyond the crypto core, the product layer ships a **kind-aware vault**
> (logins, secure notes, payment cards), **Password DNA** visual reuse
> detection, **offline crack-time estimates**, in-place **master-password
> rotation** (no vault re-encryption), printable **Emergency Kit export**,
> **Diceware-style passphrase generation**, and a **Ctrl+K command
> palette** — all under the same MDK envelope, all offline, all zero-
> knowledge.

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

### 6.10 Change master password (`changeMasterPassword`)

The single best demonstration of why the MDK indirection earns its
keep. When a logged-in user rotates their master password, **no entry
on disk is re-encrypted**. The lifecycle is:

1. Vault must be unlocked. We already hold the in-memory MDK.
2. Verify the user knows the current password before mutating anything:
   - Re-derive `K_pwd_current = PBKDF2(currentPassword, salt.salt, 600k)`.
   - Unwrap `wrap.pwd` with `K_pwd_current`. **Compare the unwrapped
     bytes against the in-memory MDK** using a length-prefixed XOR
     loop (`_bytesEqual`). Both must match — defending against the
     edge case where the file has been swapped under us between
     unlock and rotation.
3. Generate a fresh **password salt** (32 random bytes).
4. Derive `K_pwd_new = PBKDF2(newPassword, newSalt, 600k)`.
5. `wrap.pwd ← AES-GCM(K_pwd_new, MDK)`.
6. Atomically write `salt.salt` and `wrap.pwd`. Two file writes total.
7. `bestEffortZero` both derived keys.

What stays untouched after a successful rotation:

| File | Why it's unaffected |
|---|---|
| `vault.json` | Every entry is encrypted under the MDK, which didn't change |
| `verify.key` | Same — encrypted under MDK |
| `salt.phrase` / `wrap.phrase` | Recovery phrase is an **independent** path onto the MDK |
| `key.device` / `wrap.device` | Hello quick-unlock is independent too |
| Intrusion log | Metadata only — not key material |

This is what "non-destructive key rotation" looks like in practice and
is the same property you get from LUKS key-slot operations or
1Password's account-key rotation. The whole operation completes in
milliseconds because we never re-encrypt user data.

If the current-password verification fails, no file is touched and we
return `success: false, message: "Current master password is
incorrect."` — the user can retry indefinitely against the in-memory
MDK without involving the persistent intrusion log (this is an
authenticated user already inside the vault, not a brute-force
attacker at the gate).

### 6.11 Emergency Kit export

Many users will create a vault, never write down the phrase, and lose
access forever the day they reformat their machine. The Emergency Kit
addresses that with a **single printable plaintext document** that
contains everything needed to recover the vault on any machine.

When the user reveals their recovery phrase (Settings → Recovery &
Backup → Reveal phrase), they get a `Save Emergency Kit (.txt)`
button. It writes to:

```
%USERPROFILE%\Documents\CipherNest\EmergencyKit\
    CipherNest-EmergencyKit-<ISO-8601-timestamp>.txt
```

The file contains:

1. Generation timestamp + local hostname (so the user can tell which
   install it came from).
2. The 24 words formatted in a 4-column grid, padded and aligned for
   the human eye.
3. A two-path recovery walkthrough:
   - **Path A** — phrase only: install Cipher Nest, hit "Recovery
     options" on the lock screen, paste 24 words, set a new password.
   - **Path B** — phrase + `.cnest` backup: same flow via "Restore
     from encrypted backup."
4. A short technical addendum (PBKDF2 + AES-256-GCM + BIP-39).
5. A "Treat this document like cash" warning in the header and footer.

**Why plaintext?** Because the user is going to *print* and *physically
store* this. Encrypting it would force them to keep a separate
recovery secret for the kit itself, recursively. The threat model for
this artifact is "lives in a safe" or "lives in a sealed envelope" —
the encryption boundary is the physical world, not the file system.

We make the threat model explicit by surfacing the path in a snackbar
with a one-tap `COPY PATH` button so the user can immediately move
the file off the disk after generating it. The kit is created on
demand, never auto-generated, never synced.

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
│   ├── local_vault_manager.dart           ★ MDK architecture, lifecycle,
│   │                                          changeMasterPassword
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
│   └── vault_insights.dart                — reuse / weak-password / 2FA coverage,
│                                              kind breakdown
│
├── models/credential.dart                 ★ Credential value object — tagged
│                                              union over ItemKind {login, note, card}
│                                              with TOTP and card fields
│
├── utils/
│   ├── crypto_utils.dart                  — random + passphrase generator,
│   │                                          embedded Diceware wordlist,
│   │                                          strength meter
│   └── crack_time.dart                    — offline crack-time estimation
│                                              (entropy → seconds → human label)
│
├── widgets/
│   ├── session_guard.dart                 — pointer listener → bumpActivity
│   ├── totp_code_field.dart               — rotating 6-digit code + drain ring
│   ├── totp_setup_section.dart            — Add/Edit "enable 2FA" section + disclosure
│   ├── vault_lock_animation.dart          — login screen lock visual,
│   │                                          shader-cached painter
│   ├── password_dna.dart                  ★ SHA-256 visual fingerprint
│   │                                          (reuse detection without reveal)
│   ├── reveal_hold.dart                   — press-and-hold to reveal sensitive
│   │                                          fields (shoulder-surf defense)
│   ├── brand_logo.dart                    — woven-nest geometric mark
│   └── command_palette.dart               ★ Ctrl+K Spotlight-style search +
│                                              global actions
│
└── screens/
    ├── login_screen.dart                  — entry UI, recovery hub, Hello chip,
    │                                          matrix-rain background (shader-cached)
    ├── app_shell.dart                     — IndexedStack + TickerMode +
    │                                          RepaintBoundary per page,
    │                                          Ctrl+K Shortcuts wrapper
    ├── vault_page.dart                    — credential list + detail + banner
    ├── item_editor_screen.dart            — unified add/edit form, adapts per
    │                                          ItemKind (replaced legacy
    │                                          add_credential / edit_credential)
    ├── password_generator_page.dart       — Random + Passphrase mode segmented
    ├── security_center_page.dart          — vault insights view (incl. kind strip)
    └── settings_page.dart                 — Recovery & Backup, Master password
                                              rotation, Emergency Kit export,
                                              Hello, theme, auto-lock

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

## 10. UX Architecture & Stability Engineering

The cryptographic core (§3–§7) gives us a secure vault. This section
covers everything that turns a secure vault into a **product people
will actually use without crashing or feeling sluggish**. Each
subsection documents a specific engineering decision with the
rationale and the failure mode it prevents — these are the patterns
worth being able to defend in interviews.

### 10.1 The Credential model is a tagged union over `ItemKind`

The original schema was login-only: `{site, username, password, url,
notes}`. Adding **Secure Notes** and **Payment Cards** required either:

- (a) three separate classes + three storage tables + three editors, or
- (b) one `Credential` class with an `ItemKind` discriminator and
  kind-specific fields that are empty for the kinds that don't use
  them.

We picked (b). `models/credential.dart` defines:

```dart
enum ItemKind { login, note, card;
  String get wire => name;        // 'login' | 'note' | 'card'
  static ItemKind fromWire(String? s) { /* forward-compat fallback to login */ }
}

class Credential {
  final ItemKind kind;
  final String site;             // also serves as "title" for notes
  final String username;         // login-only
  final String password;         // login-only
  final String notes;            // notes-only body
  final String cardholderName, cardNumber, cardExpiry,
               cardCvv, cardBrand, cardZip;   // card-only
  // … TOTP fields, timestamps, etc.
}
```

**Why a single class and not three subclasses?**

1. **Vault storage is one encrypted JSON list.** With a single class,
   serialization stays one `toJson` / `fromJson`. With subclasses
   we'd need a tag discriminator at the JSON layer plus a polymorphic
   deserializer — same complexity, more files.
2. **`ItemKind.fromWire` is forward-compatible.** Any unknown kind in
   an old/future vault falls back to `ItemKind.login` instead of
   throwing. Users who downgrade and re-upgrade never lose data.
3. **The editor (`item_editor_screen.dart`) is one form that
   adapts.** Each field's `Visibility` is gated on the current kind.
   This means the validation rules, the password DNA strip, the
   crack-time pill, the favorite toggle — all share one
   implementation across kinds.
4. **Search stays kind-aware.** `VaultProvider.searchCredentials`
   never searches encrypted card numbers (we explicitly filter them
   out — there's no reason to enable substring lookup against a
   secret); it does search cardholder name and brand.

If we ever genuinely need divergent storage (e.g. encrypted file
attachments per card), we add a `_files` list to the same class — the
schema is already `version: 2` for exactly this reason.

### 10.2 Password Intelligence

Three small widgets that turn the vault from a list of secrets into a
**security advisor**. None of them touch the network.

#### Password DNA (`widgets/password_dna.dart`)

A coloured strip of 6 cells per password. Computed as
`SHA-256(password)` → first 6 bytes → each byte becomes a coloured
rounded cell. Two properties matter:

- **Identical passwords produce identical strips** — instant visual
  reuse detection at a glance. You scroll the vault and see "ah, my
  Twitter, my StackOverflow, and my Reddit all have the *same* DNA"
  without ever revealing the password.
- **6 bytes = 2⁴⁸ visual patterns**. Far too large to brute-force a
  low-entropy password from its picture alone, and we render the
  picture only — never the hex.

We deliberately do **not** salt with the site name. The reuse-
detection feature only works if the same password produces the same
DNA across entries. The information leak from "this password is the
same across these 4 sites" is a feature, not a flaw — it's the
information we want the user to see.

#### Crack-time estimation (`utils/crack_time.dart`)

Offline estimate of how long an attacker would take to brute-force
this specific string at a generous-to-the-attacker 10¹⁰ guesses/sec.
The estimate uses Shannon entropy of the character set + length, plus
a small penalty for repeated digrams. We surface it as a human label
("≈ 4 trillion years to crack") and a risk bucket (TRIVIAL / WEAK /
OK / STRONG / EXCELLENT) so the user gets a visceral sense of why
the generator produces 20-character passwords by default.

Why offline and not haveibeenpwned-style? Because the threat model
is local-only, and zxcvbn-style entropy estimation is mature enough
to be useful without leaving the machine.

#### RevealHold (`widgets/reveal_hold.dart`)

Press-and-hold to reveal the password, releases on mouse-up. Replaces
the persistent "👁 toggle reveal" pattern, which was a shoulder-surf
hazard (user clicks the eye, gets called away, password sits visible
for 20 minutes).

### 10.3 Recovery Hub redesign on the login screen

The old login screen had an "Erase vault" button right next to
"Recover." Two problems:

1. **Destructive option presented at peer level with non-destructive
   one.** Users with a forgotten password reflexively reach for
   "Erase" because the visual hierarchy didn't tell them they should
   prefer "Recover."
2. **Erasure on the lock screen has no good reason to exist.** If you
   can't unlock, you can't authorise destruction. We moved erasure
   to Settings → Danger Zone (which requires an unlocked vault) and
   gated it behind a `Type ERASE` confirmation dialog.

The lock screen now shows a single quiet `Can't unlock? Recovery
options` link, which opens a bottom sheet with three options:

| Option | What it does |
|---|---|
| **Recover with recovery phrase** | The §6.4 flow. Phrase + new password → unlocked |
| **Restore from encrypted backup** | The §6.7 flow. `.cnest` file + phrase + new password |
| **Test recovery phrase** | Read-only check: derives K_phrase, attempts to unwrap, *throws away the result*. Lets a user verify they wrote the phrase down correctly **without** rotating anything |

The "Test phrase" path is the unsung hero. It eliminates the
"phrase that I never tested and now it doesn't work" failure mode
that breaks people during a real recovery.

### 10.4 Change master password in place

Covered in §6.10. Worth reiterating the *operational* property in
this section:

> Master-password rotation is a 2-file write that costs less than 1
> second of wall clock. It never touches `vault.json`. The recovery
> phrase and biometric quick-unlock both keep working without any
> further action from the user.

The UI (`_ChangeMasterPasswordDialog`) is a `StatefulWidget` that
owns its three `TextEditingController`s (current / new / confirm)
via `State.dispose()` — see §10.7 for why this matters.

### 10.5 Diceware-style passphrase generator

The `Generator` page has two modes, switched via a `SegmentedButton`:

| Mode | Output example | Use case |
|---|---|---|
| **Random** | `7vN!q9PxLkDw#3RtY2zM` | Vault-stored passwords; the user never types them |
| **Passphrase** | `harbor-Cedar17-glide-prism-cobra` | Wi-Fi password, secondary email, anything the user must hand-type |

The passphrase generator (`CryptoUtils.generatePassphrase`) draws
words from an **embedded** 1,000-word list defined inline in
`utils/crypto_utils.dart` (no asset loading — ships in-binary, ~5 KB).
The list is curated:

- 4–8 letter words only (easy to type).
- No proper nouns, no offensive words, no easily-confused
  homophones (`bear`/`bare`, `pear`/`pair`).
- Each word is uniformly drawn from the list via `Random.secure()`
  (the OS CSPRNG — same primitive as the recovery phrase).

**Entropy math:**

- 5 random words from a 1,000-word list = log₂(1000⁵) ≈ **49.8 bits**.
- 6 words ≈ 59.8 bits.
- The optional injected number adds ~6.6 bits; the optional capitalised
  word adds ~2.3 bits.
- A 5-word passphrase with both options is roughly equivalent to a
  10-character random alphanumeric (which is ~60 bits), but with the
  crucial difference that the user can actually *type it from
  memory* without errors.

We use a much smaller wordlist than BIP-39 (1,000 vs 2,048) because
the BIP-39 list is designed for high-stakes, written-once seed
phrases where 256 bits matters. For everyday passphrases, 50–60 bits
+ memorability is a better trade.

### 10.6 Ctrl+K command palette

`widgets/command_palette.dart` is a Spotlight-style overlay that:

- **Fuzzy-searches every vault entry.** Scoring is tiered:
  - exact site match → score 100
  - prefix match → 70
  - substring match → 50
  - substring on username/url/cardholder/brand → 30
  - subsequence (e.g. "gth" matches "github") → 10
- **Default action on a credential** is `copy password (or card
  number) → jump to Vault tab → snackbar`. This is the
  "I just want to log into GitHub right now" path that's the most
  common reason anyone opens a password manager — we collapse it to
  three keystrokes (Ctrl+K, "git", Enter).
- **Global actions** are mixed into the result list when relevant:
  *Lock vault now*, *Generate strong password*, *Generate
  passphrase*, *Open Security Center*, *Open Settings*. They show
  the `ACTION` tag in the row so they never get confused with
  credentials.
- **Full keyboard control**: ↑/↓ to navigate, Enter to select,
  Escape to dismiss. The arrow keys also keep the highlighted row
  visible via `_scroll.animateTo`.
- **Wired at the shell level.** `app_shell.dart` wraps its `Scaffold`
  in `Shortcuts` + `Actions` listening for
  `SingleActivator(LogicalKeyboardKey.keyK, control: true)` (and the
  `meta: true` variant for Mac parity). Because the activator lives
  on the shell, the palette is reachable from any tab and from any
  dialog (showGeneralDialog inherits the same FocusScope).

The palette never displays passwords inline — it only copies them
through `SecureClipboard.copyAndScheduleClear` (30 s auto-wipe). The
clipboard is the single secret-exposure surface, and it cleans up
after itself.

### 10.7 The `TextEditingController` lifecycle race (the bug that bit us)

A class of crashes that **only** manifests when dialogs are
involved. Worth being able to explain in detail.

**The buggy pattern:**

```dart
final controller = TextEditingController();
final result = await showDialog<bool>(
  context: context,
  builder: (ctx) => StatefulBuilder(
    builder: (ctx, setInner) => AlertDialog(
      content: TextField(
        controller: controller,
        onChanged: (v) => setInner(() => /* … */),
      ),
      actions: [ FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('OK')) ],
    ),
  ),
);
controller.dispose();   // ← BUG
// continue with `result`
```

**Why this crashes:** `await showDialog` resolves the instant
`Navigator.pop` is called — but **the dialog is still
mid-exit-animation** for the next ~200 ms. During those 200 ms the
framework continues to rebuild the `TextField`'s subtree (cursor
fades, exit transition rebuilds). If `controller.dispose()` runs
before the dialog is fully removed, the next rebuild touches a
disposed controller and we get the iconic:

```
A TextEditingController was used after being disposed.
```

**The fix is structural, not patchy.** Move the controller into a
dedicated `StatefulWidget` so the State's `dispose()` runs only
after the Element is unmounted (which the framework guarantees
happens after the exit animation):

```dart
class _ConfirmEraseDialog extends StatefulWidget { … }
class _ConfirmEraseDialogState extends State<_ConfirmEraseDialog> {
  final _controller = TextEditingController();
  @override void dispose() { _controller.dispose(); super.dispose(); }
  // … build returns AlertDialog with the TextField …
}

await showDialog<bool>(
  context: context,
  builder: (_) => const _ConfirmEraseDialog(),
);
```

We applied this pattern to every dialog in the codebase that owns a
controller: `_ConfirmEraseDialog`, `_ChangeMasterPasswordDialog`, and
`_PhraseRevealDialog`.

### 10.8 The "swap tree mid-exit" race (the second bug that bit us)

Sister problem to §10.7, different symptom. The buggy pattern:

```dart
final ok = await showDialog<bool>(context: context, builder: …);
if (ok != true) return;
vault.lock();                // ← swaps AppShell → LoginScreen
// or: await vault.resetVault()  // same swap
```

**The bug:** `vault.lock()` calls `notifyListeners()` which causes
`MaterialApp.home` to flip from `AppShell` to `LoginScreen`. If
this happens while the dialog overlay is still animating out, the
overlay's render objects are being painted against a tree that's
already being deactivated. You get:

- `'is not true.' RenderObject reference box not attached`
- `RenderFlex overflowed by 99876 pixels` (yellow/black stripes)

**The fix:** wait for the dialog's exit animation before swapping
the tree:

```dart
final ok = await showDialog<bool>(context: context, builder: …);
if (ok != true || !mounted) return;
await Future.delayed(const Duration(milliseconds: 280));
if (!mounted) return;
vault.lock();
```

280 ms is empirically the Material default dialog exit duration
(200 ms) plus a small safety margin. Applied to both `_lock()` in
`vault_page.dart` and `_confirmErase` in `settings_page.dart`. The
auto-lock timer also bumps its `onLock()` callback through
`WidgetsBinding.instance.addPostFrameCallback` so a timer that fires
mid-build doesn't trigger the same race.

### 10.9 Tab-switching: `IndexedStack` + `TickerMode` + `RepaintBoundary`

The naive implementation of `app_shell.dart` was:

```dart
Expanded(child: pages[_index]),   // ← rebuilds whole subtree on switch
```

Every tab switch unmounted the previous page's `State` (losing
search query, scroll position, in-flight controllers) and mounted
the next one (running `initState`, restarting animations, re-fetching
lists). Vault → Generator stuttered for ~200 ms.

The current implementation pairs three Flutter primitives:

```dart
IndexedStack(
  index: _index,
  children: [
    for (var i = 0; i < pages.length; i++)
      TickerMode(
        enabled: i == _index,
        child: RepaintBoundary(child: pages[i]),
      ),
  ],
);
```

Each primitive solves one specific problem:

| Primitive | What it does | Why we need it |
|---|---|---|
| `IndexedStack` | Keeps every child mounted, paints only the visible one | Preserves state across tab switches. Switch becomes paint-only — no `initState`/`dispose` churn |
| `TickerMode(enabled: …)` | Pauses every `AnimationController` whose `Ticker` is under this scope when disabled | Off-screen pages stop burning CPU on their idle animations (Security Center pulse, lock-glow breath, etc.) |
| `RepaintBoundary` | Promotes its subtree to its own paint layer; the engine caches the layer and only repaints dirty children | A repaint inside Settings (typing in the master-password field) can't invalidate the cached Vault layer behind it |

The combination means tab switching after the first visit is
**instantaneous** and we never spend frame budget rendering pages
the user can't see.

### 10.10 CustomPainter shader caching

The login screen has two heavy painters that run continuously:

- **Matrix rain** at ~28 fps (via a `Timer.periodic` and a
  `ValueNotifier<int>` clock).
- **Vault lock** at ~60 fps (via a 4-second `..repeat(reverse: true)`
  idle controller).

Both painters were calling `RadialGradient.createShader(...)` and
`LinearGradient.createShader(...)` inside `paint()`. That meant a
fresh `Shader` object allocated per frame, per gradient — which on
the lock alone was 60 shaders/sec for the body + 60 for the shackle.
The shader objects themselves aren't huge, but the constant
allocation pressure was visibly starving the input-thread keystroke
processing pipeline.

**The fix** is the classic CustomPainter optimisation:

```dart
class _LockShaderCache {
  _LockShaderCache(this.size, this.body, this.shackle);
  final Size size;
  final Shader body, shackle;
}

_LockShaderCache? _lockShaderCache;   // process-wide

_LockShaderCache _shadersFor(Size size, Offset center, double bodyR) {
  final cached = _lockShaderCache;
  if (cached != null && cached.size.width.round() == size.width.round() …) {
    return cached;                       // reuse
  }
  final body = const RadialGradient(...).createShader(…);
  final shackle = const LinearGradient(...).createShader(…);
  final fresh = _LockShaderCache(size, body, shackle);
  _lockShaderCache = fresh;
  return fresh;
}
```

The key insight is that **shader binding is cheap once the shader
exists** — the expensive part is constructing the gradient
coefficients and uploading them. We pay that once per window-size
change, then reuse forever. The same pattern is applied to the
matrix's radial background (`_MatrixBgCache`).

### 10.11 Cutting the most expensive blur passes

`MaskFilter.blur(BlurStyle.normal, radius)` is Skia's gaussian
blur, and its cost is **O(radius²)**. We had three offenders on the
login screen:

- The matrix painter's hover aura, `MaskFilter.blur(40)`, drawn over
  the full hover region every frame. At 28 fps that's a 1,600-unit
  blur 28×/sec. Removed entirely — the pointer parallax already
  shifts the columns toward the cursor, so the aura was decorative
  double-coverage.
- Per-glyph `Shadow(blurRadius: 6)` on every matrix "head"
  character. Each `Shadow` forces an off-screen blur pass *per
  character*. With ~80 columns, that's 80 blur passes per frame.
  Removed — heads stay bright cyan and the eye still reads them
  as glowing.
- The lock's outer aura `MaskFilter.blur(28)` was kept (it's the
  signature visual of the lock) but its alpha is animated, not its
  radius — so Skia can cache the blurred bitmap and re-tint it.

Combined with the shader cache from §10.10, the login screen's
per-frame cost dropped enough that typing in the password field is
indistinguishable from a native text input.

### 10.12 `RepaintBoundary` discipline on the login screen

Even with cheap painters, the engine merges dirty rects up the
render tree until it hits a `RepaintBoundary`. That means a cursor
blink inside the password field — which is repainting at the
cursor's blink rate — was invalidating the entire `SafeArea` and
forcing the engine to redo the matrix layer + the brand wordmark
layer.

The login screen now has four strategic boundaries:

1. `RepaintBoundary` around the matrix shower (already there).
2. `RepaintBoundary` around `_BrandHero` so the wordmark's shimmer
   never invalidates the auth card.
3. `RepaintBoundary` around the entire auth card (the right column
   in the wide layout) so typing in the password field can't dirty
   the hero panel.
4. `RepaintBoundary` around `VaultLockAnimation` and around the
   password pill individually, so the lock's 60 fps idle paint and
   the password pill's cursor-blink paint stay in their own
   layers.

These five boundaries are the difference between "typing feels
laggy" and "typing feels like a native text field" — same machine,
same code, just a tighter dirty-region scope.

### 10.13 Dim-overlay opacity and matrix visibility

A small but visible win: the dim overlay above the matrix was at
`alpha 0.86 / 0.92` which crushed the rain down to faint hints.
Users reported "background animations are not visible." Reducing to
`alpha 0.55 / 0.62` lets the matrix breathe through while keeping
the auth card readable on top of its own opaque-ish surface.

The rule of thumb: dim overlays should sit just below the
*minimum* readability threshold for the foreground content, not at
"definitely-readable-everywhere" levels. Test against the brightest
fluid background, not against a static reference.

### 10.14 Summary table — UX patterns and what they protect against

| Pattern | What it costs | What it protects |
|---|---|---|
| Tagged-union `Credential` w/ `ItemKind.fromWire` | One enum + one editor that adapts | Forward compatibility, single editor codebase |
| Password DNA visual fingerprint | One `StatelessWidget` + SHA-256 | Silent password reuse detection |
| `RevealHold` press-and-hold | One `StatefulWidget` | Shoulder-surf when user is away from screen |
| Recovery Hub on login (no destructive option visible) | Bottom-sheet redesign | Accidental erasure under password-forget panic |
| `Test recovery phrase` (read-only) | One method on `LocalVaultManager` | "Phrase I never tested" failure mode |
| `_PhraseRevealDialog` w/ Emergency Kit button | Dedicated `StatefulWidget` + plaintext writer | Lost phrase = lost vault failure mode |
| `IndexedStack + TickerMode + RepaintBoundary` per tab | Three lines in `_buildPageBody` | State loss + CPU burn on tab switch |
| Shader caches in `CustomPainter` | One `_…ShaderCache` class per painter | Frame-budget starvation on continuous animations |
| `MaskFilter.blur` removal | Slight visual change | GPU stall on continuous repaints |
| Dialog `StatefulWidget` refactor | `dispose()` lifecycle is framework-owned | `TextEditingController used after being disposed` crash |
| 280 ms post-dialog delay before tree mutation | One `await Future.delayed` | `is not true.` overlay-vs-AppShell swap crash |
| `addPostFrameCallback` for auto-lock | One callback wrapper | mid-build `notifyListeners` tearing down `Consumer` |

> When asked **"what would you change about your project today,"** lead
> with the entries from this table — they show you can write code
> *and* reason about why it broke. That combination is rare in
> early-career interviews.

---

## 11. Why Flutter Desktop?

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

## 12. What's NOT in Scope (Honest Tradeoffs)

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
- ❌ **No soft-delete / trash bin.** Deleting an entry is immediate
  and irreversible. A 30-day undo bin is a reasonable next addition
  but isn't shipped.
- ❌ **No CSV import.** Moving from a previous password manager
  requires manual re-entry today. CSV import is on the roadmap but
  raises non-trivial threat-model questions (a CSV on disk is a
  plaintext leak surface) that we haven't designed for yet.
- ❌ **Emergency Kit is plaintext.** Intentional (see §6.11) — the
  user manages physical storage of it. But we don't *prevent* a user
  from leaving it on their desktop, and we don't watermark the file
  if exfiltrated.
- ❌ **No keyboard-activity auto-lock bump.** `SessionGuard` only
  listens to pointer events; keystrokes do not reset the idle timer.
  A user typing into the password field for 5 minutes would
  technically auto-lock mid-edit. Easy fix (`Focus` + raw keyboard
  listener), not yet shipped.

What we *used* to call out here and **have since shipped**:

- ✅ **Master-password rotation while logged in** — §6.10.
- ✅ **Printable Emergency Kit export** — §6.11.
- ✅ **Diceware-style passphrase generation** — §10.5.
- ✅ **Read-only phrase verification (Test phrase)** — §10.3.
- ✅ **Command palette (Ctrl+K)** — §10.6.
- ✅ **Multi-kind items (logins / notes / cards)** — §10.1.

---

## 13. Cybersecurity Interview Q&A

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

### H. Product / UX architecture (recent additions)

**Q39. Walk me through exactly what happens when the user changes
their master password.**

(Cover §6.10 from memory.) Vault must be unlocked, so we have the
MDK in memory. We re-derive `K_pwd_current` from the typed current
password, unwrap `wrap.pwd`, and **compare the unwrapped bytes
against the in-memory MDK with a length-prefixed XOR-fold loop**
(`_bytesEqual`). If they don't match, we return "Current password
is incorrect" and touch zero files. If they match, we generate a
fresh 32-byte password salt, derive `K_pwd_new` at PBKDF2-600k,
encrypt the in-memory MDK with the new key, and atomically write
`salt.salt` and `wrap.pwd`. Two file writes. `vault.json`,
`verify.key`, `wrap.phrase`, `wrap.device`, and the intrusion log
are all untouched. Recovery phrase and biometric quick-unlock keep
working without any user action. This is the entire point of having
an MDK — operational, not cryptographic.

**Q40. Why is the Emergency Kit plaintext? Isn't that a leak?**

It is a leak **the moment it lives on the file system**. That's
exactly why we (a) only generate it on explicit user request, (b)
surface the full path in a snackbar with a one-tap COPY PATH
button so the user can immediately move the file off disk, and (c)
include "Treat this document like cash" as the header and footer of
the file itself. The threat model for the Emergency Kit is
**physical storage** — a printed copy in a safe, in a sealed
envelope in a safety-deposit box, etc. If we encrypted the kit,
the user would need a separate secret to decrypt it, which
recursively re-creates the original "I forgot my master password"
problem. The only solid alternative would be a Shamir-secret-shared
QR code, which is a real future enhancement, but is non-trivial
both to implement and to explain to non-technical users at
recovery time.

**Q41. Why a 1,000-word Diceware list and not the BIP-39 2,048-word
list for the passphrase generator?**

Different threat model. BIP-39's 24-word phrase is the *recovery
secret for the entire vault* — every word must add precious bits
because forgetting the phrase = losing the vault. So we use the
2,048-word standard for 264 bits of entropy. The Diceware
passphrase generator is for *everyday vault entries the user has
to type out* — Wi-Fi passwords, secondary emails, anything not
stored under the master vault. There the trade-off shifts toward
memorability: a 5-word phrase from 1,000 words is ~50 bits, easily
strong enough for a per-account password, and dramatically easier
to type. Different stakes, different list.

**Q42. Explain Password DNA and why it's safe to display.**

It's the first 6 bytes of SHA-256(password) rendered as 6
coloured cells. Two security properties matter:

1. **Identical passwords produce identical pictures**, so the user
   sees password reuse across entries at a glance, without anyone
   needing to reveal the actual passwords.
2. **The visual space is ~2⁴⁸**, large enough that reversing a
   low-entropy password from its picture alone is infeasible — and
   we render only the picture, never the hex. SHA-256 is preimage-
   resistant, so even if a viewer photographed the strip, recovering
   the password is no easier than brute-forcing the hash directly.

It does intentionally leak the "these N entries share a password"
fact — but that *is* the feature. The user should know.

**Q43. Why did you replace `Erase vault` on the login screen with a
`Recovery options` menu and a separate Settings-only erase?**

Two security-product instincts:

1. **Destructive options at peer level with non-destructive ones
   are an anti-pattern.** A frustrated user who can't unlock will
   reflexively click "Erase" if it looks like just another option
   next to "Recover." Moving destruction off the lock screen
   prevents a panicked tap from torching the vault.
2. **You shouldn't be able to authorise destruction when you can't
   authorise anything else.** Erasure on the lock screen has no
   authentication. Gating it behind a Settings-only "Type ERASE"
   confirmation that requires the vault to already be unlocked
   means the only person who can erase the vault is someone who
   has already proved possession of the master password.

It's the same logic that puts "Delete account" under Settings in
every well-designed app, not next to the login button.

**Q44. Tell me about a bug you fixed and what it taught you.**

Pick one of the two from §10.7 / §10.8. The
`TextEditingController used after being disposed` crash is the
crisper story: `await showDialog` resolves at `Navigator.pop` time,
but Flutter keeps the dialog mounted for the ~200 ms exit
animation. If you `dispose()` the controller you owned in the
calling function before that animation finishes, the next rebuild
inside the dialog touches a disposed controller. Lesson: **don't
own object lifecycles across `await showDialog` boundaries**. Move
the controller into a `StatefulWidget` whose `dispose()` runs only
when the framework removes the Element — which it guarantees
happens after the exit animation. The fix is structural, not a
band-aid.

**Q45. How does your IndexedStack + TickerMode pattern work, and
why isn't an IndexedStack alone enough?**

`IndexedStack` keeps every child mounted but only paints the
selected one. That preserves State across tab switches (search
queries, scroll positions, in-flight controllers) — which is the
primary goal. But the off-screen children are *still building*,
which means their `AnimationController`s keep ticking under their
`Ticker`s. So you've eliminated mount-time cost but you're now
burning CPU on animations the user can't see. Wrapping each child
in `TickerMode(enabled: i == _index)` disables every Ticker in the
subtree when the page is hidden, so animations literally pause and
resume across switches. Adding `RepaintBoundary` per child is the
third ingredient: it gives each page its own paint layer so a
repaint inside Settings can't dirty the cached Vault layer behind
it. All three together = tab switching is essentially free.

**Q46. Walk me through the shader caching optimisation. Why was it
necessary?**

Two `CustomPainter`s on the login screen — the matrix rain at ~28
fps and the vault lock at ~60 fps — were calling
`RadialGradient.createShader()` and `LinearGradient.createShader()`
inside `paint()`. That means a fresh `Shader` object allocated per
frame, per gradient. The lock alone was creating 120 shaders per
second between the body and the shackle. The shader objects are
small but the allocation churn — plus the upload to the GPU each
time — was visibly starving the input thread, so typing in the
password field felt sticky. The fix is to cache the shaders in a
top-level `_LockShaderCache` keyed by the painter's Size and only
recreate when the size changes (i.e., once per window resize).
After: same visuals, ~zero shader allocations during animation,
and the keystroke latency drops to native-text-input territory. The
same pattern works for the matrix's radial background.

**Q47. Why don't you ship a network breach-check (HaveIBeenPwned)?**

Three reasons. First, the headline feature of the app is
zero-knowledge / offline. Adding a network call — even a
k-anonymous one — breaks that promise and changes the threat model.
Second, the API call leaks the *fact that the user is checking this
password*, which is a metadata side-channel some users object to.
Third, doing breach-check locally would require either bundling
the full ~12 GB HIBP database into the app, which is impractical,
or downloading on demand, which is the same network problem
disguised. The right shape for breach-check in our model would be
a future "import a locally-downloaded HIBP bloom filter from
Settings" toggle — explicit, opt-in, and fully offline once
configured. Not shipped yet.

---

## 14. Glossary

- **AEAD** — Authenticated Encryption with Associated Data. A primitive
  that gives both confidentiality and integrity in one go.
- **AES** — Advanced Encryption Standard (Rijndael, 2001). 128-bit block
  cipher with 128/192/256-bit key sizes.
- **Auth tag** — The MAC output of an AEAD construction. For GCM it's
  128 bits.
- **BIP-39** — Bitcoin Improvement Proposal 39. The mnemonic seed phrase
  standard.
- **CSPRNG** — Cryptographically Secure Pseudo-Random Number Generator.
- **Diceware** — Passphrase generation scheme. Each word is drawn
  uniformly from a fixed word list; the entropy per word is
  log₂(list size).
- **DPAPI** — Data Protection API on Windows. OS-managed per-user key
  storage.
- **Emergency Kit** — A user-generated printable plaintext document
  containing the 24-word recovery phrase + restoration steps. Intended
  for physical (not digital) storage. See §6.11.
- **Forbidden attack on GCM** — Nonce reuse under the same key reveals
  the GHASH subkey H, breaking authenticity universally for that key.
  This is why every GCM encryption needs a fresh nonce.
- **GCM** — Galois/Counter Mode. The AEAD mode of AES we use.
- **GHASH** — The Galois-field universal hash inside GCM.
- **HMAC** — Hash-based Message Authentication Code.
- **HSM** — Hardware Security Module.
- **IndexedStack** — Flutter widget that keeps every child in the
  Element tree but only paints the selected one. Preserves State
  across switches; pair with `TickerMode` to pause off-screen
  animations.
- **ItemKind** — Cipher Nest's tagged-union discriminator over a
  single `Credential` class. Values are `login`, `note`, `card`.
  Forward-compatible: unknown wire values fall back to `login`.
- **KDF** — Key Derivation Function. PBKDF2, scrypt, Argon2, HKDF…
- **MDK** — Master Data Key. The random 32-byte key that actually
  encrypts vault entries.
- **Nonce / IV** — Number-used-once / Initialization Vector. Per-message
  unique input to the cipher.
- **Password DNA** — Cipher Nest's visual fingerprint widget. SHA-256
  of the password rendered as 6 coloured cells; identical passwords
  produce identical pictures. See §10.2.
- **PBKDF2** — Password-Based KDF #2 (RFC 8018). Iterated PRF.
- **RepaintBoundary** — Flutter widget that promotes its subtree to a
  dedicated paint layer. Cached by the engine, only repaints when
  its own children are dirty. Used to isolate the matrix, the brand
  hero, the auth card, the lock animation, and the password pill on
  the login screen.
- **TickerMode** — Flutter widget that enables or disables every
  `Ticker` in its subtree. Used per-child inside our `IndexedStack`
  so off-screen pages stop animating.
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
