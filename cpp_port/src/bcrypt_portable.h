// ============================================================
// Portable bcrypt (OpenBSD implementation, ISC license)
//
// Produces and verifies standard "$2b$" hashes compatible with
// bcryptjs / libxcrypt, without depending on libcrypt.
// ============================================================

#pragma once

#include <string>

namespace bcrypt {

// cost is the log2 of the rounds (4..15, 10 recommended)
std::string hash(const std::string& password, int cost);

// returns true when `password` matches the "$2b$..." hash
bool verify(const std::string& password, const std::string& hash);

} // namespace bcrypt
