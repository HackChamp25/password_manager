"""Secure password generator"""
import secrets
import string
class PasswordGenerator:
    """Generate cryptographically secure passwords"""

    LOWERCASE = string.ascii_lowercase
    UPPERCASE = string.ascii_uppercase
    DIGITS = string.digits
    SYMBOLS = "!@#$%^&*()_+-=[]{}|;:,.<>?"
    SIMILAR_CHARS = "il1Lo0O"

    @staticmethod
    def generate(
        length: int = 16,
        include_uppercase: bool = True,
        include_lowercase: bool = True,
        include_digits: bool = True,
        include_symbols: bool = True,
        exclude_similar: bool = True,
    ) -> str:
        if length < 8 or length > 128:
            raise ValueError("Password length must be between 8 and 128 characters")
        char_pool = ""
        if include_lowercase:
            char_pool += PasswordGenerator.LOWERCASE
        if include_uppercase:
            char_pool += PasswordGenerator.UPPERCASE
        if include_digits:
            char_pool += PasswordGenerator.DIGITS
        if include_symbols:
            char_pool += PasswordGenerator.SYMBOLS
        if not char_pool:
            raise ValueError("At least one character type must be enabled")
        if exclude_similar:
            char_pool = "".join(c for c in char_pool if c not in PasswordGenerator.SIMILAR_CHARS)
        password_chars = []
        if include_lowercase:
            password_chars.append(secrets.choice(PasswordGenerator.LOWERCASE))
        if include_uppercase:
            password_chars.append(secrets.choice(PasswordGenerator.UPPERCASE))
        if include_digits:
            password_chars.append(secrets.choice(PasswordGenerator.DIGITS))
        if include_symbols:
            password_chars.append(secrets.choice(PasswordGenerator.SYMBOLS))
        remaining_length = length - len(password_chars)
        for _ in range(remaining_length):
            password_chars.append(secrets.choice(char_pool))
        secrets.SystemRandom().shuffle(password_chars)
        return "".join(password_chars)

    @staticmethod
    def check_strength(password: str) -> dict:
        score = 0
        feedback = []
        length = len(password)
        if length >= 12:
            score += 25
        elif length >= 8:
            score += 15
        else:
            feedback.append("Password is too short (minimum 8 characters)")
        has_lower = any(c.islower() for c in password)
        has_upper = any(c.isupper() for c in password)
        has_digit = any(c.isdigit() for c in password)
        has_symbol = any(c in PasswordGenerator.SYMBOLS for c in password)
        variety_count = sum([has_lower, has_upper, has_digit, has_symbol])
        score += variety_count * 15
        if not has_lower:
            feedback.append("Add lowercase letters")
        if not has_upper:
            feedback.append("Add uppercase letters")
        if not has_digit:
            feedback.append("Add numbers")
        if not has_symbol:
            feedback.append("Add special characters")
        common_patterns = ["123", "abc", "qwerty", "password", "admin"]
        if any(pattern in password.lower() for pattern in common_patterns):
            score -= 20
            feedback.append("Avoid common patterns")
        if len(set(password)) < len(password) * 0.5:
            score -= 10
            feedback.append("Too many repeated characters")
        if score >= 80:
            strength = "Very Strong"
        elif score >= 60:
            strength = "Strong"
        elif score >= 40:
            strength = "Moderate"
        elif score >= 20:
            strength = "Weak"
        else:
            strength = "Very Weak"
        return {
            "score": max(0, min(100, score)),
            "strength": strength,
            "feedback": feedback,
            "length": length,
            "has_lower": has_lower,
            "has_upper": has_upper,
            "has_digit": has_digit,
            "has_symbol": has_symbol,
        }
