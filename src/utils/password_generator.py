"""Secure password generator"""
import secrets
import string
from typing import Optional


class PasswordGenerator:
    """Generate cryptographically secure passwords"""
    
    # Character sets
    LOWERCASE = string.ascii_lowercase
    UPPERCASE = string.ascii_uppercase
    DIGITS = string.digits
    SYMBOLS = "!@#$%^&*()_+-=[]{}|;:,.<>?"
    SIMILAR_CHARS = "il1Lo0O"  # Characters that look similar
    
    @staticmethod
    def generate(
        length: int = 16,
        include_uppercase: bool = True,
        include_lowercase: bool = True,
        include_digits: bool = True,
        include_symbols: bool = True,
        exclude_similar: bool = True
    ) -> str:
        """
        Generate a cryptographically secure random password.
        
        Args:
            length: Password length (8-128)
            include_uppercase: Include uppercase letters
            include_lowercase: Include lowercase letters
            include_digits: Include digits
            include_symbols: Include special symbols
            exclude_similar: Exclude similar-looking characters
            
        Returns:
            Generated password string
        """
        if length < 8 or length > 128:
            raise ValueError("Password length must be between 8 and 128 characters")
        
        # Build character pool
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
        
        # Remove similar characters if requested
        if exclude_similar:
            char_pool = ''.join(c for c in char_pool if c not in PasswordGenerator.SIMILAR_CHARS)
        
        # Ensure at least one character from each selected type
        password_chars = []
        if include_lowercase:
            password_chars.append(secrets.choice(PasswordGenerator.LOWERCASE))
        if include_uppercase:
            password_chars.append(secrets.choice(PasswordGenerator.UPPERCASE))
        if include_digits:
            password_chars.append(secrets.choice(PasswordGenerator.DIGITS))
        if include_symbols:
            password_chars.append(secrets.choice(PasswordGenerator.SYMBOLS))
        
        # Fill the rest with random characters
        remaining_length = length - len(password_chars)
        for _ in range(remaining_length):
            password_chars.append(secrets.choice(char_pool))
        
        # Shuffle to avoid predictable patterns
        secrets.SystemRandom().shuffle(password_chars)
        
        return ''.join(password_chars)
    
    @staticmethod
    def check_strength(password: str) -> dict:
        """
        Check password strength and return analysis.
        
        Returns:
            Dictionary with strength score (0-100) and feedback
        """
        score = 0
        feedback = []
        
        length = len(password)
        
        # Length scoring
        if length >= 12:
            score += 25
        elif length >= 8:
            score += 15
        else:
            feedback.append("Password is too short (minimum 8 characters)")
        
        # Character variety
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
        
        # Common patterns check
        common_patterns = ['123', 'abc', 'qwerty', 'password', 'admin']
        if any(pattern in password.lower() for pattern in common_patterns):
            score -= 20
            feedback.append("Avoid common patterns")
        
        # Repetition check
        if len(set(password)) < len(password) * 0.5:
            score -= 10
            feedback.append("Too many repeated characters")
        
        # Determine strength level
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
            'score': max(0, min(100, score)),
            'strength': strength,
            'feedback': feedback,
            'length': length,
            'has_lower': has_lower,
            'has_upper': has_upper,
            'has_digit': has_digit,
            'has_symbol': has_symbol
        }

