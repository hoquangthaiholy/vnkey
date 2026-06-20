//
//  EnglishDictionary.h
//  VNKey
//

#ifndef EnglishDictionary_h
#define EnglishDictionary_h

#include <string>

/**
 * Returns true for common English words that are frequently changed by Telex.
 * Ambiguous raw sequences that may intentionally produce Vietnamese words are
 * intentionally excluded.
 */
bool isProtectedEnglishWord(const std::string& word);

#endif /* EnglishDictionary_h */
