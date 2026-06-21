//
//  EnglishDictionary.cpp
//  VNKey
//

#include "EnglishDictionary.h"

#include <algorithm>
#include <cctype>
#include <iterator>
#include <sstream>
#include <unordered_set>

namespace {

// Keep sorted for binary_search. This is a protected lexicon, not a complete
// English dictionary: only words that are common in Vietnamese technical text
// and are vulnerable to Telex transformations belong here.
const char *const kProtectedEnglishWords[] = {
    "alert",
    "are",
    "array",
    "async",
    "await",
    "base",
    "benchmark",
    "browser",
    "buffer",
    "care",
    "case",
    "checkbox",
    "class",
    "coffee",
    "color",
    "dashboard",
    "database",
    "destroy",
    "diff",
    "display",
    "docker",
    "download",
    "dropdown",
    "error",
    "example",
    "expected",
    "export",
    "extension",
    "fare",
    "feature",
    "feedback",
    "filter",
    "focus",
    "for",
    "fork",
    "form",
    "format",
    "framework",
    "free",
    "google",
    "handler",
    "header",
    "helper",
    "her",
    "here",
    "history",
    "host",
    "hover",
    "import",
    "index",
    "interface",
    "internet",
    "issue",
    "javascript",
    "keyboard",
    "kubernetes",
    "library",
    "linux",
    "logger",
    "macos",
    "meeting",
    "memory",
    "message",
    "more",
    "mouse",
    "network",
    "parameter",
    "password",
    "port",
    "post",
    "process",
    "project",
    "promise",
    "proxy",
    "push",
    "python",
    "query",
    "queue",
    "read",
    "regression",
    "release",
    "render",
    "request",
    "response",
    "restart",
    "router",
    "rust",
    "screen",
    "search",
    "server",
    "service",
    "share",
    "software",
    "sort",
    "source",
    "status",
    "success",
    "support",
    "swift",
    "system",
    "target",
    "task",
    "terminal",
    "text",
    "theme",
    "there",
    "these",
    "thread",
    "token",
    "tool",
    "true",
    "typescript",
    "undefined",
    "url",
    "user",
    "variable",
    "version",
    "warning",
    "was",
    "website",
    "websocket",
    "were",
    "where",
    "width",
    "wifi",
    "windows",
    "word",
    "workflow",
    "write",
    "wrong"};

std::string lowerAscii(const std::string &word) {
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

std::unordered_set<std::string> gCustomEnglishWords;

} // namespace

bool isProtectedEnglishWord(const std::string &word) {
  const std::string normalized = lowerAscii(word);
  if (normalized.empty()) {
    return false;
  }
  if (std::binary_search(std::begin(kProtectedEnglishWords),
                         std::end(kProtectedEnglishWords), normalized)) {
    return true;
  }
  return gCustomEnglishWords.count(normalized) > 0;
}

void setCustomEnglishWords(const std::string& content) {
  gCustomEnglishWords.clear();
  std::stringstream ss(content);
  std::string word;
  while (ss >> word) {
    if (word.empty()) continue;
    if (word[0] == '#') {
      std::string comment;
      std::getline(ss, comment);
      continue;
    }
    std::string normalized = lowerAscii(word);
    if (!normalized.empty()) {
      gCustomEnglishWords.insert(normalized);
    }
  }
}
