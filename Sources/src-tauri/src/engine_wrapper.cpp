#include "Engine.h"
#include "../engine/EnglishDictionary.h"
#include "../engine/ProgrammingFSM.h"
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

extern "C" {
    int vFixChromiumBrowser = 0;
    int vFixRecommendBrowser = 1;
    int vFixSpotlight = 1;
    int vPerformLayoutCompat = 0;
    int vSendKeyStepByStep = 0;
    int vLanguage = 1;
    int vInputType = 0;
    int vFreeMark = 0;
    int vCodeTable = 0;
    int vSwitchKeyStatus = 0x20000C31; // DEFAULT_SWITCH_STATUS (Cmd + Shift + Space)
    int vCheckSpelling = 1;
    int vUseModernOrthography = 0;
    int vQuickTelex = 0;
    int vUseEnglishDictionary = 1;
    int vCheckProgrammingKeywords = 1;
    int vUseMacro = 1;
    int vUseMacroInEnglishMode = 0;
    int vAutoCapsMacro = 1;
    int vUseSmartSwitchKey = 1;
    int vUpperCaseFirstChar = 0;
    int vTempOffSpelling = 0;
    int vAllowConsonantZFWJ = 0;
    int vQuickStartConsonant = 0;
    int vQuickEndConsonant = 0;
    int vRememberCode = 1;
    int vOtherLanguage = 1;
    int vTempOffVNKey = 0;
    int vDisableHotkeys = 0;
    // FSM priority order: 0=VI, 1=EN, 2=PROG. Default: VI → PROG → EN
    int vFsmPriorityOrder[3] = {0, 2, 1};

    // Telex sub-options (only effective when vInputType == vTelex):
    //   vTelexWAsU=1  → W standalone at word start becomes ư (classic Telex)
    //   vTelexWAsU=0  → W is always a literal W when no vowel match
    int vTelexWAsU = 1;
    //   vTelexBracketAsO=1 → [ becomes ơ, ] becomes ư as special Telex keys (classic Telex)
    //   vTelexBracketAsO=0 → [ and ] are never treated as Vietnamese keys
    int vTelexBracketAsO = 1;

    char* vnkey_copy_string(const std::string& value) {
        char* result = static_cast<char*>(malloc(value.size() + 1));
        if (result == nullptr) {
            return nullptr;
        }
        memcpy(result, value.c_str(), value.size() + 1);
        return result;
    }

    void vnkey_free_string(char* value) {
        free(value);
    }

    int vnkey_macro_count() {
        std::vector<std::vector<Uint32>> keys;
        std::vector<std::string> texts;
        std::vector<std::string> contents;
        getAllMacro(keys, texts, contents);
        return static_cast<int>(texts.size());
    }

    char* vnkey_macro_text_at(int index) {
        std::vector<std::vector<Uint32>> keys;
        std::vector<std::string> texts;
        std::vector<std::string> contents;
        getAllMacro(keys, texts, contents);
        if (index < 0 || index >= static_cast<int>(texts.size())) {
            return nullptr;
        }
        return vnkey_copy_string(texts[index]);
    }

    char* vnkey_macro_content_at(int index) {
        std::vector<std::vector<Uint32>> keys;
        std::vector<std::string> texts;
        std::vector<std::string> contents;
        getAllMacro(keys, texts, contents);
        if (index < 0 || index >= static_cast<int>(contents.size())) {
            return nullptr;
        }
        return vnkey_copy_string(contents[index]);
    }

    bool vnkey_add_macro(const char* shortcut, const char* content) {
        return shortcut != nullptr && content != nullptr && addMacro(shortcut, content);
    }

    bool vnkey_delete_macro(const char* shortcut) {
        return shortcut != nullptr && deleteMacro(shortcut);
    }

    void vnkey_on_code_table_changed() {
        onTableCodeChange();
    }

    void vnkey_save_macros(const char* path) {
        if (path == nullptr) {
            return;
        }
        std::vector<Byte> data;
        getMacroSaveData(data);
        std::ofstream file(path, std::ios::binary | std::ios::trunc);
        file.write(reinterpret_cast<const char*>(data.data()), static_cast<std::streamsize>(data.size()));
    }

    void vnkey_load_macros(const char* path) {
        if (path == nullptr) {
            return;
        }
        std::ifstream file(path, std::ios::binary);
        if (!file) {
            return;
        }
        std::vector<Byte> data(
            (std::istreambuf_iterator<char>(file)),
            std::istreambuf_iterator<char>()
        );
        initMacroMap(data.data(), static_cast<int>(data.size()));
    }

    void vnkey_set_custom_english_words(const char* content) {
        if (content == nullptr) {
            setCustomEnglishWords("");
        } else {
            setCustomEnglishWords(content);
        }
    }

    void vnkey_set_custom_programming_keywords(const char* content) {
        if (content == nullptr) {
            vnkey::setCustomProgrammingKeywords("");
        } else {
            vnkey::setCustomProgrammingKeywords(content);
        }
    }

    void vnkey_set_fsm_priority_order(int a, int b, int c) {
        vFsmPriorityOrder[0] = a;
        vFsmPriorityOrder[1] = b;
        vFsmPriorityOrder[2] = c;
    }

    void vnkey_get_fsm_priority_order(int* a, int* b, int* c) {
        *a = vFsmPriorityOrder[0];
        *b = vFsmPriorityOrder[1];
        *c = vFsmPriorityOrder[2];
    }

    char* vnkey_convert_text(
        const char* source,
        int from_code,
        int to_code,
        bool all_caps,
        bool all_non_caps,
        bool caps_first_letter,
        bool caps_each_word,
        bool remove_mark
    ) {
        if (source == nullptr || from_code < 0 || from_code > 4 || to_code < 0 || to_code > 4) {
            return nullptr;
        }
        convertToolFromCode = static_cast<Uint8>(from_code);
        convertToolToCode = static_cast<Uint8>(to_code);
        convertToolToAllCaps = all_caps;
        convertToolToAllNonCaps = all_non_caps;
        convertToolToCapsFirstLetter = caps_first_letter;
        convertToolToCapsEachWord = caps_each_word;
        convertToolRemoveMark = remove_mark;
        return vnkey_copy_string(convertUtil(source));
    }

    int get_convert_tool_dont_alert() { return convertToolDontAlertWhenCompleted ? 1 : 0; }
    void set_convert_tool_dont_alert(int val) { convertToolDontAlertWhenCompleted = (val != 0); }

    int get_convert_tool_to_all_caps() { return convertToolToAllCaps ? 1 : 0; }
    void set_convert_tool_to_all_caps(int val) { convertToolToAllCaps = (val != 0); }

    int get_convert_tool_to_all_non_caps() { return convertToolToAllNonCaps ? 1 : 0; }
    void set_convert_tool_to_all_non_caps(int val) { convertToolToAllNonCaps = (val != 0); }

    int get_convert_tool_to_caps_first_letter() { return convertToolToCapsFirstLetter ? 1 : 0; }
    void set_convert_tool_to_caps_first_letter(int val) { convertToolToCapsFirstLetter = (val != 0); }

    int get_convert_tool_to_caps_each_word() { return convertToolToCapsEachWord ? 1 : 0; }
    void set_convert_tool_to_caps_each_word(int val) { convertToolToCapsEachWord = (val != 0); }

    int get_convert_tool_remove_mark() { return convertToolRemoveMark ? 1 : 0; }
    void set_convert_tool_remove_mark(int val) { convertToolRemoveMark = (val != 0); }

    int get_convert_tool_from_code() { return convertToolFromCode; }
    void set_convert_tool_from_code(int val) { convertToolFromCode = static_cast<Uint8>(val); }

    int get_convert_tool_to_code() { return convertToolToCode; }
    void set_convert_tool_to_code(int val) { convertToolToCode = static_cast<Uint8>(val); }

    int get_convert_tool_hotkey() { return convertToolHotKey; }
    void set_convert_tool_hotkey(int val) { convertToolHotKey = val; }

#if !defined(__APPLE__)
    bool start_event_tap() {
        return false;
    }

    void stop_event_tap() {
    }

    bool do_quick_convert() {
        return false;
    }
#endif
}
