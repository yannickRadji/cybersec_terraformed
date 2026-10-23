import re

NAME_PATTERN = re.compile(r"^[A-Za-z0-9 \-]{1,100}$")


def validate_name(raw: object) -> str:
    if not isinstance(raw, str):
        raise ValueError("name must be a string.")
    cleaned = raw.strip()
    if not NAME_PATTERN.fullmatch(cleaned):
        raise ValueError("name: 1-100 characters, letters, digits, space or hyphen only.")
    return cleaned