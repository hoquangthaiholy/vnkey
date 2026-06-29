//
//  StringUtil.h
//  VNKey
//

#ifndef StringUtil_h
#define StringUtil_h

#include <string>
#include <cctype>

namespace vnkey {

inline std::string toLower(const std::string& s) {
    std::string lower;
    lower.reserve(s.size());
    for (char c : s) {
        lower.push_back(static_cast<char>(std::tolower(static_cast<unsigned char>(c))));
    }
    return lower;
}

inline std::string lowerAsciiOnly(const std::string &word) {
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

} // namespace vnkey

#endif // StringUtil_h
