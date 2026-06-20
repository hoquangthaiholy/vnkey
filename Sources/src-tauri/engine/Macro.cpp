//
//  Macro.cpp
//  VNKey
//
//  Created by Tuyen on 8/4/19.
//  Copyright © 2019 Tuyen Mai. All rights reserved.
//

#include "Macro.h"
#include "Vietnamese.h"
#include "Engine.h"
#include <memory.h>
#include <fstream>
#include <algorithm>
#include <unordered_map>

using namespace std;

struct MacroKeyHash {
    size_t operator()(const vector<Uint32>& key) const {
        size_t hash = key.size();
        for (const Uint32 code : key) {
            hash ^= std::hash<Uint32>()(code) + 0x9e3779b9 + (hash << 6) + (hash >> 2);
        }
        return hash;
    }
};

//main data
using MacroMap = unordered_map<vector<Uint32>, MacroData, MacroKeyHash>;
static MacroMap macroMap;

extern int vCodeTable;

static std::unordered_map<Uint16, std::pair<Uint32, int>> unicodeReverseMap;
static bool unicodeReverseMapInited = false;

static void initUnicodeReverseMap() {
    if (unicodeReverseMapInited) return;
    for (auto it = _codeTable[0].begin(); it != _codeTable[0].end(); ++it) {
        for (int z = 0; z < it->second.size(); z++) {
            unicodeReverseMap[it->second[z]] = { it->first, z };
        }
    }
    unicodeReverseMapInited = true;
}

struct CodeTableReverseEntry {
    Uint32 baseKey;
    int index;
};

static std::unordered_map<Uint16, CodeTableReverseEntry> codeTableReverseMap[5];
static bool codeTableReverseMapInited = false;

static void initCodeTableReverseMap() {
    if (codeTableReverseMapInited) return;
    for (int table = 0; table < 5; ++table) {
        for (auto it = _codeTable[table].begin(); it != _codeTable[table].end(); ++it) {
            for (int z = 0; z < it->second.size(); z++) {
                codeTableReverseMap[table][it->second[z]] = { it->first, z };
            }
        }
    }
    codeTableReverseMapInited = true;
}

static void convert(const string& str, vector<Uint32>& outData) {
    outData.clear();
    wstring data = utf8ToWideString(str);
    outData.reserve(data.size());
    Uint32 t = 0;
    for (size_t i = 0; i < data.size(); i++) {
        t = (Uint32)data[i];
        
        //find normal character fist
        auto character = _characterMap.find(t);
        if (character != _characterMap.end()) {
            outData.push_back(character->second);
            continue;
        }
        
        //find character which has tone/mark
        if (!unicodeReverseMapInited) {
            initUnicodeReverseMap();
        }
        auto it = unicodeReverseMap.find((Uint16)t);
        if (it != unicodeReverseMap.end()) {
            Uint32 baseKey = it->second.first;
            int idx = it->second.second;
            outData.push_back(_codeTable[vCodeTable][baseKey][idx] | CHAR_CODE_MASK);
            continue;
        }
        
        //find other character
        outData.push_back(t | PURE_CHARACTER_MASK); //mark it as pure character
    }
}

static vector<const MacroMap::value_type*> getSortedMacros() {
    vector<const MacroMap::value_type*> macros;
    macros.reserve(macroMap.size());
    for (const auto& item : macroMap) {
        macros.push_back(&item);
    }
    sort(macros.begin(), macros.end(), [](const MacroMap::value_type* lhs, const MacroMap::value_type* rhs) {
        return lhs->second.macroText < rhs->second.macroText;
    });
    return macros;
}

/**
 * data structure:
 * byte 0 and 1: macro count
 *
 * byte n: macroText size (macroTextSize)
 * byte n + macroTextSize: macroText data
 *
 * byte m, m+1: macroContentSize
 * byte m+1 + macroContentSize: macroContent data
 *
 * ...
 * next macro
 */
void initMacroMap(const Byte* pData, const int& size) {
    macroMap.clear();
    if (pData == NULL || size < 2) {
        return;
    }
    Uint16 macroCount = 0;
    Uint32 cursor = 0;
    memcpy(&macroCount, pData + cursor, 2);
    cursor += 2;
    macroMap.reserve(macroCount);
    Uint8 macroTextSize;
    Uint16 macroContentSize;
    for (int i = 0; i < macroCount; i++) {
        if (cursor >= (Uint32)size) {
            break;
        }
        macroTextSize = pData[cursor++];
        if (cursor + macroTextSize + 2 > (Uint32)size) {
            break;
        }
        string macroText((char*)pData + cursor, macroTextSize);
        cursor += macroTextSize;
        
        memcpy(&macroContentSize, pData + cursor, 2);
        cursor+=2;
        if (cursor + macroContentSize > (Uint32)size) {
            break;
        }
        string macroContent((char*)pData + cursor, macroContentSize);
        cursor += macroContentSize;
        
        MacroData data;
        data.macroText = macroText;
        data.macroContent = macroContent;
        
        vector<Uint32> key;
        convert(macroText, key);
        convert(macroContent, data.macroContentCode);
        
        macroMap[key] = data;
    }
}

void getMacroSaveData(vector<Byte>& outData) {
    outData.clear();
    Uint16 totalMacro = (Uint16)macroMap.size();
    size_t estimatedSize = 2;
    for (const auto& item : macroMap) {
        estimatedSize += 3 + item.second.macroText.size() + item.second.macroContent.size();
    }
    outData.reserve(estimatedSize);
    outData.push_back((Byte)totalMacro);
    outData.push_back((Byte)(totalMacro>>8));
    
    for (const auto* item : getSortedMacros()) {
        const MacroData& macro = item->second;
        outData.push_back((Byte)macro.macroText.size());
        for (size_t j = 0; j < macro.macroText.size(); j++) {
            outData.push_back(macro.macroText[j]);
        }
        
        Uint16 macroContentSize = (Uint16)macro.macroContent.size();
        outData.push_back((Byte)macroContentSize);
        outData.push_back(macroContentSize>>8);
        for (size_t j = 0; j < macroContentSize; j++) {
            outData.push_back(macro.macroContent[j]);
        }
    }
}

static bool modifyCaseUnicode(Uint32& code, const bool& isUpperCase=true) {
    const Uint32 oldCode = code;
    if (!(code & CHAR_CODE_MASK)) { //for normal char
        code &= isUpperCase ? CAPS_MASK :  ~CAPS_MASK;
        return code != oldCode;
    }
    
    if (vCodeTable >= 5) return false;
    if (!codeTableReverseMapInited) {
        initCodeTableReverseMap();
    }
    auto it = codeTableReverseMap[vCodeTable].find((Uint16)code);
    if (it != codeTableReverseMap[vCodeTable].end()) {
        Uint32 baseKey = it->second.baseKey;
        int idx = it->second.index;
        if (idx % 2 == 0 && !isUpperCase) {
            idx++;
        } else if (idx % 2 != 0 && isUpperCase) {
            idx--;
        }
        if (idx < _codeTable[vCodeTable][baseKey].size()) {
            code = _codeTable[vCodeTable][baseKey][idx] | CHAR_CODE_MASK;
        }
        return code != oldCode;
    }
    return false;
}

bool findMacro(const vector<Uint32>& key, vector<Uint32>& macroContentCode) {
    static vector<Uint32> lookupKey;
    lookupKey.clear();
    lookupKey.reserve(key.size());
    for (const Uint32 code : key) {
        lookupKey.push_back(getCharacterCode(code));
    }

    auto macro = macroMap.find(lookupKey);
    if (macro != macroMap.end()) {
        macroContentCode = macro->second.macroContentCode;
        return true;
    }
    if (vAutoCapsMacro) {
        bool allCaps = false;
        if (lookupKey.size() > 1 && modifyCaseUnicode(lookupKey[1], false)) {
            allCaps = true;
            for (size_t c = 2; c < lookupKey.size(); c++) {
                modifyCaseUnicode(lookupKey[c], false);
            }
        }
        
        if (!lookupKey.empty() && modifyCaseUnicode(lookupKey[0], false)) {
            macro = macroMap.find(lookupKey);
            if (macro != macroMap.end()) {
                macroContentCode = macro->second.macroContentCode;
                for (size_t c = 0; c < macroContentCode.size(); c++) {
                    if (c == 0 || allCaps) {
                        Uint16 character = keyCodeToCharacter(macroContentCode[c]);
                        if (character != 0) {
                            character = toupper(character);
                            auto upper = _characterMap.find(character);
                            if (upper != _characterMap.end()) {
                                macroContentCode[c] = upper->second;
                            }
                            continue;
                        }
                        if (macroContentCode[c] & CHAR_CODE_MASK) {
                            modifyCaseUnicode(macroContentCode[c]);
                        }
                    }
                }
                return true;
            }
        }
    }
    return false;
}

bool hasMacro(const string& macroName) {
    vector<Uint32> key;
    convert(macroName, key);
    return (macroMap.find(key) != macroMap.end());
}

void getAllMacro(vector<vector<Uint32>>& keys, vector<string>& macroTexts, vector<string>& macroContents) {
    keys.clear();
    macroTexts.clear();
    macroContents.clear();
    keys.reserve(macroMap.size());
    macroTexts.reserve(macroMap.size());
    macroContents.reserve(macroMap.size());
    for (const auto* item : getSortedMacros()) {
        keys.push_back(item->first);
        macroTexts.push_back(item->second.macroText);
        macroContents.push_back(item->second.macroContent);
    }
}

bool addMacro(const string& macroText, const string& macroContent) {
    if (macroText.empty() || macroText.size() > 0xFF || macroContent.size() > 0xFFFF) {
        return false;
    }
    vector<Uint32> key;
    convert(macroText, key);
    auto macro = macroMap.find(key);
    if (macro == macroMap.end()) { //add new macro
        if (macroMap.size() >= 0xFFFF) {
            return false;
        }
        MacroData data;
        data.macroText = macroText;
        data.macroContent = macroContent;
        convert(macroContent, data.macroContentCode);
        macroMap.emplace(std::move(key), std::move(data));
    } else { //edit this macro
        macro->second.macroContent = macroContent;
        convert(macroContent, macro->second.macroContentCode);
    }
    return true;
}

bool deleteMacro(const string& macroText) {
    vector<Uint32> key;
    convert(macroText, key);
    const auto macro = macroMap.find(key);
    if (macro != macroMap.end()) {
        macroMap.erase(macro);
        return true;
    }
    return false;
}

void onTableCodeChange() {
    // Reverse lookup data is table-independent, but converted macro output is not.
    for (auto& item : macroMap) {
        convert(item.second.macroContent, item.second.macroContentCode);
    }
}

void saveToFile(const string& path) {
    ofstream myfile;
    myfile.open(path.c_str());
    myfile << ";Compatible VNKey Macro Data file for UniKey*** version=1 ***\n";
    for (const auto* item : getSortedMacros()) {
        myfile << item->second.macroText << ":" << item->second.macroContent << "\n";
    }
    myfile.close();
}

void readFromFile(const string& path, const bool& append) {
    ifstream myfile(path.c_str());
    string line;
    int k = 0;
    size_t pos = 0;
    string name, content;
    if (myfile.is_open()) {
        if (!append) {
            macroMap.clear();
        }
        while (getline (myfile,line) ) {
            k++;
            if (k == 1) continue;
            pos = line.find(":");
            if (string::npos != pos) {
                name = line.substr(0, pos);
                content = line.substr(pos + 1, line.length() - pos - 1);
				while (name.compare("") == 0 && content.compare("") != 0) {
					pos = content.find(":");
					if (string::npos != pos) {
						name += ":";
						name += content.substr(0, pos);
						content = content.substr(pos + 1, line.length() - pos - 1);
					} else {
						break;
					}
				}

                if (name.compare("") != 0 && !hasMacro(name)) {
                    addMacro(name, content);
                }
            }
        }
        myfile.close();
    }
}
