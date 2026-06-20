//
//  EnglishDictionary.cpp
//  VNKey
//

#include "EnglishDictionary.h"

#include <algorithm>
#include <cctype>
#include <iterator>

namespace {

// Keep sorted for binary_search. This is a protected lexicon, not a complete
// English dictionary: only words that are common in Vietnamese technical text
// and are vulnerable to Telex transformations belong here.
const char* const kProtectedEnglishWords[] = {
    "api",
    "are",
    "backend",
    "base",
    "benchmark",
    "browser",
    "button",
    "care",
    "case",
    "checkbox",
    "chrome",
    "code",
    "coffee",
    "cpu",
    "dashboard",
    "database",
    "deadline",
    "debug",
    "docker",
    "documentation",
    "download",
    "dropdown",
    "email",
    "engine",
    "example",
    "expected",
    "fare",
    "feedback",
    "file",
    "for",
    "form",
    "framework",
    "free",
    "frontend",
    "github",
    "google",
    "gpu",
    "her",
    "here",
    "http",
    "input",
    "issue",
    "javascript",
    "json",
    "kubernetes",
    "laptop",
    "linux",
    "login",
    "logout",
    "macos",
    "median",
    "meeting",
    "modal",
    "mode",
    "more",
    "network",
    "notion",
    "online",
    "output",
    "password",
    "production",
    "python",
    "regression",
    "render",
    "review",
    "rust",
    "screen",
    "search",
    "share",
    "slack",
    "software",
    "support",
    "swift",
    "telegram",
    "there",
    "these",
    "typescript",
    "upload",
    "url",
    "user",
    "vscode",
    "was",
    "website",
    "websocket",
    "were",
    "where",
    "wifi",
    "windows",
    "word",
    "workflow",
    "write",
    "wrong"
};

std::string lowerAscii(const std::string& word) {
    std::string normalized;
    normalized.reserve(word.size());
    for (const unsigned char character : word) {
        if (!std::isalpha(character)) {
            return std::string();
        }
        normalized.push_back(static_cast<char>(std::tolower(character)));
    }
    return normalized;
}

} // namespace

bool isProtectedEnglishWord(const std::string& word) {
    const std::string normalized = lowerAscii(word);
    if (normalized.empty()) {
        return false;
    }
    return std::binary_search(std::begin(kProtectedEnglishWords),
                              std::end(kProtectedEnglishWords),
                              normalized);
}
