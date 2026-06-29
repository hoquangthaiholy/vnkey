//
//  EnglishDictionary.cpp
//  VNKey
//

#include "EnglishDictionary.h"
#include "StringUtil.h"

#include <algorithm>
#include <cctype>
#include <iterator>
#include <memory>
#include <sstream>
#include <unordered_set>

const std::string& getDefaultEnglishWords() {
  static const std::string words =
      "password rust issue coffee wrong software framework network browser download website search support workflow feedback dashboard deadline meeting google excel slack chrome youtube facebook instagram twitter microsoft office word powerpoint code vs notion telegram laptop email login logout upload file backend frontend button modal form checkbox dropdown github json http websocket database macos windows linux benchmark median p95 p99 space enter tab ai api cpu gpu wifi bluetooth iphone android docker kubernetes javascript typescript python swift production antivirus free write screen user";
  return words;
}

namespace {

// Keep sorted for binary_search. This is a protected lexicon, not a complete
// English dictionary: only words that are common in Vietnamese technical text
// and are vulnerable to Telex transformations belong here.

struct TrieNode {
  bool isWord = false;
  std::unique_ptr<TrieNode> children[26];
};

class Trie {
public:
  std::unique_ptr<TrieNode> root;
  Trie() {
    root = std::make_unique<TrieNode>();
  }
  
  void insert(const std::string& word) {
    TrieNode* curr = root.get();
    for (char c : word) {
      int idx = c - 'a';
      if (idx < 0 || idx >= 26) return;
      if (!curr->children[idx]) {
        curr->children[idx] = std::make_unique<TrieNode>();
      }
      curr = curr->children[idx].get();
    }
    curr->isWord = true;
  }
  
  bool search(const std::string& word) const {
    TrieNode* curr = root.get();
    for (char c : word) {
      int idx = c - 'a';
      if (idx < 0 || idx >= 26) return false;
      if (!curr->children[idx]) return false;
      curr = curr->children[idx].get();
    }
    return curr->isWord;
  }
  
  bool startsWith(const std::string& prefix) const {
    if (prefix.empty()) return false;
    TrieNode* curr = root.get();
    for (char c : prefix) {
      int idx = c - 'a';
      if (idx < 0 || idx >= 26) return false;
      if (!curr->children[idx]) return false;
      curr = curr->children[idx].get();
    }
    return true;
  }
};

std::shared_ptr<const Trie> gCustomEnglishWords = []() {
  auto customTrie = std::make_shared<Trie>();
  std::stringstream ss(getDefaultEnglishWords());
  std::string word;
  while (ss >> word) {
    if (word.empty()) continue;
    std::string normalized = vnkey::lowerAsciiOnly(word);
    if (!normalized.empty()) {
      customTrie->insert(normalized);
    }
  }
  return customTrie;
}();

} // namespace

bool isProtectedEnglishWord(const std::string &word) {
  const std::string normalized = vnkey::lowerAsciiOnly(word);
  if (normalized.empty()) {
    return false;
  }
  const auto customTrie = std::atomic_load(&gCustomEnglishWords);
  return customTrie->search(normalized);
}

bool hasProtectedEnglishPrefix(const std::string& prefix) {
  const std::string normalized = vnkey::lowerAsciiOnly(prefix);
  if (normalized.empty()) {
    return false;
  }
  const auto customTrie = std::atomic_load(&gCustomEnglishWords);
  return customTrie->startsWith(normalized);
}

void setCustomEnglishWords(const std::string& content) {
  auto customTrie = std::make_shared<Trie>();
  std::stringstream ss(content);
  std::string word;
  while (ss >> word) {
    if (word.empty()) continue;
    if (word[0] == '#') {
      std::string comment;
      std::getline(ss, comment);
      continue;
    }
    std::string normalized = vnkey::lowerAsciiOnly(word);
    if (!normalized.empty()) {
      customTrie->insert(normalized);
    }
  }
  std::atomic_store(
      &gCustomEnglishWords,
      std::static_pointer_cast<const Trie>(customTrie));
}

void addWordToTrie(const std::string& word) {
  const std::string normalized = vnkey::lowerAsciiOnly(word);
  if (normalized.empty()) return;
  auto trie = std::atomic_load(&gCustomEnglishWords);
  if (trie) {
    const_cast<Trie*>(trie.get())->insert(normalized);
  }
}


