#include "ProgrammingFSM.h"
#include <unordered_set>
#include <memory>
#include <sstream>
#include <cctype>
#include <atomic>

namespace vnkey {

namespace {

using KeywordSet = std::unordered_set<std::string>;
std::shared_ptr<const KeywordSet> gCustomProgrammingKeywords = std::make_shared<const KeywordSet>();

const std::unordered_set<std::string> builtInKeywords = {
    // Control flow & exception handling
    "if", "else", "elif", "while", "for", "do", "switch", "case", "default",
    "break", "continue", "return", "try", "catch", "finally", "throw", "throws",
    "except", "raise", "with", "as", "import", "export", "from", "yield", "await", "async",
    
    // Declarations, modifiers, types
    "const", "let", "var", "function", "def", "class", "struct", "interface", "enum",
    "public", "private", "protected", "static", "final", "abstract", "virtual", "override",
    "volatile", "transient", "synchronized", "native", "extern", "fn", "impl", "trait",
    "type", "mut", "pub", "use", "mod",
    
    // Primitive types
    "void", "int", "float", "double", "char", "bool", "boolean", "string", "long", "short",
    "byte", "signed", "unsigned",
    
    // Values & keywords
    "true", "false", "null", "nil", "undefined", "none", "self", "this", "super",
    
    // Common programming terms / functions
    "println", "printf", "console", "log", "print", "main", "include", "define",
    "ifndef", "ifdef", "endif", "namespace", "package", "extends", "implements",
    
    // Common technology names (from programming/sysops context)
    "github", "gitlab", "docker", "kubernetes", "k8s", "redis", "nginx", "mysql",
    "mongodb", "sqlite", "postgres", "postgresql", "react", "vue", "svelte", "angular",
    "electron", "tauri", "nodejs", "npm", "cargo", "pip", "maven", "gradle"
};

bool isProgrammingChar(char c) {
    return std::isalnum(static_cast<unsigned char>(c)) || c == '_' || c == '$';
}

} // namespace

bool isValidProgrammingKeyword(const std::string& word) {
    if (word.empty() || word.length() > 50) return false;
    
    // Basic lexer checks:
    // 1. Must not start with a digit
    if (std::isdigit(static_cast<unsigned char>(word[0]))) {
        return false;
    }
    
    // 2. All characters must be valid identifier characters (a-z, A-Z, 0-9, _, $)
    // And there must be at least one letter character.
    bool hasLetter = false;
    for (char c : word) {
        if (!isProgrammingChar(c)) {
            return false;
        }
        if (std::isalpha(static_cast<unsigned char>(c))) {
            hasLetter = true;
        }
    }
    if (!hasLetter) return false;
    
    // 3. Check if it matches a built-in or user-defined keyword (case-insensitive for check)
    std::string lowerWord;
    lowerWord.reserve(word.size());
    for (char c : word) {
        lowerWord.push_back(static_cast<char>(std::tolower(static_cast<unsigned char>(c))));
    }
    
    if (builtInKeywords.count(lowerWord) > 0) {
        return true;
    }
    
    const auto customWords = std::atomic_load(&gCustomProgrammingKeywords);
    if (customWords->count(lowerWord) > 0) {
        return true;
    }
    
    // 4. Check for programming identifier "clues":
    // Clue A: Starts with '$' (PHP style variable)
    if (word[0] == '$') {
        return word.length() > 1;
    }
    
    // Clue B: Contains an underscore '_' (snake_case)
    if (word.find('_') != std::string::npos) {
        return true;
    }
    
    // Clue C: All uppercase and length >= 3 (e.g. constant or technology acronym: API, URL, JSON)
    bool allUpper = true;
    for (char c : word) {
        if (std::isalpha(static_cast<unsigned char>(c)) && !std::isupper(static_cast<unsigned char>(c))) {
            allUpper = false;
            break;
        }
    }
    if (allUpper && word.length() >= 3) {
        return true;
    }
    
    // Clue D: camelCase or PascalCase (has transition from lowercase to uppercase)
    // E.g. getApp, AppBuilder
    bool hasLowerToUpper = false;
    for (size_t i = 0; i < word.length() - 1; ++i) {
        if (std::islower(static_cast<unsigned char>(word[i])) && std::isupper(static_cast<unsigned char>(word[i+1]))) {
            hasLowerToUpper = true;
            break;
        }
    }
    if (hasLowerToUpper) {
        return true;
    }
    
    // Clue E: Transition between letter and digit (e.g. utf8, sha256)
    bool hasLetterDigitTransition = false;
    for (size_t i = 0; i < word.length() - 1; ++i) {
        bool currentLetter = std::isalpha(static_cast<unsigned char>(word[i])) != 0;
        bool nextDigit = std::isdigit(static_cast<unsigned char>(word[i+1])) != 0;
        bool currentDigit = std::isdigit(static_cast<unsigned char>(word[i])) != 0;
        bool nextLetter = std::isalpha(static_cast<unsigned char>(word[i+1])) != 0;
        if ((currentLetter && nextDigit) || (currentDigit && nextLetter)) {
            hasLetterDigitTransition = true;
            break;
        }
    }
    if (hasLetterDigitTransition) {
        return true;
    }
    
    return false;
}

bool isBuiltInProgrammingKeyword(const std::string& word) {
    if (word.empty()) return false;
    std::string lowerWord;
    lowerWord.reserve(word.size());
    for (char c : word) {
        lowerWord.push_back(static_cast<char>(std::tolower(static_cast<unsigned char>(c))));
    }
    if (builtInKeywords.count(lowerWord) > 0) {
        return true;
    }
    const auto customWords = std::atomic_load(&gCustomProgrammingKeywords);
    if (customWords->count(lowerWord) > 0) {
        return true;
    }
    return false;
}

void setCustomProgrammingKeywords(const std::string& content) {
    auto customWords = std::make_shared<KeywordSet>();
    std::stringstream ss(content);
    std::string word;
    while (ss >> word) {
        if (word.empty()) continue;
        if (word[0] == '#') {
            std::string comment;
            std::getline(ss, comment);
            continue;
        }
        std::string normalized;
        normalized.reserve(word.size());
        for (char c : word) {
            normalized.push_back(static_cast<char>(std::tolower(static_cast<unsigned char>(c))));
        }
        if (!normalized.empty()) {
            customWords->insert(normalized);
        }
    }
    std::atomic_store(
        &gCustomProgrammingKeywords,
        std::static_pointer_cast<const KeywordSet>(customWords)
    );
}

} // namespace vnkey
