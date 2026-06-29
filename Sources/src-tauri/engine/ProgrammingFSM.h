#ifndef PROGRAMMING_FSM_H
#define PROGRAMMING_FSM_H

#include <string>

namespace vnkey {

// Check if a word matches programming keywords or identifier patterns (camelCase, snake_case, etc.)
bool isValidProgrammingKeyword(const std::string& word);

// Check if a word matches built-in or custom programming keywords exactly
bool isBuiltInProgrammingKeyword(const std::string& word);

// Update user-defined programming keywords list
void setCustomProgrammingKeywords(const std::string& content);

} // namespace vnkey

#endif // PROGRAMMING_FSM_H
