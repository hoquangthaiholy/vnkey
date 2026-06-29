//
//  Engine.cpp
//  VNKey
//
//  Created by Tuyen on 1/18/19.
//  Copyright © 2019 Tuyen Mai. All rights reserved.
//
#include <algorithm>
#include "Engine.h"
#include "EnglishFSM.h"
#include "ProgrammingFSM.h"
#include <string.h>
#include <list>
#include <unordered_set>
#include "Macro.h"



static Uint16 ProcessingChar[][11] = {
    {KEY_S, KEY_F, KEY_R, KEY_X, KEY_J, KEY_A, KEY_O, KEY_E, KEY_W, KEY_D, KEY_Z}, //Telex
    {KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0}  //VNI
};

#define IS_KEY_Z(key) (ProcessingChar[vInputType][10] == key)
#define IS_KEY_D(key) (ProcessingChar[vInputType][9] == key)
#define IS_KEY_W(key) ((vInputType != vVNI) ? ProcessingChar[vInputType][8] == key : \
                                    (vInputType == vVNI ? (ProcessingChar[vInputType][8] == key || ProcessingChar[vInputType][7] == key) : false))
#define IS_KEY_DOUBLE(key) ((vInputType != vVNI) ? (ProcessingChar[vInputType][5] == key || ProcessingChar[vInputType][6] == key || ProcessingChar[vInputType][7] == key) :\
                                        (vInputType == vVNI ? ProcessingChar[vInputType][6] == key : false))
#define IS_KEY_S(key) (ProcessingChar[vInputType][0] == key)
#define IS_KEY_F(key) (ProcessingChar[vInputType][1] == key)
#define IS_KEY_R(key) (ProcessingChar[vInputType][2] == key)
#define IS_KEY_X(key) (ProcessingChar[vInputType][3] == key)
#define IS_KEY_J(key) (ProcessingChar[vInputType][4] == key)

#define IS_MARK_KEY(keyCode) (((vInputType != vVNI) && (keyCode == KEY_S || keyCode == KEY_F || keyCode == KEY_R || keyCode == KEY_J || keyCode == KEY_X)) || \
                                        (vInputType == vVNI && (keyCode == KEY_1 || keyCode == KEY_2 || keyCode == KEY_3 || keyCode == KEY_5 || keyCode == KEY_4)))
#define IS_BRACKET_KEY(key) (key == KEY_LEFT_BRACKET || key == KEY_RIGHT_BRACKET)

#define VSI vowelStartIndex
#define VEI vowelEndIndex
#define VWSM vowelWillSetMark
#define hBPC HookState.backspaceCount
#define hNCC HookState.newCharCount
#define hCode HookState.code
#define hExt HookState.extCode
#define hData HookState.charData
#define GET getCharacterCode
#define hMacroKey HookState.macroKey
#define hMacroData HookState.macroData

//Data to sendback to main program
vKeyHookState HookState;

//private data
/**
 * data structure of each element in TypingWord (Uint64)
 * first 2 byte is character code or key code.
 * bit 16: has caps or not
 * bit 17: has tone ^ or not
 * bit 18: has tone w or not
 * bit 19 - > 23: has mark or not (Sắc, huyền, hỏi, ngã, nặng)
 * bit 24: is standalone key? (w, [, ])
 * bit 25: is character code or keyboard code; 1: character code; 0: keycode
 */
static Uint32 TypingWord[MAX_BUFF];
static Byte _index = 0;
static vector<Uint32> _longWordHelper; //save the word when _index >= MAX_BUFF
static list<vector<Uint32>> _typingStates; //Aug 28th, 2019: typing helper, save long state of Typing word, can go back and modify the word
static list<vector<Uint32>> _typingStatesKeyStates;
static list<vector<Uint32>> _typingStatesRawTyping;
vector<Uint32> _typingStatesData;

/**
 * Use for restore key if invalid word
 */
static Uint32 KeyStates[MAX_BUFF];
static Byte _stateIndex = 0;
static vector<Uint32> _rawTyping;

static bool tempDisableKey = false;
static int capsElem;
static int key;
static int markElem;
static bool isCorect = false;
static bool isChanged = false;
static Byte vowelCount = 0;
static Byte vowelStartIndex = 0;
static Byte vowelEndIndex = 0;
static Byte vowelWillSetMark = 0;
static int i, ii, iii;
static int j;
static int k, kk;
static int l;
static bool isRestoredW;
static Uint16 keyForAEO;
static bool isCheckedGrammar;
static bool _isCaps = false;
static int _spaceCount = 0; //add: July 30th, 2019
static bool _hasHandledMacro = false; //for macro flag August 9th, 2019
Byte _upperCaseStatus = 0; //for Write upper case for the first letter; 2: will upper case
static bool _isCharKeyCode;
static vector<Uint32> _specialChar;
static bool _useSpellCheckingBefore;
static bool _hasHandleQuickConsonant;
static bool _willTempOffEngine = false;
static bool _liveProgrammingContext = false;
static bool _isAllCapsLockActive = false;

//function prototype
void findAndCalculateVowel(const bool& forGrammar=false);
void insertMark(const Uint32& markMask, const bool& canModifyFlag=true);

wstring utf8ToWideString(const string& str) {
    wstring result;
    result.reserve(str.size());
    size_t i = 0;
    while (i < str.size()) {
        unsigned char c = str[i];
        wchar_t wc = 0;
        if (c < 0x80) {
            wc = c;
            i += 1;
        } else if ((c & 0xE0) == 0xC0) {
            if (i + 1 >= str.size()) break;
            wc = ((c & 0x1F) << 6) | (str[i + 1] & 0x3F);
            i += 2;
        } else if ((c & 0xF0) == 0xE0) {
            if (i + 2 >= str.size()) break;
            wc = ((c & 0x0F) << 12) | ((str[i + 1] & 0x3F) << 6) | (str[i + 2] & 0x3F);
            i += 3;
        } else if ((c & 0xF8) == 0xF0) {
            if (i + 3 >= str.size()) break;
            uint32_t cp = ((c & 0x07) << 18) | ((str[i + 1] & 0x3F) << 12) | ((str[i + 2] & 0x3F) << 6) | (str[i + 3] & 0x3F);
            if (sizeof(wchar_t) == 2) {
                if (cp > 0xFFFF) {
                    cp -= 0x10000;
                    result.push_back((wchar_t)(0xD800 + ((cp >> 10) & 0x3FF)));
                    wc = (wchar_t)(0xDC00 + (cp & 0x3FF));
                } else {
                    wc = (wchar_t)cp;
                }
            } else {
                wc = (wchar_t)cp;
            }
            i += 4;
        } else {
            i += 1;
            continue;
        }
        result.push_back(wc);
    }
    return result;
}

string wideStringToUtf8(const wstring& str) {
    string result;
    result.reserve(str.size() * 3);
    for (size_t i = 0; i < str.size(); ++i) {
        uint32_t cp = str[i];
        if (sizeof(wchar_t) == 2 && cp >= 0xD800 && cp <= 0xDBFF && i + 1 < str.size()) {
            uint32_t low = str[i + 1];
            if (low >= 0xDC00 && low <= 0xDFFF) {
                cp = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00);
                ++i;
            }
        }
        if (cp < 0x80) {
            result.push_back((char)cp);
        } else if (cp < 0x800) {
            result.push_back((char)(0xC0 | ((cp >> 6) & 0x1F)));
            result.push_back((char)(0x80 | (cp & 0x3F)));
        } else if (cp < 0x10000) {
            result.push_back((char)(0xE0 | ((cp >> 12) & 0x0F)));
            result.push_back((char)(0x80 | ((cp >> 6) & 0x3F)));
            result.push_back((char)(0x80 | (cp & 0x3F)));
        } else if (cp < 0x200000) {
            result.push_back((char)(0xF0 | ((cp >> 18) & 0x07)));
            result.push_back((char)(0x80 | ((cp >> 12) & 0x3F)));
            result.push_back((char)(0x80 | ((cp >> 6) & 0x3F)));
            result.push_back((char)(0x80 | (cp & 0x3F)));
        }
    }
    return result;
}

void* vKeyInit() {
    _index = 0;
    _stateIndex = 0;
    _useSpellCheckingBefore = vCheckSpelling;
    _typingStatesData.clear();
    _typingStates.clear();
    _typingStatesKeyStates.clear();
    _typingStatesRawTyping.clear();
    _longWordHelper.clear();
    _rawTyping.clear();
    _liveProgrammingContext = false;
    return &HookState;
}

static bool isWordBreak(const vKeyEvent& event, const vKeyEventState&, const Uint16& data) {
    if (event == vKeyEvent::Mouse) {
        return true;
    }
    switch (data) {
        case KEY_ESC: case KEY_TAB: case KEY_ENTER:
#if !defined(LINUX) && !defined(_WIN32)
        case KEY_RETURN:
#endif
        case KEY_LEFT: case KEY_RIGHT: case KEY_DOWN: case KEY_UP:
        case KEY_COMMA: case KEY_DOT: case KEY_SLASH: case KEY_SEMICOLON:
        case KEY_QUOTE: case KEY_BACK_SLASH: case KEY_MINUS: case KEY_EQUALS:
        case KEY_BACKQUOTE: case KEY_LEFT_BRACKET: case KEY_RIGHT_BRACKET:
            return true;
#if _WIN32
        case VK_INSERT: case VK_HOME: case VK_END: case VK_DELETE:
        case VK_PRIOR: case VK_NEXT: case VK_SNAPSHOT: case VK_PRINT:
        case VK_SELECT: case VK_HELP: case VK_EXECUTE: case VK_NUMLOCK:
        case VK_SCROLL:
            return true;
#endif
        default:
            return false;
    }
}

static bool isMacroBreakCode(const int& data) {
    switch (data) {
        case KEY_RETURN: case KEY_COMMA: case KEY_DOT: case KEY_SLASH:
        case KEY_SEMICOLON: case KEY_QUOTE: case KEY_BACK_SLASH:
        case KEY_MINUS: case KEY_EQUALS:
            return true;
        default:
            return false;
    }
}

static bool isCharKeyCode(const Uint16 data) {
    switch (data) {
        case KEY_BACKQUOTE:
        case KEY_1: case KEY_2: case KEY_3: case KEY_4: case KEY_5:
        case KEY_6: case KEY_7: case KEY_8: case KEY_9: case KEY_0:
        case KEY_MINUS: case KEY_EQUALS: case KEY_LEFT_BRACKET:
        case KEY_RIGHT_BRACKET: case KEY_BACK_SLASH: case KEY_SEMICOLON:
        case KEY_QUOTE: case KEY_COMMA: case KEY_DOT: case KEY_SLASH:
            return true;
        default:
            return false;
    }
}

void setKeyData(const Byte& index, const Uint16& keyCode, const bool& isCaps) {
    if (index < 0 || index >= MAX_BUFF)
        return;
    TypingWord[index] = keyCode | (isCaps ? CAPS_MASK : 0);
}

bool _spellingOK = false;
bool _spellingFlag = false;
bool _spellingVowelOK = false;
Byte _spellingEndIndex = 0;

static std::string getOutputWordUtf8() {
    std::string word;
    for (int i = 0; i < _index; i++) {
        Uint32 cp = getCharacterCode(TypingWord[i]);
        if (cp == 0) continue;
        if (cp < 0x80) {
            word.push_back(static_cast<char>(cp));
        } else if (cp < 0x800) {
            word.push_back(static_cast<char>(0xC0 | (cp >> 6)));
            word.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
        } else if (cp < 0x10000) {
            word.push_back(static_cast<char>(0xE0 | (cp >> 12)));
            word.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
            word.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
        } else {
            word.push_back(static_cast<char>(0xF0 | (cp >> 18)));
            word.push_back(static_cast<char>(0x80 | ((cp >> 12) & 0x3F)));
            word.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
            word.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
        }
    }
    return word;
}

void checkSpelling(const bool& forceCheckVowel=false) {
    _spellingOK = false;
    _spellingVowelOK = true;
    _spellingEndIndex = _index;

    {
        std::string currentOutputWord = getOutputWordUtf8();
        if (!currentOutputWord.empty() && isCustomVietnameseWord(currentOutputWord)) {
            _spellingOK = true;
            _spellingVowelOK = true;
            tempDisableKey = false;
            return;
        }
    }

    
    if (_index > 0 && CHR(_index-1) == KEY_RIGHT_BRACKET) {
        _spellingEndIndex = _index-1;
    }
    
    if (_spellingEndIndex > 0) {
        j = 0;
        //Check first consonant
        if (IS_CONSONANT(CHR(0))) {
            for (i = 0; i < (int)_consonantTable.size(); i++) {
                _spellingFlag = false;
                if (_spellingEndIndex < _consonantTable[i].size())
                    _spellingFlag = true;
                for (j = 0; j < (int)_consonantTable[i].size(); j++) {
                    if (_spellingEndIndex > j &&
                        (_consonantTable[i][j] & ~(vQuickStartConsonant ? END_CONSONANT_MASK : 0)) != CHR(j) &&
                        (_consonantTable[i][j] & ~CONSONANT_ALLOW_MASK) != CHR(j)) {
                        _spellingFlag = true;
                        break;
                    }
                }
                if (_spellingFlag)
                    continue;
                
                break;
            }
        }
        
        if (j == _spellingEndIndex){ //for "d" case
            _spellingOK = true;
        }
        
        //check next vowel
        k = j;
        VSI = k;
        //August 23rd, 2019: fix case "que't"
        if (CHR(VSI) == KEY_U && k > 0 && k < _spellingEndIndex-1 && CHR(VSI-1) == KEY_Q) {
            k = k + 1;
            j = k;
            VSI = k;
        } else if (_index >= 2 && CHR(0) == KEY_G && CHR(1) == KEY_I && IS_CONSONANT(CHR(2))) {
            VSI = k = j = 1; //Sep 28th: fix gìn
        }
        for (l = 0; l < 3; l++) {
            if (k < _spellingEndIndex && !IS_CONSONANT(CHR(k))) {
                k++;
                VEI = k;
            }
        }
        if (k > j) { //has vowel,
            _spellingVowelOK = false;
            //check correct combined vowel
            if (k - j > 1 && forceCheckVowel) {
                vector<vector<Uint32>>& vowelSet = _vowelCombine[CHR(j)];
                for (l = 0; l < (int)vowelSet.size(); l++) {
                    _spellingFlag = false;
                    for (ii = 1; ii < (int)vowelSet[l].size(); ii++) {
                        if (j + ii - 1 < _spellingEndIndex && vowelSet[l][ii] != ((CHR(j + ii - 1) | (TypingWord[j + ii - 1] & TONEW_MASK) | (TypingWord[j + ii - 1] & TONE_MASK)))) {
                            _spellingFlag = true;
                            break;
                        }
                    }
                    if (_spellingFlag || (k < _spellingEndIndex && !vowelSet[l][0]) || (j + ii - 1 < _spellingEndIndex && !IS_CONSONANT(CHR(j + ii - 1))))
                        continue;
                    
                    _spellingVowelOK = true;
                    break;
                }
            } else if (!IS_CONSONANT(CHR(j))) {
                _spellingVowelOK = true;
            }
            
            //continue check last consonant
            for (ii = 0; ii < (int)_endConsonantTable.size(); ii++) {
                _spellingFlag = false;
   
                for (j = 0; j < (int)_endConsonantTable[ii].size(); j++) {
                    if (_spellingEndIndex > k+j &&
                        (_endConsonantTable[ii][j] & ~(vQuickEndConsonant ? END_CONSONANT_MASK : 0)) != CHR(k + j)) {
                        _spellingFlag = true;
                        break;
                    }
                }
                if (_spellingFlag)
                    continue;
                
                if (k + j >= _spellingEndIndex) {
                    _spellingOK = true;
                    break;
                }
            }
            
            //limit: end consonant "ch", "t" can not use with "~", "`", "?"
            if (_spellingOK) {
                if (_index >= 3 && CHR(_index-1) == KEY_H && CHR(_index-2) == KEY_C && !((TypingWord[_index-3] & MARK1_MASK) || (TypingWord[_index-3] & MARK5_MASK) || !(TypingWord[_index-3] & MARK_MASK))) {
                    _spellingOK = false;
                } else if (_index >= 2 && CHR(_index-1) == KEY_T && !((TypingWord[_index-2] & MARK1_MASK) || (TypingWord[_index-2] & MARK5_MASK) || !(TypingWord[_index-2] & MARK_MASK))) {
                    _spellingOK = false;
                }
            }
            
            //validate tone mark position: if a "special" vowel (ê/ô/â = TONE_MASK,
            //or ơ/ư/ă = TONEW_MASK) exists in the syllable, the tone mark must be
            //on that vowel, not on a plain vowel (e.g. hịên, sừơn are invalid).
            if (_spellingOK && (k - (int)VSI) >= 2) {
                int _markAt = -1, _specialAt = -1;
                for (int _vi = (int)VSI; _vi < k; _vi++) {
                    if (TypingWord[_vi] & MARK_MASK)
                        _markAt = _vi;
                    if ((TypingWord[_vi] & TONE_MASK) || (TypingWord[_vi] & TONEW_MASK))
                        _specialAt = _vi;
                }
                if (_markAt >= 0 && _specialAt >= 0 && _markAt != _specialAt)
                    _spellingOK = false;
            }
        }
    } else {
        _spellingOK = true;
    }
    tempDisableKey = !(_spellingOK && _spellingVowelOK);
    
    //cout<<"spelling vowel: "<<(_spellingVowelOK ? "OK": "Err")<<endl;
    //cout<<"spelling: "<<(_spellingOK ? "OK": "Err")<<endl<<endl;
}

void checkGrammar(const int& deltaBackSpace) {
    if (_index <= 1 || _index >= MAX_BUFF)
        return;
    
    findAndCalculateVowel(true);
    if (vowelCount == 0)
        return;
    
    isCheckedGrammar = false;
    
    l = VSI;
    
    //if N key for case: "thuơn", "ưoi", "ưom", "ưoc"
    if (_index >= 3) {
        for (i = _index-1; i >= 0; i--) {
            if (CHR(i) == KEY_N || CHR(i) == KEY_C || CHR(i) == KEY_I ||
                CHR(i) == KEY_M || CHR(i) == KEY_P || CHR(i) == KEY_T) {
                if (i - 2 >= 0 && CHR(i - 1) == KEY_O && CHR(i - 2) == KEY_U) {
                    if ((TypingWord[i-1] & TONEW_MASK) ^ (TypingWord[i-2] & TONEW_MASK)) {
                        TypingWord[i - 2] |= TONEW_MASK;
                        TypingWord[i - 1] |= TONEW_MASK;
                        isCheckedGrammar = true;
                        break;
                    }
                }
            }
        }
    }
    
    //check mark
    if (_index >= 2) {
        for (i = l; i <= VEI; i++) {
            if (TypingWord[i] & MARK_MASK) {
                Uint32 mark = TypingWord[i] & MARK_MASK;
                TypingWord[i] &= ~MARK_MASK;
                insertMark(mark, false);
                if (i != vowelWillSetMark)
                    isCheckedGrammar = true;
                break;
            }
        }
    }
    
    //re-arrange data to sendback
    if (isCheckedGrammar) {
        if (hCode ==vDoNothing)
            hCode = vWillProcess;
        hBPC = 0;
        
        for (i = _index - 1; i >= l; i--) {
            hBPC++;
            hData[_index - 1 - i] = GET(TypingWord[i]);
        }
        hNCC = hBPC;
        hBPC += deltaBackSpace;
        hExt = 4;
    }
}

void insertKey(const Uint16& keyCode, const bool& isCaps, const bool& isCheckSpelling=true) {
    if (_index >= MAX_BUFF) {
        _longWordHelper.push_back(TypingWord[0]); //save long word
        //left shift
        for (iii = 0; iii < MAX_BUFF - 1; iii++) {
            TypingWord[iii] = TypingWord[iii + 1];
        }
        setKeyData(_index-1, keyCode, isCaps);
    } else {
        setKeyData(_index++, keyCode, isCaps);
    }
    
    if (vCheckSpelling && isCheckSpelling)
        checkSpelling();
    
    //allow d after consonant
    if (keyCode == KEY_D && _index - 2 >= 0 && IS_CONSONANT(CHR(_index - 2)))
        tempDisableKey = false;
}

void insertState(const Uint16& keyCode, const bool& isCaps) {
    if (_stateIndex >= MAX_BUFF) {
        //left shift
        for (iii = 0; iii < MAX_BUFF - 1; iii++) {
            KeyStates[iii] = KeyStates[iii + 1];
        }
        KeyStates[_stateIndex-1] = keyCode | (isCaps ? CAPS_MASK : 0);
    } else {
        KeyStates[_stateIndex++] = keyCode | (isCaps ? CAPS_MASK : 0);
    }
}

void saveWord() {
    //save word history
    if (hCode != vReplaceMaro) {
        if (_index > 0) {
            if (_longWordHelper.size() > 0) { //save long word first
                _typingStatesData.clear();
                for (i = 0; i < (int)_longWordHelper.size(); i++) {
                    if (i != 0 && i % MAX_BUFF == 0) { //save if overflow
                        _typingStates.push_back(_typingStatesData);
                        _typingStatesData.clear();
                        _typingStatesKeyStates.push_back(vector<Uint32>());
                        _typingStatesRawTyping.push_back(vector<Uint32>());
                    }
                    _typingStatesData.push_back(_longWordHelper[i]);
                }
                _typingStates.push_back(_typingStatesData);
                _typingStatesKeyStates.push_back(vector<Uint32>());
                _typingStatesRawTyping.push_back(vector<Uint32>());
                _longWordHelper.clear();
            }
            
            //save current word
            _typingStatesData.clear();
            for (i = 0; i < _index; i++) {
                _typingStatesData.push_back(TypingWord[i]);
            }
            _typingStates.push_back(_typingStatesData);
            
            vector<Uint32> currentKeyStates;
            for (i = 0; i < _stateIndex; i++) {
                currentKeyStates.push_back(KeyStates[i]);
            }
            _typingStatesKeyStates.push_back(currentKeyStates);
            _typingStatesRawTyping.push_back(_rawTyping);
        }
    } else { //save macro words
        _typingStatesData.clear();
        for (i = 0; i < (int)hMacroData.size(); i++) {
            if (i != 0 && i % MAX_BUFF == 0) { //break if overflow
                _typingStates.push_back(_typingStatesData);
                _typingStatesData.clear();
                _typingStatesKeyStates.push_back(vector<Uint32>());
                _typingStatesRawTyping.push_back(vector<Uint32>());
            }
            _typingStatesData.push_back(hMacroData[i]);
        }
        _typingStates.push_back(_typingStatesData);
        
        vector<Uint32> macroKeyStates;
        for (i = 0; i < (int)hMacroKey.size(); i++) {
            macroKeyStates.push_back(hMacroKey[i]);
        }
        _typingStatesKeyStates.push_back(macroKeyStates);
        _typingStatesRawTyping.push_back(macroKeyStates);
    }
}

void saveWord(const Uint32& keyCode, const int& count) {
    _typingStatesData.clear();
    vector<Uint32> keys;
    for (i = 0; i < count; i++) {
        _typingStatesData.push_back(keyCode);
        keys.push_back(keyCode);
    }
    _typingStates.push_back(_typingStatesData);
    _typingStatesKeyStates.push_back(keys);
    _typingStatesRawTyping.push_back(keys);
}

void saveSpecialChar() {
    _typingStatesData.clear();
    vector<Uint32> keys;
    for (i = 0; i < (int)_specialChar.size(); i++) {
        _typingStatesData.push_back(_specialChar[i]);
        keys.push_back(_specialChar[i]);
    }
    _typingStates.push_back(_typingStatesData);
    _typingStatesKeyStates.push_back(keys);
    _typingStatesRawTyping.push_back(keys);
    _specialChar.clear();
}

void restoreLastTypingState() {
    if (_typingStates.size() > 0) {
        _typingStatesData = _typingStates.back();
        _typingStates.pop_back();
        
        vector<Uint32> poppedKeyStates;
        vector<Uint32> poppedRawTyping;
        if (!_typingStatesKeyStates.empty()) {
            poppedKeyStates = _typingStatesKeyStates.back();
            _typingStatesKeyStates.pop_back();
        }
        if (!_typingStatesRawTyping.empty()) {
            poppedRawTyping = _typingStatesRawTyping.back();
            _typingStatesRawTyping.pop_back();
        }
        
        if (_typingStatesData.size() > 0){
            if (_typingStatesData[0] == KEY_SPACE) {
                _spaceCount = (int)_typingStatesData.size();
                _index = 0;
                _stateIndex = 0;
                _rawTyping.clear();
            } else if (isCharKeyCode((Uint16)_typingStatesData[0])) {
                _index = 0;
                _specialChar = _typingStatesData;
                _stateIndex = 0;
                _rawTyping.clear();
                checkSpelling();
            } else {
                for (i = 0; i < (int)_typingStatesData.size(); i++) {
                    TypingWord[i] = _typingStatesData[i];
                }
                _index = (Byte)_typingStatesData.size();
                
                _stateIndex = (Byte)poppedKeyStates.size();
                for (i = 0; i < (int)poppedKeyStates.size(); i++) {
                    KeyStates[i] = poppedKeyStates[i];
                }
                _rawTyping = poppedRawTyping;
            }
        }
    }
}

void startNewSession() {
    _index = 0;
    hBPC = 0;
    hNCC = 0;
    tempDisableKey = false;
    _stateIndex = 0;
    _hasHandledMacro = false;
    _hasHandleQuickConsonant = false;
    _longWordHelper.clear();
    _rawTyping.clear();
    _isAllCapsLockActive = false;
}

void checkCorrectVowel(vector<vector<Uint16>>& charset, int& i, int& k, const Uint16& markKey) {
    //ignore "qu" case
    if (_index >= 2 && CHR(_index-1) == KEY_U && CHR(_index-2) == KEY_Q) {
        isCorect = false;
        return;
    }
    k = _index - 1;
    for (j = (int)charset[i].size() - 1; j >= 0; j--) {
        if ((charset[i][j] & ~(vQuickEndConsonant ? END_CONSONANT_MASK : 0)) != CHR(k)) {
            isCorect = false;
            return;
        }
        k--;
        if (k < 0)
            break;
    }
    
    //limit mark for end consonant: "C", "T"
    if (isCorect && charset[i].size() > 1 && (IS_KEY_F(markKey) || IS_KEY_X(markKey) || IS_KEY_R(markKey))) {
        if (charset[i][1] == KEY_C || charset[i][1] == KEY_T) {
            isCorect = false;
        } else if (charset[i].size() > 2 && (charset[i][2] == KEY_T)) {
            isCorect = false;
        }
    }
    
    if (isCorect && k >= 0) {
        if (CHR(k) == CHR(k+1)) {
            isCorect = false;
        }
    }
}

Uint32 getCharacterCode(const Uint32& data) {
    capsElem = (data & CAPS_MASK) ? 0 : 1;
    key = data & CHAR_MASK;
    if (data & MARK_MASK) { //has mark
        markElem = -2;
        switch (data & MARK_MASK) {
            case MARK1_MASK:
                markElem = 0;
                break;
            case MARK2_MASK:
                markElem = 2;
                break;
            case MARK3_MASK:
                markElem = 4;
                break;
            case MARK4_MASK:
                markElem = 6;
                break;
            case MARK5_MASK:
                markElem = 8;
                break;
        }
        markElem += capsElem;
        
        switch (key) {
            case KEY_A:
            case KEY_O:
            case KEY_U:
            case KEY_E:
                if ((data & TONE_MASK) == 0 && (data & TONEW_MASK) == 0)
                    markElem += 4;
                break;
        }
        
        if (data & TONE_MASK) {
            key |= TONE_MASK;
        } else if (data & TONEW_MASK) {
            key |= TONEW_MASK;
        }
        const auto character = _codeTable[vCodeTable].find(key);
        if (character == _codeTable[vCodeTable].end())
            return data; //not found
        
        return character->second[markElem] | CHAR_CODE_MASK;
    } else { //doesn't has mark
        const auto character = _codeTable[vCodeTable].find(key);
        if (character == _codeTable[vCodeTable].end())
            return data; //not found
        
        if (data & TONE_MASK) {
            return character->second[capsElem] | CHAR_CODE_MASK;
        } else if (data & TONEW_MASK) {
            return character->second[capsElem + 2] | CHAR_CODE_MASK;
        } else {
            return data; //not found
        }
    }
    
    return 0;
}

void findAndCalculateVowel(const bool& forGrammar) {
    vowelCount = 0;
    VSI = VEI = 0;
    for (iii = _index - 1; iii >= 0; iii--) {
        if (IS_CONSONANT(CHR(iii))) {
            if (vowelCount > 0)
                break;
        } else {  //is vowel
            if (vowelCount == 0)
                VEI = iii;
            if (!forGrammar) {
                if ((iii-1 >= 0 && (CHR(iii) == KEY_I && CHR(iii-1) == KEY_G)) ||
                    (iii-1 >= 0 && (CHR(iii) == KEY_U && CHR(iii-1) == KEY_Q))) {
                    break;
                }
            }
            VSI = iii;
            vowelCount++;
        }
    }
    //August 26th, 2019: don't count "u" at "q u" as a vowel
    if (VSI - 1 >= 0 && CHR(VSI) == KEY_U && CHR(VSI-1) == KEY_Q) {
        VSI++;
        vowelCount--;
    }
}

void removeMark() {
    findAndCalculateVowel(true);
    isChanged = false;
    if (_index > 0) {
        for (i = VSI; i <= VEI; i++) {
            if (TypingWord[i] & MARK_MASK) {
                TypingWord[i] &= ~MARK_MASK;
                isChanged = true;
            }
        }
    }
    if (isChanged) {
        hCode = vWillProcess;
        hBPC = 0;
        
        for (i = _index - 1; i >= VSI; i--) {
            hBPC++;
            hData[_index - 1 - i] = GET(TypingWord[i]);
        }
        hNCC = hBPC;
    } else {
        hCode = vDoNothing;
    }
}

bool canHasEndConsonant() {
    vector<vector<Uint32>>& vo = _vowelCombine[CHR(VSI)];
    for (ii = 0; ii < (int)vo.size(); ii++) {
        kk = VSI;
        for (iii = 1; iii < (int)vo[ii].size(); iii++) {
            if (kk > VEI || ((CHR(kk) | (TypingWord[kk] & TONE_MASK) | (TypingWord[kk] & TONEW_MASK)) != vo[ii][iii])) {
                break;
            }
            kk++;
        }
        if (iii >= (int)vo[ii].size()) {
            return vo[ii][0] == 1;
        }
    }
    return false;
}

void handleModernMark() {
    //default
    VWSM = VEI;
    hBPC = (_index - VEI);
    
    //rule 2
    if (vowelCount == 3 && ((CHR(VSI) == KEY_O && CHR(VSI+1) == KEY_A && CHR(VSI+2) == KEY_I) ||
                            (CHR(VSI) == KEY_U && CHR(VSI+1) == KEY_Y && CHR(VSI+2) == KEY_U) ||
                            (CHR(VSI) == KEY_O && CHR(VSI+1) == KEY_E && CHR(VSI+2) == KEY_O) ||
                            (CHR(VSI) == KEY_U && CHR(VSI+1) == KEY_Y && CHR(VSI+2) == KEY_A))) {
        VWSM = VSI + 1;
        hBPC = _index - VWSM;
    } else if ((CHR(VSI) == KEY_O && CHR(VSI+1) == KEY_I) ||
               (CHR(VSI) == KEY_A && CHR(VSI+1) == KEY_I) ||
               (CHR(VSI)== KEY_U && CHR(VSI+1) == KEY_I) ) {
        
        VWSM = VSI;
        hBPC = _index - VWSM;
    } else if (CHR(VEI-1) == KEY_A && CHR(VEI) == KEY_Y) {
        VWSM = VEI - 1;
        hBPC = (_index - VEI) + 1;
    } else if (CHR(VSI) == KEY_U && CHR(VSI+1) == KEY_O) {
        VWSM = VSI + 1;
        hBPC = _index - VWSM;
    } else if (CHR(VSI+1) == KEY_O || CHR(VSI+1) == KEY_U) {
        VWSM = VEI - 1;
        hBPC = (_index - VEI) + 1;
    } else if (CHR(VSI) == KEY_O || CHR(VSI) == KEY_U) {
        VWSM = VEI;
        hBPC = (_index - VEI);
    }
    
    //rule 3.1
    if ((CHR(VSI) == KEY_I && CHR(VSI+1) == KEY_E && (TypingWord[VSI+1] & TONE_MASK)) ||
        (CHR(VSI) == KEY_Y && CHR(VSI+1) == KEY_E && (TypingWord[VSI+1] & TONE_MASK)) ||
        (CHR(VSI) == KEY_U && CHR(VSI+1) == KEY_O && (TypingWord[VSI+1] & TONE_MASK)) ||
        (CHR(VSI) == KEY_U && (TypingWord[VSI] & TONEW_MASK) && CHR(VSI+1) == KEY_O && (TypingWord[VSI+1] & TONEW_MASK))){
        
        if (VSI+2 < _index) {
            if (CHR(VSI+2) == KEY_P || CHR(VSI+2) == KEY_T ||
                CHR(VSI+2) == KEY_M || CHR(VSI+2) == KEY_N ||
                CHR(VSI+2) == KEY_O || CHR(VSI+2) == KEY_U ||
                CHR(VSI+2) == KEY_I || CHR(VSI+2) == KEY_C ||
                (VSI+3 < _index && CHR(VSI+2) == KEY_C && CHR(VSI+2) == KEY_H) ||
                (VSI+3 < _index && CHR(VSI+2) == KEY_N && CHR(VSI+2) == KEY_H) ||
                (VSI+3 < _index && CHR(VSI+2) == KEY_N && CHR(VSI+2) == KEY_G)) {
                
                VWSM = VSI + 1;
                hBPC = _index - VWSM;
            } else {
                VWSM = VSI;
                hBPC = _index - VWSM;
            }
        } else {
            VWSM = VSI;
            hBPC = _index - VWSM;
        }
    }
    //rule 3.2
    else if ((CHR(VSI) == KEY_I && CHR(VSI+1) == KEY_A) ||
             (CHR(VSI) == KEY_Y && CHR(VSI+1) == KEY_A) ||
             (CHR(VSI) == KEY_U && CHR(VSI+1) == KEY_A) ||
             (CHR(VSI) == KEY_U && CHR(VSI+1) == KEY_U && (TypingWord[VSI+1] & TONEW_MASK))){
        
        VWSM = VSI;
        hBPC = _index - VWSM;
    }
    
    //rule 4
    if (vowelCount == 2) {
        if (((CHR(VSI) == KEY_I) && (CHR(VSI+1) == KEY_A)) ||
            ((CHR(VSI) == KEY_I) && (CHR(VSI+1) == KEY_U)) ||
            ((CHR(VSI) == KEY_I) && (CHR(VSI+1) == KEY_O))) {
            
            if (VSI == 0 || (CHR(VSI-1) != KEY_G)) { //dont have G
                VWSM = VSI;
                hBPC = _index - VWSM;
            } else {
                VWSM = VSI + 1;
                hBPC = _index - VWSM;
            }
        } else if ((CHR(VSI) == KEY_U) && (CHR(VSI+1) == KEY_A)) {
            if (VSI == 0 || (CHR(VSI-1) != KEY_Q)) { //dont have Q
                if (VEI + 1 >= _index || !canHasEndConsonant()) {
                    VWSM = VSI;
                    hBPC = _index - VWSM;
                }
            } else {
                VWSM = VSI + 1;
                hBPC = _index - VWSM;
            }
        } else if ((CHR(VSI) == KEY_O) && (CHR(VSI+1) == KEY_O)) { //thoong
            VWSM = VEI;
            hBPC = _index - VWSM;
        }
    }
}

void handleOldMark() {
    //default
    if (vowelCount == 0 && CHR(VEI) == KEY_I)
        VWSM = VEI;
    else
        VWSM = VSI;
    hBPC = (_index - VWSM);
    
    //rule 2
    if (vowelCount == 3 || (VEI + 1 < _index && IS_CONSONANT(CHR(VEI + 1)) && canHasEndConsonant())) {
        VWSM = VSI + 1;
        hBPC = _index - VWSM;
    }
    
    //rule 3
    for (ii = VSI; ii <= VEI; ii++) {
        if ((CHR(ii) == KEY_E && TypingWord[ii] & TONE_MASK) || (CHR(ii) == KEY_O && TypingWord[ii] & TONEW_MASK)) {
            VWSM = ii;
            hBPC = _index - VWSM;
            break;
        }
    }
    
    hNCC = hBPC;
}

void insertMark(const Uint32& markMask, const bool& canModifyFlag) {
    vowelCount = 0;
    
    if (canModifyFlag)
        hCode = vWillProcess;
    hBPC = hNCC = 0;
    
    findAndCalculateVowel();
    VWSM = 0;
    
    //detect mark position
    if (vowelCount == 1) {
        VWSM = VEI;
        hBPC = (_index - VEI);
    } else { //vowel = 2 or 3
        if (vUseModernOrthography == 0)
            handleOldMark();
        else
            handleModernMark();
        if (TypingWord[VEI] & TONE_MASK || TypingWord[VEI] & TONEW_MASK)
            vowelWillSetMark = VEI;
    }
    
    //send data
    kk = _index - 1 - VSI;
    //if duplicate same mark -> restore
    if (TypingWord[VWSM] & markMask) {
        
        TypingWord[VWSM] &= ~MARK_MASK;
        if (canModifyFlag) {
            hCode = vRestore;
            if (markMask == MARK1_MASK || markMask == MARK2_MASK || markMask == MARK3_MASK || markMask == MARK4_MASK || markMask == MARK5_MASK) {
                if (!_rawTyping.empty()) _rawTyping.pop_back();
                if (_stateIndex > 0) _stateIndex--;
            }
        }
        for (ii = VSI; ii < _index; ii++) {
            TypingWord[ii] &= ~MARK_MASK;
            hData[kk--] = GET(TypingWord[ii]);
        }
        //_index = 0;
        tempDisableKey = true;
    } else {
        //remove other mark
        TypingWord[VWSM] &= ~MARK_MASK;
        
        //add mark
        TypingWord[VWSM] |= markMask;
        for (ii = VSI; ii < _index; ii++) {
            if (ii != VWSM) { //remove mark for other vowel
                TypingWord[ii] &= ~MARK_MASK;
            }
            hData[kk--] = GET(TypingWord[ii]);
        }
        
        hBPC = _index - VSI;
    }
    hNCC = hBPC;
}

void insertD(const Uint16& data, const bool& isCaps) {
    (void)data;
    (void)isCaps;
    hCode = vWillProcess;
    hBPC = 0;
    for (ii = _index - 1; ii >= 0; ii--) {
        hBPC++;
        if (CHR(ii) == KEY_D) { //reverse unicode char
            if (TypingWord[ii] & TONE_MASK) {
                //restore and disable temporary
                hCode = vRestore;
                TypingWord[ii] &= ~TONE_MASK;
                hData[_index - 1 - ii] = TypingWord[ii];
                tempDisableKey = true;
                break;
            } else {
                TypingWord[ii] |= TONE_MASK;
                hData[_index - 1 - ii] = GET(TypingWord[ii]);
            }
            break;
        } else { //preresent old char
            hData[_index - 1 - ii] = GET(TypingWord[ii]);
        }
    }
    hNCC = hBPC;
}

void insertAOE(const Uint16& data, const bool& isCaps) {
    (void)isCaps;
    findAndCalculateVowel();
    
    //remove W tone
    for (ii = VSI; ii <= VEI; ii++) {
        TypingWord[ii] &= ~TONEW_MASK;
    }
    
    hCode = vWillProcess;
    hBPC = 0;
    
    for (ii = _index - 1; ii >= 0; ii--) {
        hBPC++;
        if (CHR(ii) == data) { //reverse unicode char
            if (TypingWord[ii] & TONE_MASK) {
                //restore and disable temporary
                hCode = vRestore;
                TypingWord[ii] &= ~TONE_MASK;
                if (!_rawTyping.empty()) _rawTyping.pop_back();
                if (_stateIndex > 0) _stateIndex--;
                hData[_index - 1 - ii] = TypingWord[ii];
                //_index = 0;
                if (data != KEY_O) //case thoòng
                    tempDisableKey = true;
                break;
            } else {
                TypingWord[ii] |= TONE_MASK;
                if (!IS_KEY_D(data))
                    TypingWord[ii] &= ~TONEW_MASK;
                hData[_index - 1 - ii] = GET(TypingWord[ii]);
                
            }
            break;
        } else { //preresent old char
            hData[_index - 1 - ii] = GET(TypingWord[ii]);
        }
    }
    hNCC = hBPC;
}

void insertW(const Uint16& data, const bool& isCaps) {
    (void)data;
    (void)isCaps;
    isRestoredW = false;
    
    findAndCalculateVowel();
    
    //remove ^ tone
    for (ii = VSI; ii <= VEI; ii++) {
        TypingWord[ii] &= ~TONE_MASK;
    }
    
    if (vowelCount > 1) {
        hBPC = _index - VSI;
        hNCC = hBPC;
        
        if (((TypingWord[VSI] & TONEW_MASK) && (TypingWord[VSI+1] & TONEW_MASK)) ||
            ((TypingWord[VSI] & TONEW_MASK) && CHR(VSI+1) == KEY_I) ||
            ((TypingWord[VSI] & TONEW_MASK) && CHR(VSI+1) == KEY_A)){
            //restore and disable temporary
            hCode = vRestore;
            if (!_rawTyping.empty()) _rawTyping.pop_back();
            if (_stateIndex > 0) _stateIndex--;
            
            for (ii = VSI; ii < _index; ii++) {
                TypingWord[ii] &= ~TONEW_MASK;
                hData[_index - 1 - ii] = GET(TypingWord[ii]) & ~STANDALONE_MASK;
            }
            isRestoredW = true;
            tempDisableKey = true;
        } else {
            hCode = vWillProcess;
            
            if ((CHR(VSI) == KEY_U && CHR(VSI+1) == KEY_O)) {
                if (VSI - 2 >= 0 && TypingWord[VSI - 2] == KEY_T && TypingWord[VSI - 1] == KEY_H) {
                    TypingWord[VSI+1] |= TONEW_MASK;
                    if (VSI + 2 < _index && CHR(VSI+2) == KEY_N) {
                        TypingWord[VSI] |= TONEW_MASK;
                    }
                } else if (VSI - 1 >= 0 && TypingWord[VSI - 1] == KEY_Q) {
                    TypingWord[VSI+1] |= TONEW_MASK;
                } else {
                    TypingWord[VSI] |= TONEW_MASK;
                    TypingWord[VSI+1] |= TONEW_MASK;
                }
            } else if ((CHR(VSI) == KEY_U && CHR(VSI+1) == KEY_A) ||
                       (CHR(VSI) == KEY_U && CHR(VSI+1) == KEY_I) ||
                       (CHR(VSI) == KEY_U && CHR(VSI+1) == KEY_U) ||
                       (CHR(VSI) == KEY_O && CHR(VSI+1) == KEY_I)) {
                TypingWord[VSI] |= TONEW_MASK;
            } else if ((CHR(VSI) == KEY_I && CHR(VSI+1) == KEY_O) ||
                       (CHR(VSI) == KEY_O && CHR(VSI+1) == KEY_A)) {
                TypingWord[VSI+1] |= TONEW_MASK;
            } else {
                //don't do anything
                tempDisableKey = true;
                isChanged = false;
                hCode = vDoNothing;
            }
            
            for (ii = VSI; ii < _index; ii++) {
                hData[_index - 1 - ii] = GET(TypingWord[ii]);
            }
        }
        
        return;
    }
    
    hCode = vWillProcess;
    hBPC = 0;
    
    for (ii = _index - 1; ii >= 0; ii--) {
        if (ii < VSI)
            break;
        hBPC++;
        switch (CHR(ii)) {
            case KEY_A:
            case KEY_U:
            case KEY_O:
                if (TypingWord[ii] & TONEW_MASK) {
                    //restore and disable temporary
                    if (TypingWord[ii] & STANDALONE_MASK) {
                        hCode = vWillProcess;
                        if (CHR(ii) == KEY_U){
                            TypingWord[ii] = KEY_W | ((TypingWord[ii] & CAPS_MASK) ? CAPS_MASK : 0);
                        } else if (CHR(ii) == KEY_O) {
                            hCode = vRestore;
                            TypingWord[ii] = KEY_O | ((TypingWord[ii] & CAPS_MASK) ? CAPS_MASK : 0);
                            isRestoredW = true;
                            if (!_rawTyping.empty()) _rawTyping.pop_back();
                            if (_stateIndex > 0) _stateIndex--;
                        }
                        hData[_index - 1 - ii] = TypingWord[ii];
                    } else {
                        hCode = vRestore;
                        TypingWord[ii] &= ~TONEW_MASK;
                        if (!_rawTyping.empty()) _rawTyping.pop_back();
                        if (_stateIndex > 0) _stateIndex--;
                        hData[_index - 1 - ii] = TypingWord[ii];
                        isRestoredW = true;
                        //_index++;
                    }
                    
                    tempDisableKey = true;
                } else {
                    TypingWord[ii] |= TONEW_MASK;
                    TypingWord[ii] &= ~TONE_MASK;
                    hData[_index - 1 - ii] = GET(TypingWord[ii]);
                }
                break;
                
            default:
                hData[_index - 1 - ii] = GET(TypingWord[ii]);
                break;
        }
    }
    hNCC = hBPC;
    
    if (isRestoredW) {
        //_index = 0;
    }
}

void reverseLastStandaloneChar(const Uint32& keyCode, const bool& isCaps) {
    hCode = vWillProcess;
    hBPC = 0;
    hNCC = 1;
    hExt = 4;
    TypingWord[_index - 1] = (keyCode | TONEW_MASK | STANDALONE_MASK | (isCaps ? CAPS_MASK : 0));
    hData[0] = GET(TypingWord[_index - 1]);
}

void checkForStandaloneChar(const Uint16& data, const bool& isCaps, const Uint32& keyWillReverse) {
    if (_index > 0 &&
        CHR(_index - 1) == keyWillReverse &&
        TypingWord[_index - 1] & TONEW_MASK) {
        hCode = vWillProcess;
        hBPC = 1;
        hNCC = 1;
        TypingWord[_index - 1] = data | (isCaps ? CAPS_MASK : 0);
        hData[0] = GET(TypingWord[_index - 1]);
        return;
    }
    
    //check standalone w -> ư
    
    if (_index > 0 && CHR(_index-1) == KEY_U && keyWillReverse == KEY_O) {
        insertKey(keyWillReverse, isCaps);
        reverseLastStandaloneChar(keyWillReverse, isCaps);
        return;
    }
    
    if (_index == 0) { //zero char
        insertKey(data, isCaps, false);
        reverseLastStandaloneChar(keyWillReverse, isCaps);
        return;
    } else if (_index == 1) { //1 char
        for (i = 0; i < (int)_standaloneWbad.size(); i++) {
            if (CHR(0) == _standaloneWbad[i]) {
                insertKey(data, isCaps);
                return;
            }
        }
        insertKey(data, isCaps, false);
        reverseLastStandaloneChar(keyWillReverse, isCaps);
        return;
    } else if (_index == 2) {
        for (i = 0; i < (int)_doubleWAllowed.size(); i++) {
            if (CHR(0) == _doubleWAllowed[i][0] && CHR(1) == _doubleWAllowed[i][1]) {
                insertKey(data, isCaps, false);
                reverseLastStandaloneChar(keyWillReverse, isCaps);
                return;
            }
        }
        insertKey(data, isCaps);
        return;
    }
    
    insertKey(data, isCaps);
}

void upperCaseFirstCharacter() {
    if (!(TypingWord[0] & CAPS_MASK)) {
        hCode = vWillProcess;
        hBPC = 0;
        hNCC = 1;
        TypingWord[0] |= CAPS_MASK;
        hData[0] = GET(TypingWord[0]);
        _upperCaseStatus = 0;
        if (vUseMacro)
            hMacroKey[0] |= CAPS_MASK;
    }
}

void handleMainKey(const Uint16& data, const bool& isCaps) {
    //if is Z key, remove mark
    if (IS_KEY_Z(data)) {
        removeMark();
        if (!isChanged) {
            insertKey(data, isCaps);
        }
        return;
    }
    
    if (data == KEY_LEFT_BRACKET) { //standalone key [
        checkForStandaloneChar(data, isCaps, KEY_O);
        return;
    }
    
    if (data == KEY_RIGHT_BRACKET) { //standalone key }
        checkForStandaloneChar(data, isCaps, KEY_U);
        return;
    }
    
    //if is D key
    if (IS_KEY_D(data)) {
        isCorect = false;
        isChanged = false;
        k = _index;
        for (i = 0; i < (int)_consonantD.size(); i++) {
            if (_index < _consonantD[i].size())
                continue;
            isCorect = true;
            checkCorrectVowel(_consonantD, i, k, data);
            
            //allow d after consonant
            if (!isCorect && _index - 2 >= 0 && CHR(_index-1) == KEY_D && IS_CONSONANT(CHR(_index-2))) {
                isCorect = true;
            }
            if (isCorect) {
                isChanged = true;
                insertD(data, isCaps);
                break;
            }
        }
    
        if (!isChanged) {
            insertKey(data, isCaps);
        }
        return;
    }
    
    //if is mark key
    if (IS_MARK_KEY(data)) {
        for (auto& vowelEntry : _vowelForMark) {
            vector<vector<Uint16>>& charset = vowelEntry.second;
            isCorect = false;
            isChanged = false;
            k = _index;
            for (l = 0; l < (int)charset.size(); l++) {
                if (_index < charset[l].size())
                    continue;
                isCorect = true;
                checkCorrectVowel(charset, l, k, data);

                if (isCorect) {
                    isChanged = true;
                    if (IS_KEY_S(data))
                        insertMark(MARK1_MASK);
                    else if (IS_KEY_F(data))
                        insertMark(MARK2_MASK);
                    else if (IS_KEY_R(data))
                        insertMark(MARK3_MASK);
                    else if (IS_KEY_X(data))
                        insertMark(MARK4_MASK);
                    else if (IS_KEY_J(data))
                        insertMark(MARK5_MASK);
                    break;
                }
            }

            if (isCorect) {
                break;
            }
        }

        if (!isChanged) {
            insertKey(data, isCaps);
        }

        return;
    }
    
    //check Vowel
    if (vInputType == vVNI) {
        for (i = _index-1; i >= 0; i--) {
            if (CHR(i) == KEY_O || CHR(i) == KEY_A || CHR(i) == KEY_E) {
                VEI = i;
                break;
            }
        }
    }
    
    keyForAEO = ((vInputType != vVNI) ? data : ((data == KEY_7 || data == KEY_8 ? KEY_W : (data == KEY_6 ? TypingWord[VEI] : data))));
    vector<vector<Uint16>>& charset = _vowel[keyForAEO];
    isCorect = false;
    isChanged = false;
    k = _index;
    for (i = 0; i < (int)charset.size(); i++) {
        if (_index < charset[i].size())
            continue;
        isCorect = true;
        checkCorrectVowel(charset, i, k, data);
        
        if (isCorect) {
            isChanged = true;
            if (IS_KEY_DOUBLE(data)) {
                insertAOE(keyForAEO, isCaps);
            } else if (IS_KEY_W(data)) {
                if (vInputType == vVNI) {
                    for (j = _index-1; j >= 0; j--) {
                        if (CHR(j) == KEY_O || CHR(j) == KEY_U ||CHR(j) == KEY_A || CHR(j) == KEY_E) {
                            VEI = j;
                            break;
                        }
                    }
                    if ((data == KEY_7 && CHR(VEI) == KEY_A && (VEI-1>=0 ? CHR(VEI-1) != KEY_U : true)) || (data == KEY_8 && (CHR(VEI) == KEY_O || CHR(VEI) == KEY_U)))
                        break;
                }
                insertW(keyForAEO, isCaps);
            }
            break;
        }
    }
    
    if (!isChanged) {
        // For Telex: standalone W → ư only when vTelexWAsU is enabled.
        bool wStandaloneAllowed = (vInputType == vTelex && vTelexWAsU);
        if (data == KEY_W && wStandaloneAllowed) {
            checkForStandaloneChar(data, isCaps, KEY_U);
        } else {
            insertKey(data, isCaps);
        }
    }
}

void handleQuickTelex(const Uint16& data, const bool& isCaps) {
    hCode = vWillProcess;
    hBPC = 1;
    hNCC = 2;
    hData[1] = _quickTelex[data][0] | (isCaps ? CAPS_MASK : 0);
    hData[0] = _quickTelex[data][1] | (isCaps ? CAPS_MASK : 0);
    insertKey(_quickTelex[data][1], isCaps, false);
}

static bool restoreRawTyping(const int& handleCode, bool excludeLast = true) {
    hCode = handleCode;
    hBPC = _index;
    hNCC = excludeLast ? (_stateIndex - 1) : _stateIndex;
    for (i = 0; i < _stateIndex; i++) {
        TypingWord[i] = KeyStates[i];
    }
    for (i = 0; i < hNCC; i++) {
        hData[hNCC - 1 - i] = KeyStates[i];
    }
    _index = _stateIndex;
    return true;
}



static const std::unordered_set<std::string> englishContextMarkers = {
    "the", "a", "an", "of", "in", "to", "for", "with", "on", "at", "by", "this", "that", "is", "are", "was", "were", "it", "they", "we", "he", "she", "you", "and", "or", "but", "as", "from"
};

std::string getPreviousWord() {
    if (_typingStates.empty()) return "";
    for (auto it = _typingStates.rbegin(); it != _typingStates.rend(); ++it) {
        std::string word;
        for (Uint32 val : *it) {
            Uint32 charCode = getCharacterCode(val);
            if (charCode >= 32 && charCode < 127) {
                char c = static_cast<char>(charCode);
                if (std::isalnum(static_cast<unsigned char>(c))) {
                    word.push_back(c);
                } else {
                    if (!word.empty()) break;
                }
            }
        }
        if (!word.empty()) {
            return word;
        }
    }
    return "";
}

bool isPreviousWordEnglishMarker() {
    std::string prev = getPreviousWord();
    for (char &c : prev) c = std::tolower(static_cast<unsigned char>(c));
    return englishContextMarkers.count(prev) > 0;
}

bool predictIsEnglishOrProgramming(const std::string& word) {
    if (!vUsePerceptronContext) return false;

    // x1: Active app environment (1.0 if coding/terminal, -1.0 if chat/text editor)
    double x1 = -1.0;
    std::string app = vCurrentAppBundleId;
    for (char &c : app) c = std::tolower(static_cast<unsigned char>(c));
    if (app.find("vscode") != std::string::npos || 
        app.find("xcode") != std::string::npos || 
        app.find("intellij") != std::string::npos ||
        app.find("terminal") != std::string::npos ||
        app.find("iterm") != std::string::npos ||
        app.find("sublime") != std::string::npos ||
        app.find("studio") != std::string::npos) {
        x1 = 1.0;
    }

    // x2: Has programming characters
    double x2 = -1.0;
    for (char c : word) {
        if (c == '_' || c == '$') {
            x2 = 1.0;
            break;
        }
    }

    // x3: CamelCase / PascalCase clue
    double x3 = -1.0;
    if (word.length() >= 2) {
        for (size_t i = 0; i < word.length() - 1; ++i) {
            if (std::islower(static_cast<unsigned char>(word[i])) && std::isupper(static_cast<unsigned char>(word[i+1]))) {
                x3 = 1.0;
                break;
            }
        }
    }

    // x4: Word length > 5
    double x4 = (word.length() > 5) ? 1.0 : -1.0;

    // x5: Pre-context English marker
    double x5 = isPreviousWordEnglishMarker() ? 1.0 : -1.0;

    // weights and bias:
    double score = 1.5 * x1 + 2.0 * x2 + 1.5 * x3 + 0.5 * x4 + 1.2 * x5 - 0.2;
    return score > 0.0;
}

bool applyFsmRestorations(const int& handleCode) {
    if (_rawTyping.size() < 2) {
        _isAllCapsLockActive = false;
    } else if (vAllCapsAutoEscape && vCheckProgrammingKeywords) {
        bool firstUpper = (_rawTyping[0] & CAPS_MASK) != 0;
        bool secondUpper = (_rawTyping[1] & CAPS_MASK) != 0;
        
        if (firstUpper && secondUpper) {
            // Check if the second key is a Telex/VNI mark key
            Uint16 secondKey = _rawTyping[1] & CHAR_MASK;
            bool isMarkKey = false;
            if (vInputType == vTelex) {
                isMarkKey = (secondKey == KEY_S || secondKey == KEY_F || secondKey == KEY_R || secondKey == KEY_X || secondKey == KEY_J);
            } else if (vInputType == vVNI) {
                isMarkKey = (secondKey == KEY_1 || secondKey == KEY_2 || secondKey == KEY_3 || secondKey == KEY_4 || secondKey == KEY_5);
            }
            
            if (isMarkKey) {
                _isAllCapsLockActive = true;
            }
        }
    }
    
    if (_isAllCapsLockActive) {
        return restoreRawTyping(handleCode, false);
    }

    // 1. Check if the word has any Telex transformations (tone marks or accents)
    bool hasTransform = false;
    for (ii = 0; ii < _index; ii++) {
        if (!IS_CONSONANT(CHR(ii)) &&
            (TypingWord[ii] & MARK_MASK || TypingWord[ii] & TONE_MASK || TypingWord[ii] & TONEW_MASK)) {
            hasTransform = true;
            break;
        }
    }
    // Also consider it transformed if the number of raw keystrokes differs from output length
    if (_rawTyping.size() != (size_t)_index) {
        hasTransform = true;
    }
    if (!hasTransform) {
        return false;
    }

    // 2. Construct the raw English word string
    std::string rawWord;
    rawWord.reserve(_rawTyping.size());
    for (size_t i = 0; i < _rawTyping.size(); i++) {
        Uint16 character = keyCodeToCharacter(_rawTyping[i]);
        if (character == 0) {
            return false;
        }
        rawWord.push_back(static_cast<char>(character));
    }

    // 2.5. Check if it is a protected English word first
    if (vUseEnglishDictionary && isProtectedEnglishWord(rawWord)) {
        return restoreRawTyping(handleCode, false);
    }

    // 2.6. Check if it is a prefix of a protected English word to defer Vietnamese marks
    if (vUseEnglishDictionary && hasProtectedEnglishPrefix(rawWord)) {
        return restoreRawTyping(handleCode, false);
    }

    // 3. Apply FSM checks in user-configured priority order
    // FSM IDs: 0 = Vietnamese, 1 = English, 2 = Programming
    int localPriorityOrder[3];
    if (vUsePerceptronContext && predictIsEnglishOrProgramming(rawWord)) {
        // Boost English/Programming to the front
        localPriorityOrder[0] = 2; // PROG
        localPriorityOrder[1] = 1; // EN
        localPriorityOrder[2] = 0; // VI
    } else {
        localPriorityOrder[0] = vFsmPriorityOrder[0];
        localPriorityOrder[1] = vFsmPriorityOrder[1];
        localPriorityOrder[2] = vFsmPriorityOrder[2];
    }

    for (int _pri = 0; _pri < 3; ++_pri) {
        const int fsmId = localPriorityOrder[_pri];
        if (fsmId == 0) {
            // Vietnamese FSM
            if (!tempDisableKey) {
                // Valid Vietnamese spelling -> VN FSM wins! Keep Vietnamese transformation.
                return false;
            }
            // If it is INVALID Vietnamese, we just continue checking lower priority FSMs.
        } else if (fsmId == 1) {
            // English FSM
            if (vUseEnglishDictionary) {
                if (vnkey::isValidEnglishWord(rawWord)) {
                    // Valid English word -> EN FSM wins! Restore raw typing.
                    return restoreRawTyping(handleCode, false);
                }
            }
        } else if (fsmId == 2) {
            // Programming FSM
            if (vCheckProgrammingKeywords) {
                if (vnkey::isValidProgrammingKeyword(rawWord)) {
                    bool allUpper = true;
                    for (char c : rawWord) {
                        if (std::isalpha(static_cast<unsigned char>(c)) && !std::isupper(static_cast<unsigned char>(c))) {
                            allUpper = false;
                            break;
                        }
                    }
                    if (allUpper && !tempDisableKey && !vnkey::isBuiltInProgrammingKeyword(rawWord)) {
                        continue;
                    }
                    // Valid Programming keyword -> PROG FSM wins! Restore raw typing.
                    return restoreRawTyping(handleCode, false);
                }
            }
        }
    }

    // 4. Fallback
    // If we reach here, it means:
    // - English and Programming didn't match (or were disabled).
    // - Vietnamese was evaluated but it was INVALID (tempDisableKey = true).
    // We no longer automatically restore when none of the enabled FSMs match.
    return false;
}

void vSetCheckSpelling() {
    _useSpellCheckingBefore = vCheckSpelling;
}

void vTempOffEngine(const bool& off) {
    _willTempOffEngine = off;
}

bool checkQuickConsonant() {
    if (_index <= 1) return false;
    l = 0;
    if (_index > 0) {
        if (vQuickStartConsonant && _quickStartConsonant.find(CHR(0)) != _quickStartConsonant.end()) {
            hCode = vRestore;
            hBPC = _index;
            hNCC = _index + 1;
            if (_index < MAX_BUFF-1)
                _index++;
            //right shift
            for (i = _index-1; i >= 2; i--) {
                TypingWord[i] = TypingWord[i-1];
            }
            TypingWord[1] = _quickStartConsonant[CHR(0)][1] | ((TypingWord[0] & CAPS_MASK) && (TypingWord[2] & CAPS_MASK) ? CAPS_MASK : 0);
            TypingWord[0] = _quickStartConsonant[CHR(0)][0] | (TypingWord[0] & CAPS_MASK ? CAPS_MASK : 0);
            l = 1;;
        }
        if (vQuickEndConsonant &&
            (_index-2 >= 0 && !IS_CONSONANT(CHR(_index-2))) &&
            _quickEndConsonant.find(CHR(_index-1)) != _quickEndConsonant.end()) {
            hCode = vRestore;
            if (l == 1) {
                hNCC++;
            } else {
                hBPC = 1;
                hNCC = 2;
            }
            if (_index < MAX_BUFF-1)
                _index++;
            TypingWord[_index-1] = _quickEndConsonant[CHR(_index-2)][1] | (TypingWord[_index-2] & CAPS_MASK ? CAPS_MASK : 0);
            TypingWord[_index-2] = _quickEndConsonant[CHR(_index-2)][0] | (TypingWord[_index-2] & CAPS_MASK ? CAPS_MASK : 0);
            
            l = 1;
        }
        if (l == 1) {
            _hasHandleQuickConsonant = true;
            for (i = _index - 1; i >= 0; i--) {
                hData[_index - 1 - i] = GET(TypingWord[i]);
            }
            return true;
        }
    }
    return false;
}
/*==========================================================================================================*/

void vEnglishMode(const vKeyEventState& state, const Uint16& data, const bool& isCaps, const bool& otherControlKey) {
    hCode = vDoNothing;
    const bool wordBreak = isWordBreak(vKeyEvent::Keyboard, state, data);
    if (state == vKeyEventState::MouseDown || (otherControlKey && !isCaps)) {
        hMacroKey.clear();
        _willTempOffEngine = false;
    } else if (data == KEY_SPACE) {
        if (!_hasHandledMacro && findMacro(hMacroKey, hMacroData)) {
            hCode = vReplaceMaro;
            hBPC = (Byte)hMacroKey.size();
        }
        hMacroKey.clear();
        _willTempOffEngine = false;
    } else if (data == KEY_DELETE) {
        if (hMacroKey.size() > 0) {
            hMacroKey.pop_back();
        } else {
            _willTempOffEngine = false;
        }
    } else {
        if (wordBreak && !isCharKeyCode(data)) {
            hMacroKey.clear();
            _willTempOffEngine = false;
        } else {
            if (!_willTempOffEngine)
                hMacroKey.push_back(data | (isCaps ? CAPS_MASK : 0));
        }
    }
}

void vKeyHandleEvent(const vKeyEvent& event,
                     const vKeyEventState& state,
                     const Uint16& data,
                     const Uint8& capsStatus,
                     const bool& otherControlKey) {
    _isCaps = (capsStatus == 1 || //shift
               capsStatus == 2); //caps lock
    const bool wordBreak = isWordBreak(event, state, data) || 
                           (event == vKeyEvent::Keyboard && capsStatus == 1 && (data == KEY_9 || data == KEY_0));
    
    if (wordBreak) {
        if (data == KEY_MINUS && capsStatus == 1) {
            _liveProgrammingContext = true;
        } else if (data == KEY_SPACE || data == KEY_ENTER || data == KEY_RETURN || data == KEY_TAB || data == KEY_ESC) {
            _liveProgrammingContext = false;
        }
    }
    if ((IS_NUMBER_KEY(data) && capsStatus == 1)
        || otherControlKey || wordBreak || (_index == 0 && IS_NUMBER_KEY(data))) {
        hCode = vDoNothing;
        hBPC = 0;
        hNCC = 0;
        hExt = 1; //word break
        
        //check macro feature
        if (vUseMacro && isMacroBreakCode(data) && !_hasHandledMacro && hMacroKey.size() == _rawTyping.size() && findMacro(hMacroKey, hMacroData)) {
            hCode = vReplaceMaro;
            hBPC = (Byte)hMacroKey.size();
            _hasHandledMacro = true;
        } else if ((vQuickStartConsonant || vQuickEndConsonant) && !tempDisableKey && isMacroBreakCode(data)) {
            checkQuickConsonant();
        } else if (wordBreak) { // FSM restoration check with break-key
            if (vCheckSpelling) {
                checkSpelling(true); //force check spelling
            }
            
            bool restored = false;
            // Smart Punctuation English word check:
            if (vCheckProgrammingKeywords && vSmartPunctCheck) {
                // If the break character is one of: dot, quote, parentheses/brackets
                bool isSmartPunct = (data == KEY_DOT || data == KEY_QUOTE || 
                                     data == KEY_LEFT_BRACKET || data == KEY_RIGHT_BRACKET ||
                                     ((data == KEY_9 || data == KEY_0) && capsStatus == 1));
                if (isSmartPunct) {
                    std::string rawWord;
                    rawWord.reserve(_rawTyping.size());
                    for (size_t i = 0; i < _rawTyping.size(); i++) {
                        Uint16 character = keyCodeToCharacter(_rawTyping[i]);
                        if (character != 0) {
                            rawWord.push_back(static_cast<char>(character));
                        }
                    }
                    if (vUseEnglishDictionary && vnkey::isValidEnglishWord(rawWord)) {
                        // Check if there was any Telex/VNI transformation
                        bool hasTransform = false;
                        for (int ii = 0; ii < _index; ii++) {
                            if (!IS_CONSONANT(CHR(ii)) &&
                                (TypingWord[ii] & MARK_MASK || TypingWord[ii] & TONE_MASK || TypingWord[ii] & TONEW_MASK)) {
                                hasTransform = true;
                                break;
                            }
                        }
                        if (_rawTyping.size() != (size_t)_index) {
                            hasTransform = true;
                        }
                        if (hasTransform) {
                            restoreRawTyping(vRestoreAndStartNewSession, false);
                            restored = true;
                        }
                    }
                }
            }
            
            if (!restored) {
                if (applyFsmRestorations(vRestoreAndStartNewSession)) {
                    // Restored successfully!
                } else if (tempDisableKey) {
                    hCode = vDoNothing;
                }
            }
            if (vLateAccentTransformation == 1 && !tempDisableKey && hCode == vDoNothing && !_hasHandledMacro) {
                if (_index > 0) {
                    hCode = vWillProcess;
                    hBPC = (Byte)_rawTyping.size();
                    Uint32 triggerChar = keyCodeToCharacter(data);
                    hNCC = 0;
                    if (triggerChar != 0) {
                        hData[hNCC++] = triggerChar | PURE_CHARACTER_MASK;
                    }
                    for (i = 0; i < _index; i++) {
                        hData[hNCC++] = GET(TypingWord[_index - 1 - i]);
                    }
                }
            }
        }
        
        _isCharKeyCode = state == KeyDown && isCharKeyCode(data);
        if (!_isCharKeyCode) { //clear all line cache
            _specialChar.clear();
            _typingStates.clear();
            _typingStatesKeyStates.clear();
            _typingStatesRawTyping.clear();
        } else { //check and save current word
            if (_spaceCount > 0) {
                saveWord(KEY_SPACE, _spaceCount);
                _spaceCount = 0;
            } else {
                saveWord();
            }
            _specialChar.push_back(data | (_isCaps ? CAPS_MASK : 0));
            hExt = 3;//normal word
        }
        
        if (hCode == vDoNothing) {
            startNewSession();
            vCheckSpelling = _useSpellCheckingBefore;
            _willTempOffEngine = false;
        } else if (hCode == vReplaceMaro || _hasHandleQuickConsonant) {
            _index = 0;
        }
        
        //insert key for macro function
        if (vUseMacro) {
            if (_isCharKeyCode) {
                hMacroKey.push_back(data | (_isCaps ? CAPS_MASK : 0));
            } else {
                hMacroKey.clear();
            }
        }
        
        if (vUpperCaseFirstChar) {
            if (data == KEY_DOT)
                _upperCaseStatus = 1;
            else if (data == KEY_ENTER || data == KEY_RETURN)
                _upperCaseStatus = 2;
            else
                _upperCaseStatus = 0;
        }
    } else if (data == KEY_SPACE) {
        hCode = vDoNothing;
        hBPC = 0;
        hNCC = 0;
        hExt = 1; //word break
        if (vCheckSpelling) {
            checkSpelling(true); //force check spelling (always, so stale tempDisableKey from mid-word is refreshed)
        }
        if (vUseMacro && !_hasHandledMacro && hMacroKey.size() == _rawTyping.size() && findMacro(hMacroKey, hMacroData)) { //macro
            hCode = vReplaceMaro;
            hBPC = (Byte)hMacroKey.size();
            _spaceCount++;
            _hasHandledMacro = true;
        } else if ((vQuickStartConsonant || vQuickEndConsonant) && !tempDisableKey && checkQuickConsonant()) {
            _spaceCount++;
        } else if (!_hasHandledMacro) { // FSM restoration check
            if (applyFsmRestorations(vRestoreAndStartNewSession)) {
                // Restored successfully!
            } else if (tempDisableKey) {
                hCode = vDoNothing;
            }
            if (vLateAccentTransformation == 1 && !tempDisableKey && hCode == vDoNothing) {
                if (_index > 0) {
                    hCode = vWillProcess;
                    hBPC = (Byte)_rawTyping.size();
                    Uint32 triggerChar = keyCodeToCharacter(data);
                    hNCC = 0;
                    if (triggerChar != 0) {
                        hData[hNCC++] = triggerChar | PURE_CHARACTER_MASK;
                    }
                    for (i = 0; i < _index; i++) {
                        hData[hNCC++] = GET(TypingWord[_index - 1 - i]);
                    }
                }
            }
            _spaceCount++;
        } else { //do nothing with SPACE KEY
            hCode = vDoNothing;
            _spaceCount++;
        }
        if (vUseMacro) {
            hMacroKey.clear();
        }
        if (vUpperCaseFirstChar && _upperCaseStatus == 1) {
            _upperCaseStatus = 2;
        }
        //save word
        if (_spaceCount == 1) {
            if (_specialChar.size() > 0) {
                saveSpecialChar();
            } else {
                saveWord();
            }
        }
        vCheckSpelling = _useSpellCheckingBefore;
        _willTempOffEngine = false;
    } else if (data == KEY_DELETE) {

        hCode = vDoNothing;
        hExt = 2; //delete
        if (_specialChar.size() > 0) {
            _specialChar.pop_back();
            if (_specialChar.size() == 0) {
                restoreLastTypingState();
            }
        } else if (_spaceCount > 0) { //previous char is space
            _spaceCount--;
            if (_spaceCount == 0) { //restore word
                restoreLastTypingState();
            }
        } else {
            if (!_rawTyping.empty()) {
                _rawTyping.pop_back();
            }
            if (_rawTyping.size() < 2) {
                _isAllCapsLockActive = false;
            }
            if (_stateIndex > 0) {
                _stateIndex--;
            }
            if (_index > 0){
                _index--;
                if (_longWordHelper.size() > 0) {
                    //right shift
                    for (i = MAX_BUFF - 1; i > 0; i--) {
                        TypingWord[i] = TypingWord[i-1];
                    }
                    TypingWord[0] = _longWordHelper.back();
                    _longWordHelper.pop_back();
                    _index++;
                }
                if (vCheckSpelling)
                    checkSpelling();
            }
            if (vUseMacro && hMacroKey.size() > 0) {
                hMacroKey.pop_back();
            }
            
            hBPC = 0;
            hNCC = 0;
            hExt = 2; //delete key
            if (_index == 0) {
                startNewSession();
                _specialChar.clear();
                restoreLastTypingState();
            } else { //August 23rd continue check grammar
                checkGrammar(1);
            }
        }
    } else { //START AND CHECK KEY
        if (_willTempOffEngine) {
            hCode = vDoNothing;
            hExt = 3;
            return;
        }
        if (_spaceCount > 0) {
            hBPC = 0;
            hNCC = 0;
            hExt = 0;
            startNewSession();
            //continute save space
            saveWord(KEY_SPACE, _spaceCount);
            _spaceCount = 0;
        } else if (_specialChar.size() > 0) {
            saveSpecialChar();
        }

        _rawTyping.push_back(data | (_isCaps ? CAPS_MASK : 0));
        
        if (_rawTyping.size() < 2) {
            _isAllCapsLockActive = false;
        } else if (!_isAllCapsLockActive && vAllCapsAutoEscape && vCheckProgrammingKeywords) {
            bool firstUpper = (_rawTyping[0] & CAPS_MASK) != 0;
            bool secondUpper = (_rawTyping[1] & CAPS_MASK) != 0;
            
            if (firstUpper && secondUpper) {
                Uint16 secondKey = _rawTyping[1] & CHAR_MASK;
                bool isMarkKey = false;
                if (vInputType == vTelex) {
                    isMarkKey = (secondKey == KEY_S || secondKey == KEY_F || secondKey == KEY_R || secondKey == KEY_X || secondKey == KEY_J);
                } else if (vInputType == vVNI) {
                    isMarkKey = (secondKey == KEY_1 || secondKey == KEY_2 || secondKey == KEY_3 || secondKey == KEY_4 || secondKey == KEY_5);
                }
                
                if (isMarkKey) {
                    _isAllCapsLockActive = true;
                }
            }
        }
        
        if (_isAllCapsLockActive) {
            tempDisableKey = true;
        }

        insertState(data, _isCaps); //save state
        
        bool autoDisableVietnamese = false;
        if (_liveProgrammingContext) {
            autoDisableVietnamese = true;
        } else {
            std::string rawWord;
            rawWord.reserve(_rawTyping.size());
            for (size_t k = 0; k < _rawTyping.size(); k++) {
                Uint16 character = keyCodeToCharacter(_rawTyping[k]);
                if (character != 0) {
                    rawWord.push_back(static_cast<char>(character));
                }
            }
            
            bool hasLower = false;
            for (size_t k = 0; k < rawWord.size(); ++k) {
                char c = rawWord[k];
                if (c >= 'a' && c <= 'z') {
                    hasLower = true;
                } else if (hasLower && c >= 'A' && c <= 'Z') {
                    autoDisableVietnamese = true;
                    break;
                }
            }
        }
        
        if (!IS_SPECIALKEY(data) || tempDisableKey || autoDisableVietnamese) { //do nothing
            if (vQuickTelex && IS_QUICK_TELEX_KEY(data)) {
                handleQuickTelex(data, _isCaps);
                return;
            } else {
                hCode = vDoNothing;
                hBPC = 0;
                hNCC = 0;
                hExt = 3; //normal key
                insertKey(data, _isCaps);
            }
        } else { //check and update key
            //restore state
            hCode = vDoNothing;
            hExt = 3; //normal key
            handleMainKey(data, _isCaps);
        }

        if (!IS_KEY_D(data)) {
            if (hCode == vDoNothing) {
                checkGrammar(-1);
            } else {
                checkGrammar(0);
            }
        }
        
        if (hCode == vRestore) {
            insertKey(data, _isCaps);
        }
        
        //insert or replace key for macro feature
        if (vUseMacro) {
            if (hCode == vDoNothing) {
                hMacroKey.push_back(data | (_isCaps ? CAPS_MASK : 0));
            } else if (hCode == vWillProcess || hCode == vRestore) {
                for (i = 0; i < hBPC; i++) {
                    if (hMacroKey.size() > 0) {
                        hMacroKey.pop_back();
                    }
                }
                for (i = _index - hBPC; i < hNCC + (_index - hBPC); i++) {
                    hMacroKey.push_back(TypingWord[i]);
                }
            }
        }
        
        if (vUpperCaseFirstChar) {
            if (_index == 1 && _upperCaseStatus == 2) {
                upperCaseFirstCharacter();
            }
            _upperCaseStatus = 0;
        }
        
        //case [ ]
        // Bracket keys break the word
        bool bracketBreaksWord = IS_BRACKET_KEY((Uint16)hData[0])
                                 || (vInputType == vTelex && !vTelexBracketAsO);
        if (IS_BRACKET_KEY(data) && bracketBreaksWord) {
            if (_index - (hCode == vWillProcess ? hBPC : 0) > 0) {
                _index--;
                saveWord();
            }
            _index = 0;
            tempDisableKey = false;
            _stateIndex = 0;
            hExt = 3;
            _specialChar.push_back(data | (_isCaps ? CAPS_MASK : 0));
        }
        if (vLateAccentTransformation == 1) {
            hCode = vDoNothing;
            hBPC = 0;
            hNCC = 0;
        }
    }
    
    //Debug
    //cout<<"index "<<(int)_index<< ", stateIndex "<<(int)_stateIndex<<", word "<<_typingStates.size()<<", long word "<<_longWordHelper.size()<< endl;
    //cout<<"backspace "<<(int)hBPC<<endl;
    //cout<<"new char "<<(int)hNCC<<endl<<endl;
}
