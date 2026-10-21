"""Keyring backend for the Docker image: keyrings.cryptfile, unlocked from the env.

keyrings.cryptfile 1.3.9 prompts on a terminal both to create and to unlock its
file, and ignores KEYRING_CRYPTFILE_PATH (both env hooks are unreleased); a
server has no terminal, and the default path is inside the container, not on
the data volume. This subclass takes the password from
KEYRING_CRYPTFILE_PASSWORD and the file from KEYRING_CRYPTFILE_PATH up front.
Assigning ``keyring_key`` runs the
library's own init: it creates the file (with its password-reference entry) on
first use, and on later starts verifies the password against that entry,
raising ``ValueError("Incorrect Password")`` instead of silently writing
secrets under a different key.

Selected with PYTHON_KEYRING_BACKEND=fa_keyring.EnvCryptFileKeyring.
"""

import os

from keyrings.cryptfile.cryptfile import CryptFileKeyring


class EnvCryptFileKeyring(CryptFileKeyring):
    """Encrypted-file keyring whose password and location come from the environment."""

    @property
    def file_path(self):
        return os.environ["KEYRING_CRYPTFILE_PATH"]

    def __init__(self):
        super().__init__()
        self.keyring_key = os.environ["KEYRING_CRYPTFILE_PASSWORD"]
