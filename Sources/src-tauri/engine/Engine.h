//
//  Engine.h
//  VNKey
//
//  Created by Tuyen on 1/18/19.
//  Copyright © 2019 Tuyen Mai. All rights reserved.
//

#ifndef Engine_h
#define Engine_h

#include "DataType.h"
#include "Vietnamese.h"
#include "Macro.h"
#include "SmartSwitchKey.h"
#include "ConvertTool.h"
#include "EnglishDictionary.h"

#ifndef LOBYTE
#define LOBYTE(data) (data & 0xFF)
#endif // !LOBYTE
#ifndef HIBYTE
#define HIBYTE(data) ((data>>8) & 0xFF)
#endif // !HIBYTE

#define GET_SWITCH_KEY(data) (data & 0xFF)
#define HAS_CONTROL(data) ((data & 0x100) ? 1 : 0)
#define HAS_OPTION(data) ((data & 0x200) ? 1 : 0)
#define HAS_COMMAND(data) ((data & 0x400) ? 1 : 0)
#define HAS_SHIFT(data) ((data & 0x800) ? 1 : 0)
#define GET_BOOL(data) (data ? 1 : 0)
#define HAS_BEEP(data) (data & 0x8000)
#define SET_SWITCH_KEY(data, key) data = (data & 0xFF) | key
#define SET_CONTROL_KEY(data, val) data|=val<<8;
#define SET_OPTION_KEY(data, val) data|=val<<9;
#define SET_COMMAND_KEY(data, val) data|=val<<10;

#ifdef __cplusplus
extern "C" {
#endif

//define these variable in your application
//API
/*
 * 0: English
 * 1: Vietnamese
 */
extern int vLanguage;

/*
 * 0: Telex
 * 1: VNI
 */
extern int vInputType;

/**
 * 0: No
 * 1: Yes
 */
extern int vFreeMark;

/*
 * 0: Unicode
 * 1: TCVN3 (ABC)
 * 2: VNI-Windows
 */
extern int vCodeTable;

/*
 * first 8 bit: keycode
 * bit 8: Control on/off
 * bit 9: Option on/off
 * bit 10: Command on/off
 */
extern int vSwitchKeyStatus;

/**
 * 0: No
 * 1: Yes
 */
extern int vCheckSpelling;

/*
 * 0: òa, úy
 * 1: oà uý
*/
extern int vUseModernOrthography;

/**
 * 0: No
 * 1: Yes
 * (cc=ch, gg=gi, kk=kh, nn=ng, qq=qu, pp=ph, tt=th, uu=ươ)
 */
extern int vQuickTelex;

/**
 * Restore protected English words that Telex changed.
 * Works together with FSM Priority Order.
 * 0: No
 * 1: Yes
 */
extern int vUseEnglishDictionary;

/*
 * Fix recommend browser's address, excel,...
 * 0: No
 * 1: Yes
 */
extern int vFixRecommendBrowser;

/*
 * Fix Spotlight first word double-vowel bug
 * 0: No
 * 1: Yes
 */
extern int vFixSpotlight;

/**
 * Macro on or off
 */
extern int vUseMacro;

/**
 * Still use macro if you are in english mode
 */
extern int vUseMacroInEnglishMode;

/**
 * Ex: define: btw -> by the way
 * Type: `Btw` -> `By the way`
 * Type: `BTW` -> `BY THE WAY`
 */
extern int vAutoCapsMacro;

/**
 * auto switch language when switch app
 * 0: No
 * 1: Yes
 */
extern int vUseSmartSwitchKey;

/**
 * Auto write upper case character for first letter.
 * 0: No
 * 1: Yes
 */
extern int vUpperCaseFirstChar;



/**
 * 0: No; 1: Yes
 * f -> ph: fanh -> phanh,...
 * j ->gi: jang -> giang,...
 * w ->qu: wen -> quen,...
 */
extern int vQuickStartConsonant;

/**
 * 0: No; 1: Yes
 * g -> ng: hag -> hang,...
 * h -> nh: vih -> vinh,...
 * k -> ch: bak -> bach,...
 */
extern int vQuickEndConsonant;

/**
 * 0: No; 1: Yes
 * Auto remember table code for each application
 */
extern int vRememberCode;

/**
 * 0: No; 1: Yes
 * Turn off Vietnamese when typing in another language.
 */
extern int vOtherLanguage;

/**
 * 0: No; 1: Yes
 * Temporarily turn off VNKey  by hot key (Command on mac, Alt on Windows and Linux)
 */
extern int vTempOffVNKey;

extern int vCheckProgrammingKeywords;

/**
 * FSM priority order: array of 3 values, each 0=VI, 1=EN, 2=PROG.
 * Controls the order in which FSMs are consulted in checkRestoreIfWrongSpelling.
 * Default: {0, 1, 2} (Vietnamese first, then English, then Programming).
 */
extern int vFsmPriorityOrder[3];

/**
 * Telex sub-options (effective only when vInputType == vTelex = 0):
 *   1 = enable (classic Telex behaviour)
 *   0 = disable
 *
 * vTelexWAsU: when no vowel match, standalone W at word-start → ư
 * vTelexBracketAsO: [ key → ơ / ] key → ư as special Telex modifiers
 */
extern int vTelexWAsU;
extern int vTelexBracketAsO;

/**
 * Call this function first to receive data pointer
 */
void* vKeyInit();

/**
 * Convert engine character to real character
 */
Uint32 getCharacterCode(const Uint32& data);

/**
 * MAIN entry point for each key
 * event: mouse or keyboard event
 * state: additional state for event
 * data: key code
 * isCaps: caplock is on or shift key is pressing
 * otherControlKey: ctrl, option,... is pressing
 */
void vKeyHandleEvent(const vKeyEvent& event,
                     const vKeyEventState& state,
                     const Uint16& data,
                     const Uint8& capsStatus=0,
                     const bool& otherControlKey=false);

/**
 * Start a new word
 */
void startNewSession();

/**
 * do some task in english mode (use for macro)
 */
void vEnglishMode(const vKeyEventState& state, const Uint16& data, const bool& isCaps, const bool& otherControlKey);


/**
 * reset spelling value
 */
void vSetCheckSpelling();

/**
 * temporarily turn off VNKey engine
 */
void vTempOffEngine(const bool& off=true);

// Set user-defined programming keywords list
void vnkey_set_custom_programming_keywords(const char* content);

#ifdef __cplusplus
}
#endif

/**
 * some utils function
 */
wstring utf8ToWideString(const string& str);
string wideStringToUtf8(const wstring& str);

#endif /* Engine_h */
