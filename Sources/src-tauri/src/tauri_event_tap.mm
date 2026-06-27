//
//  VNKey.m
//  VNKey
//
//  Created by Tuyen on 1/18/19.
//  Copyright © 2019 Tuyen Mai. All rights reserved.
//
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <Foundation/Foundation.h>
#import <QuickLook/QuickLook.h>
#import "Engine.h"
#include <unistd.h>
extern "C" {
    void rust_onInputMethodChanged(int val);
    void rust_onCodeTableChanged(int val);
    void rust_onQuickConvert();
    void rust_onToggleClipboardPicker();
    void rust_onToggleControlPanel();
    void set_is_internal_copy(bool val);
    void rust_onAccessibilityRevoked();
}

#define FRONT_APP _frontMostApp
#define VNKEY_BUNDLE @"com.vnkey.app"
#define OTHER_CONTROL_KEY (_flag & kCGEventFlagMaskCommand) || (_flag & kCGEventFlagMaskControl) || \
                            (_flag & kCGEventFlagMaskAlternate) || (_flag & kCGEventFlagMaskSecondaryFn) || \
                            (_flag & kCGEventFlagMaskNumericPad) || (_flag & kCGEventFlagMaskHelp)

#define DYNA_DATA(macro, pos) (macro ? pData->macroData[pos] : pData->charData[pos])
#define MAX_UNICODE_STRING  20
#define EMPTY_HOTKEY 0xFE0000FE
#define LOAD_DATA(VAR, KEY) VAR = (int)[[NSUserDefaults standardUserDefaults] integerForKey:@#KEY]

// Ignore code for Modifier keys and numpad
// Reference: https://eastmanreference.com/complete-list-of-applescript-key-codes
NSDictionary *keyStringToKeyCodeMap = @{
    // Characters from number row
    @"`": @50, @"~": @50, @"1": @18, @"!": @18, @"2": @19, @"@": @19, @"3": @20, @"#": @20, @"4": @21, @"$": @21,
    @"5": @23, @"%": @23, @"6": @22, @"^": @22, @"7": @26, @"&": @26, @"8": @28, @"*": @28, @"9": @25, @"(": @25,
    @"0": @29, @")": @29, @"-": @27, @"_": @27, @"=": @24, @"+": @24,
    // Characters from first keyboard row
    @"q": @12, @"w": @13, @"e": @14, @"r": @15, @"t": @17, @"y": @16, @"u": @32, @"i": @34, @"o": @31, @"p": @35,
    @"[": @33, @"{": @33, @"]": @30, @"}": @30, @"\\": @42, @"|": @42,
    // Characters from second keyboard row
    @"a": @0, @"s": @1, @"d": @2, @"f": @3, @"g": @5, @"h": @4, @"j": @38, @"k": @40, @"l": @37,
    @";": @41, @":": @41, @"'": @39, @"\"": @39,
    // Characters from second third row
    @"z": @6, @"x": @7, @"c": @8, @"v": @9, @"b": @11, @"n": @45, @"m": @46,
    @",": @43, @"<": @43, @".": @47, @">": @47, @"/": @44, @"?": @44
};

int clipboardHotKey = 0x76000109; // Default: Ctrl + V
int panelHotKey = 0x50000C23;     // Default: Cmd + Shift + P
bool clipboardHistoryEnabled = true;

static CFMachPortRef      eventTap = NULL;
static CGEventMask        eventMask = 0;
static CFRunLoopSourceRef runLoopSource = NULL;
static bool               _isInited = false;
static id                 activeAppObserver = nil;
static double             _lastAppSwitchTime = 0.0;

extern "C" {
    extern int vSendKeyStepByStep;
    extern int vFixChromiumBrowser;
    extern int vPerformLayoutCompat;
    extern int vDisableHotkeys;
    extern int vFixSpotlight;
    extern int vUsePasteWorkaround;
    
    bool _usePasteInsteadOfEvent = false;

    CGEventSourceRef myEventSource = NULL;
    vKeyHookState* pData;
    CGEventRef eventBackSpaceDown;
    CGEventRef eventBackSpaceUp;
    CGEventRef unicodeEventDown;
    CGEventRef unicodeEventUp;
    UniChar _newChar, _newCharHi;
    CGEventRef _newEventDown, _newEventUp;
    CGKeyCode _keycode;
    CGEventFlags _flag, _lastFlag = 0, _privateFlag;
    CGEventTapProxy _proxy;
    
    Uint16 _newCharString[MAX_UNICODE_STRING];
    Uint16 _newCharSize;
    bool _willContinuteSending = false;
    bool _willSendControlKey = false;
    
    vector<Uint16> _syncKey;
    
    Uint16 _uniChar[2];
    int _i, _j, _k;
    Uint32 _tempChar;
    bool _hasJustUsedHotKey = false;

    int _languageTemp = 0; //use for smart switch key
    vector<Byte> savedSmartSwitchKeyData; ////use for smart switch key
    
    NSString* _frontMostApp = @"UnknownApp";
    BOOL _currentInputSourceIsEnglish = YES;
    CFAbsoluteTime _frontMostAppCheckedAt = 0;
    CFAbsoluteTime _spotlightCheckedAt = 0;
    BOOL _spotlightVisible = NO;
    
    void VNKeyFree() {
        if (eventBackSpaceDown) {
            CFRelease(eventBackSpaceDown);
            eventBackSpaceDown = NULL;
        }
        if (eventBackSpaceUp) {
            CFRelease(eventBackSpaceUp);
            eventBackSpaceUp = NULL;
        }
        if (myEventSource) {
            CFRelease(myEventSource);
            myEventSource = NULL;
        }
        if (unicodeEventDown) {
            CFRelease(unicodeEventDown);
            unicodeEventDown = NULL;
        }
        if (unicodeEventUp) {
            CFRelease(unicodeEventUp);
            unicodeEventUp = NULL;
        }
    }

    void VNKeyInit() {
        VNKeyFree();

        myEventSource = CGEventSourceCreate(kCGEventSourceStatePrivate);
        pData = (vKeyHookState*)vKeyInit();

        eventBackSpaceDown = CGEventCreateKeyboardEvent (myEventSource, 51, true);
        eventBackSpaceUp = CGEventCreateKeyboardEvent (myEventSource, 51, false);
        unicodeEventDown = CGEventCreateKeyboardEvent(myEventSource, 0, true);
        unicodeEventUp = CGEventCreateKeyboardEvent(myEventSource, 0, false);

        //init and load macro data
        NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
        NSData *data = [prefs objectForKey:@"macroData"];
        if (data) {
            initMacroMap((Byte*)data.bytes, (int)data.length);
        }
        
        //init and load smart switch key data
        data = [prefs objectForKey:@"smartSwitchKey"];
        if (data) {
            initSmartSwitchKey((Byte*)data.bytes, (int)data.length);
        }
        
        //init convert tool
        convertToolDontAlertWhenCompleted = ![prefs boolForKey:@"convertToolDontAlertWhenCompleted"];
        convertToolToAllCaps = [prefs boolForKey:@"convertToolToAllCaps"];
        convertToolToAllNonCaps = [prefs boolForKey:@"convertToolToAllNonCaps"];
        convertToolToCapsFirstLetter = [prefs boolForKey:@"convertToolToCapsFirstLetter"];
        convertToolToCapsEachWord = [prefs boolForKey:@"convertToolToCapsEachWord"];
        convertToolRemoveMark = [prefs boolForKey:@"convertToolRemoveMark"];
        convertToolFromCode = [prefs integerForKey:@"convertToolFromCode"];
        convertToolToCode = [prefs integerForKey:@"convertToolToCode"];
        convertToolHotKey = (int)[prefs integerForKey:@"convertToolHotKey"];
        if (convertToolHotKey == 0) {
            convertToolHotKey = EMPTY_HOTKEY;
        }
    }
    
    void RequestNewSession() {
        //send event signal to Engine
        vKeyHandleEvent(vKeyEvent::Mouse, vKeyEventState::MouseDown, 0);
        
        if (IS_DOUBLE_CODE(vCodeTable)) { //VNI
            _syncKey.clear();
        }
    }
    
    void queryFrontMostApp() {
        NSRunningApplication *application = [[NSWorkspace sharedWorkspace] frontmostApplication];
        NSString *bundleIdentifier = application.bundleIdentifier;
        if (bundleIdentifier != nil) {
            _frontMostApp = bundleIdentifier;
        } else if (application.localizedName != nil) {
            _frontMostApp = application.localizedName;
        } else {
            _frontMostApp = @"UnknownApp";
        }
        _frontMostAppCheckedAt = CFAbsoluteTimeGetCurrent();
    }

    void refreshFrontMostAppIfNeeded() {
        // App query is handled asynchronously by workspace notifications
    }

    void refreshCurrentInputSource() {
        _currentInputSourceIsEnglish = YES;
        TISInputSourceRef inputSource = TISCopyCurrentKeyboardInputSource();
        if (inputSource == NULL) {
            return;
        }
        CFArrayRef languages = (CFArrayRef)TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceLanguages);
        if (languages != NULL && CFArrayGetCount(languages) > 0) {
            CFStringRef language = (CFStringRef)CFArrayGetValueAtIndex(languages, 0);
            _currentInputSourceIsEnglish = [(__bridge NSString *)language hasPrefix:@"en"];
        }
        CFRelease(inputSource);
    }
    
    NSString* ConvertUtil(NSString* str) {
        return [NSString stringWithUTF8String:convertUtil([str UTF8String]).c_str()];
    }
    
    BOOL containUnicodeCompoundApp(NSString* topApp) {
        return topApp != nil &&
            ([topApp hasPrefix:@"com.apple."] ||
             [topApp isEqualToString:@"com.google.Chrome"] ||
             [topApp isEqualToString:@"com.google.Chrome.canary"] ||
             [topApp isEqualToString:@"com.brave.Browser"] ||
             [topApp isEqualToString:@"com.microsoft.edgemac.Dev"] ||
             [topApp isEqualToString:@"com.microsoft.edgemac.Beta"] ||
             [topApp isEqualToString:@"com.microsoft.Edge.Dev"] ||
             [topApp isEqualToString:@"com.microsoft.Edge"] ||
             [topApp isEqualToString:@"company.thebrowser.Browser"] ||
             [topApp isEqualToString:@"com.vivaldi.Vivaldi"] ||
             [topApp isEqualToString:@"com.operasoftware.Opera"] ||
             [topApp isEqualToString:@"org.chromium.Chromium"]);
    }

    BOOL isNiceSpaceApp(NSString* topApp) {
        return [topApp isEqualToString:@"com.sublimetext.3"] ||
               [topApp isEqualToString:@"com.sublimetext.2"];
    }

    BOOL isRecommendWorkaroundDisabledApp(NSString* topApp) {
        return [topApp isEqualToString:@"com.apple.Spotlight"];
    }

    #include <atomic>
    
    std::atomic<bool> g_spotlightVisible{false};
    std::atomic<bool> g_spotlightIsChecking{false};

    void forceCheckSpotlightVisible() {
        bool expected = false;
        if (g_spotlightIsChecking.compare_exchange_strong(expected, true)) {
            _spotlightCheckedAt = CFAbsoluteTimeGetCurrent();
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
                BOOL visible = NO;
                NSArray *windows = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
                                                                                kCGNullWindowID));
                for (NSDictionary *window in windows) {
                    if ([[window objectForKey:(__bridge NSString *)kCGWindowOwnerName] isEqualToString:@"Spotlight"]) {
                        visible = YES;
                        break;
                    }
                }
                g_spotlightVisible.store(visible);
                g_spotlightIsChecking.store(false);
            });
        }
    }

    void checkSpotlightVisibleSync() {
        BOOL visible = NO;
        NSArray *windows = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
                                                                        kCGNullWindowID));
        for (NSDictionary *window in windows) {
            if ([[window objectForKey:(__bridge NSString *)kCGWindowOwnerName] isEqualToString:@"Spotlight"]) {
                visible = YES;
                break;
            }
        }
        g_spotlightVisible.store(visible);
        _spotlightCheckedAt = CFAbsoluteTimeGetCurrent();
    }

    BOOL isSpotlightVisible() {
        if (!vFixSpotlight) return false;

        const CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (now - _spotlightCheckedAt < 0.2) {
            return g_spotlightVisible.load();
        }
        
        if (!g_spotlightVisible.load()) {
            checkSpotlightVisibleSync();
        } else {
            forceCheckSpotlightVisible();
        }
        
        return g_spotlightVisible.load();
    }

    BOOL shouldUseRecommendWorkaround(NSString* topApp) {
        if (!vFixRecommendBrowser) return false;
        if (isSpotlightVisible()) return false;
        if (topApp == nil) return true;
        return !isRecommendWorkaroundDisabledApp(topApp);
    }

    BOOL shouldUseSelectionReplacement(NSString* topApp) {
        return isSpotlightVisible() || isRecommendWorkaroundDisabledApp(topApp);
    }
    
    void saveSmartSwitchKeyData() {
        getSmartSwitchKeySaveData(savedSmartSwitchKeyData);
        NSData* _data = [NSData dataWithBytes:savedSmartSwitchKeyData.data() length:savedSmartSwitchKeyData.size()];
        NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
        [prefs setObject:_data forKey:@"smartSwitchKey"];
    }
    
    void OnActiveAppChanged() { //use for smart switch key; improved on Sep 28th, 2019
        queryFrontMostApp();
        
        // Always reset the engine session when the front app changes.
        // This prevents stale buffer state from leaking into the first keystroke
        // in the new app (e.g. double-vowel bug in Spotlight).
        RequestNewSession();
        
        _languageTemp = getAppInputMethodStatus(string(_frontMostApp.UTF8String), vLanguage | (vCodeTable << 1));
        if ((_languageTemp & 0x01) != vLanguage) { //for input method
            if (_languageTemp != -1) {
                vLanguage = _languageTemp & 0x01;
                rust_onInputMethodChanged(vLanguage);
                startNewSession();
            } else {
                saveSmartSwitchKeyData();
            }
        }
        if (vRememberCode && (_languageTemp >> 1) != vCodeTable) { //for remember table code feature
            if (_languageTemp != -1) {
                vCodeTable = _languageTemp >> 1;
                rust_onCodeTableChanged(vCodeTable);
            } else {
                saveSmartSwitchKeyData();
            }
        }
    }
    
    void OnTableCodeChange() {
        onTableCodeChange();
        if (vRememberCode) {
            queryFrontMostApp();
            setAppInputMethodStatus(string(_frontMostApp.UTF8String), vLanguage | (vCodeTable << 1));
            saveSmartSwitchKeyData();
        }
    }
    
    void OnInputMethodChanged() {
        if (vUseSmartSwitchKey) {
            queryFrontMostApp();
            setAppInputMethodStatus(string(_frontMostApp.UTF8String), vLanguage | (vCodeTable << 1));
            saveSmartSwitchKeyData();
        }
    }
    
    void OnSpellCheckingChanged() {
        vSetCheckSpelling();
    }
    
    void PasteText(NSString* text) {
        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        NSString *oldText = [pb stringForType:NSPasteboardTypeString];
        
        set_is_internal_copy(true);
        [pb declareTypes:@[NSPasteboardTypeString] owner:nil];
        [pb setString:text forType:NSPasteboardTypeString];
        
        CGEventRef cmdVDown = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)9, true);
        CGEventSetFlags(cmdVDown, kCGEventFlagMaskCommand);
        CGEventRef cmdVUp = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)9, false);
        
        CGEventTapPostEvent(_proxy, cmdVDown);
        CGEventTapPostEvent(_proxy, cmdVUp);
        
        CFRelease(cmdVDown);
        CFRelease(cmdVUp);
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(100 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
            set_is_internal_copy(true);
            NSPasteboard *pb_restore = [NSPasteboard generalPasteboard];
            [pb_restore declareTypes:@[NSPasteboardTypeString] owner:nil];
            if (oldText != nil) {
                [pb_restore setString:oldText forType:NSPasteboardTypeString];
            }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(50 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
                set_is_internal_copy(false);
            });
        });
    }
    
    void InsertKeyLength(const Uint8& len) {
        _syncKey.push_back(len);
    }

    bool PostUnicodeString(const UniChar *characters, UniCharCount length) {
        if (unicodeEventDown == NULL || unicodeEventUp == NULL ||
            characters == NULL || length == 0) {
            return false;
        }
        if (_usePasteInsteadOfEvent) {
            NSString *str = [NSString stringWithCharacters:characters length:length];
            PasteText(str);
            return true;
        }
        CGEventKeyboardSetUnicodeString(unicodeEventDown, length, characters);
        CGEventKeyboardSetUnicodeString(unicodeEventUp, length, characters);
        CGEventTapPostEvent(_proxy, unicodeEventDown);
        CGEventTapPostEvent(_proxy, unicodeEventUp);
        return true;
    }
    
    void SendPureCharacter(const Uint16& ch) {
        PostUnicodeString(&ch, 1);
        if (IS_DOUBLE_CODE(vCodeTable)) {
            InsertKeyLength(1);
        }
    }
    
    void SendKeyCode(Uint32 data) {
        _newChar = (Uint16)data;
        if (!(data & CHAR_CODE_MASK)) {
            if (IS_DOUBLE_CODE(vCodeTable)) //VNI
                InsertKeyLength(1);
            
            _newEventDown = CGEventCreateKeyboardEvent(myEventSource, _newChar, true);
            _newEventUp = CGEventCreateKeyboardEvent(myEventSource, _newChar, false);
            _privateFlag = CGEventGetFlags(_newEventDown);
            
            if (data & CAPS_MASK) {
                _privateFlag |= kCGEventFlagMaskShift;
            } else {
                _privateFlag &= ~kCGEventFlagMaskShift;
            }
            _privateFlag |= kCGEventFlagMaskNonCoalesced;
            
            CGEventSetFlags(_newEventDown, _privateFlag);
            CGEventSetFlags(_newEventUp, _privateFlag);
            CGEventTapPostEvent(_proxy, _newEventDown);
            CGEventTapPostEvent(_proxy, _newEventUp);
        } else {
            if (vCodeTable == 0) { //unicode 2 bytes code
                PostUnicodeString(&_newChar, 1);
            } else if (vCodeTable == 1 || vCodeTable == 2 || vCodeTable == 4) { //others such as VNI Windows, TCVN3: 1 byte code
                _newCharHi = HIBYTE(_newChar);
                _newChar = LOBYTE(_newChar);
                
                PostUnicodeString(&_newChar, 1);
                if (_newCharHi > 32) {
                    if (vCodeTable == 2) //VNI
                        InsertKeyLength(2);
                    PostUnicodeString(&_newCharHi, 1);
                } else {
                    if (vCodeTable == 2) //VNI
                        InsertKeyLength(1);
                }
            } else if (vCodeTable == 3) { //Unicode Compound
                _newCharHi = (_newChar >> 13);
                _newChar &= 0x1FFF;
                _uniChar[0] = _newChar;
                _uniChar[1] = _newCharHi > 0 ? (_unicodeCompoundMark[_newCharHi - 1]) : 0;
                InsertKeyLength(_newCharHi > 0 ? 2 : 1);
                PostUnicodeString(_uniChar, (_newCharHi > 0 ? 2 : 1));
            }
        }
        if (_newEventDown) {
            CFRelease(_newEventDown);
            _newEventDown = NULL;
        }
        if (_newEventUp) {
            CFRelease(_newEventUp);
            _newEventUp = NULL;
        }
    }
    
    void SendEmptyCharacter() {
        if (IS_DOUBLE_CODE(vCodeTable)) //VNI or Unicode Compound
            InsertKeyLength(1);
        
        _newChar = 0x202F; //empty char
        if (isNiceSpaceApp(FRONT_APP)) {
            _newChar = 0x200C; //Unicode character with empty space
        }
        
        PostUnicodeString(&_newChar, 1);
    }
    
    void SendVirtualKey(const Byte& vKey) {
        CGEventRef eventVkeyDown = CGEventCreateKeyboardEvent (myEventSource, vKey, true);
        CGEventRef eventVkeyUp = CGEventCreateKeyboardEvent (myEventSource, vKey, false);
        
        CGEventTapPostEvent(_proxy, eventVkeyDown);
        CGEventTapPostEvent(_proxy, eventVkeyUp);
        
        CFRelease(eventVkeyDown);
        CFRelease(eventVkeyUp);
    }

    void SendBackspace() {
        CGEventTapPostEvent(_proxy, eventBackSpaceDown);
        CGEventTapPostEvent(_proxy, eventBackSpaceUp);
        
        if (IS_DOUBLE_CODE(vCodeTable) && !_syncKey.empty()) { //VNI or Unicode Compound
            if (_syncKey.back() > 1) {
                if (!(vCodeTable == 3 && containUnicodeCompoundApp(FRONT_APP))) {
                    CGEventTapPostEvent(_proxy, eventBackSpaceDown);
                    CGEventTapPostEvent(_proxy, eventBackSpaceUp);
                }
            }
            _syncKey.pop_back();
        }
    }
    
    void SendShiftAndLeftArrow() {
        CGEventRef eventVkeyDown = CGEventCreateKeyboardEvent (myEventSource, KEY_LEFT, true);
        CGEventRef eventVkeyUp = CGEventCreateKeyboardEvent (myEventSource, KEY_LEFT, false);
        _privateFlag = CGEventGetFlags(eventVkeyDown);
        _privateFlag |= kCGEventFlagMaskShift;
        CGEventSetFlags(eventVkeyDown, _privateFlag);
        CGEventSetFlags(eventVkeyUp, _privateFlag);
        
        CGEventTapPostEvent(_proxy, eventVkeyDown);
        CGEventTapPostEvent(_proxy, eventVkeyUp);
        
        if (IS_DOUBLE_CODE(vCodeTable) && !_syncKey.empty()) { //VNI or Unicode Compound
            if (_syncKey.back() > 1) {
                if (!(vCodeTable == 3 && containUnicodeCompoundApp(FRONT_APP))) {
                    CGEventTapPostEvent(_proxy, eventVkeyDown);
                    CGEventTapPostEvent(_proxy, eventVkeyUp);
                }
            }
            _syncKey.pop_back();
        }
        CFRelease(eventVkeyDown);
        CFRelease(eventVkeyUp);
    }
    
    void SendCutKey() {
        CGEventRef eventVkeyDown = CGEventCreateKeyboardEvent (myEventSource, KEY_X, true);
        CGEventRef eventVkeyUp = CGEventCreateKeyboardEvent (myEventSource, KEY_X, false);
        _privateFlag = CGEventGetFlags(eventVkeyDown);
        _privateFlag |= NX_COMMANDMASK;
        CGEventSetFlags(eventVkeyDown, _privateFlag);
        CGEventSetFlags(eventVkeyUp, _privateFlag);
        
        CGEventTapPostEvent(_proxy, eventVkeyDown);
        CGEventTapPostEvent(_proxy, eventVkeyUp);
        
        CFRelease(eventVkeyDown);
        CFRelease(eventVkeyUp);
    }
    
    void SendNewCharString(const bool& dataFromMacro=false, const Uint16& offset=0) {
        _j = 0;
        _newCharSize = dataFromMacro ? pData->macroData.size() : pData->newCharCount;
        _willContinuteSending = false;
        _willSendControlKey = false;
        
        if (_newCharSize > 0) {
            for (_k = dataFromMacro ? offset : pData->newCharCount - 1 - offset;
                 dataFromMacro ? _k < (int)pData->macroData.size() : _k >= 0;
                 dataFromMacro ? _k++ : _k--) {
                
                if (_j >= 16) {
                    _willContinuteSending = true;
                    break;
                }
                
                _tempChar = DYNA_DATA(dataFromMacro, _k);
                if (_tempChar & PURE_CHARACTER_MASK) {
                    _newCharString[_j++] = _tempChar;
                    if (IS_DOUBLE_CODE(vCodeTable)) {
                        InsertKeyLength(1);
                    }
                } else if (!(_tempChar & CHAR_CODE_MASK)) {
                    if (IS_DOUBLE_CODE(vCodeTable)) //VNI
                        InsertKeyLength(1);
                    _newCharString[_j++] = keyCodeToCharacter(_tempChar);
                } else {
                    if (vCodeTable == 0) {  //unicode 2 bytes code
                        _newCharString[_j++] = _tempChar;
                    } else if (vCodeTable == 1 || vCodeTable == 2 || vCodeTable == 4) { //others such as VNI Windows, TCVN3: 1 byte code
                        _newChar = _tempChar;
                        _newCharHi = HIBYTE(_newChar);
                        _newChar = LOBYTE(_newChar);
                        _newCharString[_j++] = _newChar;
                        
                        if (_newCharHi > 32) {
                            if (vCodeTable == 2) //VNI
                                InsertKeyLength(2);
                            _newCharString[_j++] = _newCharHi;
                            _newCharSize++;
                        } else {
                            if (vCodeTable == 2) //VNI
                                InsertKeyLength(1);
                        }
                    } else if (vCodeTable == 3) { //Unicode Compound
                        _newChar = _tempChar;
                        _newCharHi = (_newChar >> 13);
                        _newChar &= 0x1FFF;
                        
                        InsertKeyLength(_newCharHi > 0 ? 2 : 1);
                        _newCharString[_j++] = _newChar;
                        if (_newCharHi > 0) {
                            _newCharSize++;
                            _newCharString[_j++] = _unicodeCompoundMark[_newCharHi - 1];
                        }
                        
                    }
                }
            }//end for
        }
        
        if (!_willContinuteSending && (pData->code == vRestore || pData->code == vRestoreAndStartNewSession)) { //if is restore
            if (keyCodeToCharacter(_keycode) != 0) {
                _newCharSize++;
                _newCharString[_j++] = keyCodeToCharacter(_keycode | ((_flag & kCGEventFlagMaskAlphaShift) || (_flag & kCGEventFlagMaskShift) ? CAPS_MASK : 0));
            } else {
                _willSendControlKey = true;
            }
        }
        if (!_willContinuteSending && pData->code == vRestoreAndStartNewSession) {
            startNewSession();
        }
        
        PostUnicodeString(
            _newCharString,
            _willContinuteSending ? 16 : _newCharSize - offset);

        if (_willContinuteSending) {
            SendNewCharString(dataFromMacro, dataFromMacro ? _k : 16);
        }
        
        //the case when hCode is vRestore or vRestoreAndStartNewSession, the word is invalid and last key is control key such as TAB, LEFT ARROW, RIGHT ARROW,...
        if (_willSendControlKey) {
            SendKeyCode(_keycode);
        }
    }
            
    bool checkHotKey(int hotKeyData, bool checkKeyCode=true) {
        if ((Uint32)(hotKeyData & (~0x8000)) == (Uint32)EMPTY_HOTKEY)
            return false;
        CGEventFlags flagToCheck = checkKeyCode ? _flag : _lastFlag;
        if (HAS_CONTROL(hotKeyData) ^ GET_BOOL(flagToCheck & kCGEventFlagMaskControl))
            return false;
        if (HAS_OPTION(hotKeyData) ^ GET_BOOL(flagToCheck & kCGEventFlagMaskAlternate))
            return false;
        if (HAS_COMMAND(hotKeyData) ^ GET_BOOL(flagToCheck & kCGEventFlagMaskCommand))
            return false;
        if (HAS_SHIFT(hotKeyData) ^ GET_BOOL(flagToCheck & kCGEventFlagMaskShift))
            return false;
        if (checkKeyCode) {
            if (GET_SWITCH_KEY(hotKeyData) != _keycode)
                return false;
        }
        return true;
    }
    
    void switchLanguage() {
        if (vLanguage == 0)
            vLanguage = 1;
        else
            vLanguage = 0;
        if (HAS_BEEP(vSwitchKeyStatus))
            NSBeep();
        rust_onInputMethodChanged(vLanguage);
        startNewSession();
    }
    
    void handleMacro() {
        //fix autocomplete
        if (shouldUseRecommendWorkaround(FRONT_APP)) {
            SendEmptyCharacter();
            pData->backspaceCount++;
        }
        
        //send backspace
        if (pData->backspaceCount > 0) {
            if (CFAbsoluteTimeGetCurrent() - _lastAppSwitchTime < 0.5) {
                usleep(15000); // 15ms delay to let the new app settle
            }
            for (int i = 0; i < pData->backspaceCount; i++) {
                SendBackspace();
            }
        }
        //send real data
        if (!vSendKeyStepByStep) {
            if (vUsePasteWorkaround && containUnicodeCompoundApp(FRONT_APP)) {
                _usePasteInsteadOfEvent = true;
            }
            SendNewCharString(true);
            _usePasteInsteadOfEvent = false;
        } else {
            for (size_t i = 0; i < pData->macroData.size(); i++) {
                if (pData->macroData[i] & PURE_CHARACTER_MASK) {
                    SendPureCharacter(pData->macroData[i]);
                } else {
                    SendKeyCode(pData->macroData[i]);
                }
            }
        }
        SendKeyCode(_keycode | (_flag & kCGEventFlagMaskShift ? CAPS_MASK : 0));
    }

    // TODO: Research API to convert character into CGKeyCode more elegantly!
    int ConvertKeyStringToKeyCode(NSString *keyString, CGKeyCode fallback) {
        // Infomation about capitalization (shift/caps) is already included
        // in the original CGEvent, only find out which position on keyboard a key is pressed
        NSString *lowercasedKeyString = [keyString lowercaseString];
        if (!lowercasedKeyString) {
            return fallback;
        }
        
        NSNumber *keycode = [keyStringToKeyCodeMap objectForKey:lowercasedKeyString];

        if (keycode) {
            return [keycode intValue];
        }
        return fallback;
    }

    // If conversion fails, return fallbackKeyCode
    CGKeyCode ConvertEventToKeyboadLayoutCompatKeyCode(CGEventRef keyEvent, CGKeyCode fallbackKeyCode) {
        NSEvent *kbLayoutCompatEvent = [NSEvent eventWithCGEvent:keyEvent];
        NSString *kbLayoutCompatKeyString = kbLayoutCompatEvent.charactersIgnoringModifiers;
        return ConvertKeyStringToKeyCode(kbLayoutCompatKeyString,
                                         fallbackKeyCode);
    }

    /**
     * MAIN HOOK entry, very important function.
     * MAIN Callback.
     */
    CGEventRef VNKeyCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
        (void)refcon;
        if (type == kCGEventTapDisabledByTimeout) {
            // System timeout – safe to re-enable immediately.
            if (eventTap) {
                CGEventTapEnable(eventTap, true);
            }
            return event;
        }
        if (type == kCGEventTapDisabledByUserInput) {
            // Accessibility permission was revoked by the user or tap was disabled by OS.
            // Do NOT call AXIsProcessTrusted() on the main thread here as it synchronously
            // queries TCC daemon and will deadlock the system. Dispatch to Rust to handle
            // teardown and background verification.
            dispatch_async(dispatch_get_main_queue(), ^{
                rust_onAccessibilityRevoked();
            });
            return event;
        }
        //dont handle my event
        if (CGEventGetIntegerValueField(event, kCGEventSourceStateID) == CGEventSourceGetSourceStateID(myEventSource)) {
            return event;
        }
        
        _flag = CGEventGetFlags(event);
        _keycode = (CGKeyCode)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
        
        if (type == kCGEventKeyDown) {
            if ((_keycode == 49 && (_flag & kCGEventFlagMaskCommand)) || _keycode == 160 || _keycode == 131) {
                forceCheckSpotlightVisible();
            }
        }
        
        if (type == kCGEventKeyDown && vPerformLayoutCompat) {
            // If conversion fail, use current keycode
           _keycode = ConvertEventToKeyboadLayoutCompatKeyCode(event, _keycode);
        }
        
        //switch language shortcut; convert hotkey
        if (type == kCGEventKeyDown) {
            if (!vDisableHotkeys) {
                if (clipboardHistoryEnabled && GET_SWITCH_KEY(clipboardHotKey) == _keycode && checkHotKey(clipboardHotKey, GET_SWITCH_KEY(clipboardHotKey) != 0xFE)) {
                    rust_onToggleClipboardPicker();
                    _lastFlag = 0;
                    _hasJustUsedHotKey = true;
                    return NULL;
                }

                if (GET_SWITCH_KEY(panelHotKey) == _keycode && checkHotKey(panelHotKey, GET_SWITCH_KEY(panelHotKey) != 0xFE)) {
                    rust_onToggleControlPanel();
                    _lastFlag = 0;
                    _hasJustUsedHotKey = true;
                    return NULL;
                }

                if (GET_SWITCH_KEY(vSwitchKeyStatus) != _keycode && GET_SWITCH_KEY(convertToolHotKey) != _keycode) {
                    _lastFlag = 0;
                } else {
                    if (GET_SWITCH_KEY(vSwitchKeyStatus) == _keycode && checkHotKey(vSwitchKeyStatus, GET_SWITCH_KEY(vSwitchKeyStatus) != 0xFE)){
                        switchLanguage();
                        _lastFlag = 0;
                        _hasJustUsedHotKey = true;
                        return NULL;
                    }
                    if (GET_SWITCH_KEY(convertToolHotKey) == _keycode && checkHotKey(convertToolHotKey, GET_SWITCH_KEY(convertToolHotKey) != 0xFE)){
                        rust_onQuickConvert();
                        _lastFlag = 0;
                        _hasJustUsedHotKey = true;
                        return NULL;
                    }
                }
                _hasJustUsedHotKey = _lastFlag != 0;
            }
        } else if (type == kCGEventFlagsChanged) {
            if (vDisableHotkeys) {
                _lastFlag = 0;
                _hasJustUsedHotKey = false;
            } else {
                if (_lastFlag == 0 || _lastFlag < _flag) {
                    _lastFlag = _flag;
                } else if (_lastFlag > _flag)  {
                    //check switch
                    if (checkHotKey(vSwitchKeyStatus, GET_SWITCH_KEY(vSwitchKeyStatus) != 0xFE)) {
                        _lastFlag = 0;
                        switchLanguage();
                        _hasJustUsedHotKey = true;
                        return NULL;
                    }
                    if (checkHotKey(convertToolHotKey, GET_SWITCH_KEY(convertToolHotKey) != 0xFE)) {
                        _lastFlag = 0;
                        rust_onQuickConvert();
                        _hasJustUsedHotKey = true;
                        return NULL;
                    }
                    _lastFlag = 0;
                    _hasJustUsedHotKey = false;
                }
            }
        }

        // Also check correct event hooked
        if ((type != kCGEventKeyDown) && (type != kCGEventKeyUp) &&
            (type != kCGEventLeftMouseDown) && (type != kCGEventRightMouseDown) &&
            (type != kCGEventLeftMouseDragged) && (type != kCGEventRightMouseDragged))
            return event;
        
        _proxy = proxy;
        refreshFrontMostAppIfNeeded();
        
        // If current system input source is not English, do not process characters and clear buffer
        if (!_currentInputSourceIsEnglish) {
            RequestNewSession();
            return event;
        }
        
        //If is in english mode
        if (vLanguage == 0) {
            if (vUseMacro && vUseMacroInEnglishMode && type == kCGEventKeyDown) {
                vEnglishMode((type == kCGEventKeyDown ? vKeyEventState::KeyDown : vKeyEventState::MouseDown),
                             _keycode,
                             (_flag & kCGEventFlagMaskShift) || (_flag & kCGEventFlagMaskAlphaShift),
                             OTHER_CONTROL_KEY);
                
                if (pData->code == vReplaceMaro) { //handle macro in english mode
                    handleMacro();
                    return NULL;
                }
            }
            return event;
        }
        
        //handle mouse
        if (type == kCGEventLeftMouseDown || type == kCGEventRightMouseDown || type == kCGEventLeftMouseDragged || type == kCGEventRightMouseDragged) {
            RequestNewSession();
            return event;
        }


        //handle keyboard
        if (type == kCGEventKeyDown) {
            //send event signal to Engine
            vKeyHandleEvent(vKeyEvent::Keyboard,
                            vKeyEventState::KeyDown,
                            _keycode,
                            _flag & kCGEventFlagMaskShift ? 1 : (_flag & kCGEventFlagMaskAlphaShift ? 2 : 0),
                            OTHER_CONTROL_KEY);
            if (pData->code == vDoNothing) { //do nothing
                if (IS_DOUBLE_CODE(vCodeTable)) { //VNI
                    if (pData->extCode == 1) { //break key
                        _syncKey.clear();
                    } else if (pData->extCode == 2) { //delete key
                        if (_syncKey.size() > 0) {
                            if (_syncKey.back() > 1 && (vCodeTable == 2 || !containUnicodeCompoundApp(FRONT_APP))) {
                                //send one more backspace
                                CGEventTapPostEvent(_proxy, eventBackSpaceDown);
                                CGEventTapPostEvent(_proxy, eventBackSpaceUp);
                            }
                            _syncKey.pop_back();
                        }
                       
                    } else if (pData->extCode == 3) { //normal key
                        InsertKeyLength(1);
                    }
                }
                return event;
            } else if (pData->code == vWillProcess || pData->code == vRestore || pData->code == vRestoreAndStartNewSession) { //handle result signal
                
                //fix autocomplete
                if (shouldUseRecommendWorkaround(FRONT_APP) && pData->extCode != 4) {
                    if (vFixChromiumBrowser && containUnicodeCompoundApp(FRONT_APP)) {
                        if (pData->backspaceCount > 0) {
                            SendShiftAndLeftArrow();
                            if (pData->backspaceCount == 1)
                                pData->backspaceCount--;
                        }
                    } else {
                        SendEmptyCharacter();
                        pData->backspaceCount++;
                    
                    }
                }

                if (shouldUseSelectionReplacement(FRONT_APP) && pData->backspaceCount > 0) {
                    for (_i = 0; _i < pData->backspaceCount; _i++) {
                        SendShiftAndLeftArrow();
                    }
                    pData->backspaceCount = 0;
                }
                
                //send backspace
                if (pData->backspaceCount > 0 && pData->backspaceCount < MAX_BUFF) {
                    for (_i = 0; _i < pData->backspaceCount; _i++) {
                        SendBackspace();
                        if (pData->backspaceCount > 1) {
                            usleep(3000); // Trễ 3ms cho bộ đệm OS
                        }
                    }
                    usleep(3000); // Trễ 3ms trước khi chèn chữ mới
                }
                
                //send new character
                if (!vSendKeyStepByStep) {
                    if (vUsePasteWorkaround && containUnicodeCompoundApp(FRONT_APP) &&
                        (pData->code == vRestore || pData->code == vRestoreAndStartNewSession)) {
                        _usePasteInsteadOfEvent = true;
                    }
                    SendNewCharString();
                    _usePasteInsteadOfEvent = false;
                } else {
                    if (pData->newCharCount > 0 && pData->newCharCount <= MAX_BUFF) {
                        for (int i = pData->newCharCount - 1; i >= 0; i--) {
                            SendKeyCode(pData->charData[i]);
                        }
                    }
                    if (pData->code == vRestore || pData->code == vRestoreAndStartNewSession) {
                        bool isControlKey = (_keycode == KEY_SPACE || _keycode == KEY_RETURN || _keycode == KEY_ENTER || _keycode == KEY_TAB || _keycode == KEY_ESC || _keycode == KEY_DELETE);
                        if (isControlKey) {
                            SendKeyCode(_keycode | ((_flag & kCGEventFlagMaskAlphaShift) || (_flag & kCGEventFlagMaskShift) ? CAPS_MASK : 0));
                        }
                    }
                    if (pData->code == vRestoreAndStartNewSession) {
                        startNewSession();
                    }
                }
            } else if (pData->code == vReplaceMaro) { //MACRO
                handleMacro();
            }
            
            return NULL;
        }
        
        return event;
    }

    bool is_accessibility_granted() {
        return AXIsProcessTrusted();
    }

    void request_accessibility_permission() {
        // Try the standard API first (works on fresh installs)
        NSDictionary *options = @{(__bridge id)kAXTrustedCheckOptionPrompt: @YES};
        AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
        // On macOS 13+, after a revoke the above may not open System Settings.
        // Open directly via deep link as a reliable fallback.
        NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"];
        [[NSWorkspace sharedWorkspace] openURL:url];
    }

    void onInputSourceChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
        (void)center;
        (void)observer;
        (void)name;
        (void)object;
        (void)userInfo;
        refreshCurrentInputSource();
        rust_onInputMethodChanged(vLanguage);
        RequestNewSession();
    }

    bool start_event_tap() {
        if (_isInited)
            return true;
        
        VNKeyInit();
        queryFrontMostApp();
        refreshCurrentInputSource();
        
        eventMask = ((1 << kCGEventKeyDown) |
                     (1 << kCGEventKeyUp) |
                     (1 << kCGEventFlagsChanged) |
                     (1 << kCGEventLeftMouseDown) |
                     (1 << kCGEventRightMouseDown) |
                     (1 << kCGEventLeftMouseDragged) |
                     (1 << kCGEventRightMouseDragged));
        
        eventTap = CGEventTapCreate(kCGSessionEventTap,
                                    kCGHeadInsertEventTap,
                                    (CGEventTapOptions)0,
                                    eventMask,
                                    VNKeyCallback,
                                    NULL);
        
        if (!eventTap) {
            fprintf(stderr, "failed to create event tap\n");
            return false;
        }
        
        _isInited = true;
        
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
        CGEventTapEnable(eventTap, true);
        
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDistributedCenter(),
            NULL,
            onInputSourceChanged,
            kTISNotifySelectedKeyboardInputSourceChanged,
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        activeAppObserver = [[[NSWorkspace sharedWorkspace] notificationCenter] addObserverForName:NSWorkspaceDidActivateApplicationNotification
                                                                        object:nil
                                                                         queue:[NSOperationQueue mainQueue]
                                                                    usingBlock:^(NSNotification * _Nonnull note) {
            NSRunningApplication *app = note.userInfo[NSWorkspaceApplicationKey];
            if (app) {
                NSString *bundleId = app.bundleIdentifier;
                if (bundleId != nil) {
                    _frontMostApp = bundleId;
                } else if (app.localizedName != nil) {
                    _frontMostApp = app.localizedName;
                } else {
                    _frontMostApp = @"UnknownApp";
                }
                _lastAppSwitchTime = CFAbsoluteTimeGetCurrent();
                OnActiveAppChanged();
            }
        }];

        return true;
    }

    void stop_event_tap() {
        if (_isInited) {
            if (activeAppObserver) {
                [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:activeAppObserver];
                activeAppObserver = nil;
            }
            if (runLoopSource) {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
                CFRelease(runLoopSource);
                runLoopSource = NULL;
            }
            if (eventTap) {
                CFMachPortInvalidate(eventTap);
                CFRelease(eventTap);
                eventTap = NULL;
            }
            CFNotificationCenterRemoveObserver(
                CFNotificationCenterGetDistributedCenter(),
                NULL,
                kTISNotifySelectedKeyboardInputSourceChanged,
                NULL
            );
            VNKeyFree();
            _isInited = false;
        }
    }

    bool do_quick_convert() {
        NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
        NSString *htmlString = [pasteboard stringForType:NSPasteboardTypeHTML];
        NSString *rawString = [pasteboard stringForType:NSPasteboardTypeString];
        bool converted = false;
        if (htmlString != nil) {
            htmlString = [NSString stringWithUTF8String:convertUtil([htmlString UTF8String]).c_str()];
            converted = true;
        }
        if (rawString != nil) {
            rawString = [NSString stringWithUTF8String:convertUtil([rawString UTF8String]).c_str()];
            converted = true;
        }
        if (converted) {
            [pasteboard clearContents];
            if (htmlString != nil)
                [pasteboard setString:htmlString forType:NSPasteboardTypeHTML];
            if (rawString != nil)
                [pasteboard setString:rawString forType:NSPasteboardTypeString];
            return true;
        }
        return false;
    }

    const uint8_t* get_macos_status_icon(bool vietnamese, bool gray, int inputType, int* len) {
        @autoreleasepool {
            BOOL isNotEnglish = !_currentInputSourceIsEnglish || !AXIsProcessTrusted();

            // When inputType < 0, don't show input type label (show original small icon)
            if (inputType < 0) {
                NSSize size = NSMakeSize(18, 18);
                NSImage* image = [NSImage imageWithSize:size flipped:NO drawingHandler:^BOOL(NSRect rect) {
                    NSColor* color = gray ? [NSColor blackColor] : [NSColor colorWithSRGBRed:0.0/255.0 green:102.0/255.0 blue:171.0/255.0 alpha:1.0];
                    if (isNotEnglish) {
                        color = [color colorWithAlphaComponent:0.4];
                    }

                    NSRect frameRect = NSInsetRect(rect, 1, 1);
                    NSBezierPath* frame = [NSBezierPath bezierPathWithRoundedRect:frameRect xRadius:2 yRadius:2];
                    [color setFill];
                    [frame fill];

                    NSString* text = vietnamese ? @"V" : @"E";
                    NSFont* font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];

                    NSDictionary* sizeAttrs = @{ NSFontAttributeName: font };
                    NSSize textSize = [text sizeWithAttributes:sizeAttrs];

                    CGFloat x = NSMidX(frameRect) - textSize.width / 2.0;
                    CGFloat y = NSMidY(frameRect) - font.capHeight / 2.0 + font.descender;

                    if (gray) {
                        [NSGraphicsContext saveGraphicsState];
                        [[NSGraphicsContext currentContext] setCompositingOperation:NSCompositingOperationDestinationOut];
                        NSDictionary* attrs = @{
                            NSFontAttributeName: font,
                            NSForegroundColorAttributeName: [NSColor blackColor]
                        };
                        [text drawAtPoint:NSMakePoint(x, y) withAttributes:attrs];
                        [NSGraphicsContext restoreGraphicsState];
                    } else {
                        NSColor* textColor = [NSColor whiteColor];
                        if (isNotEnglish) {
                            textColor = [textColor colorWithAlphaComponent:0.4];
                        }
                        NSDictionary* attrs = @{
                            NSFontAttributeName: font,
                            NSForegroundColorAttributeName: textColor
                        };
                        [text drawAtPoint:NSMakePoint(x, y) withAttributes:attrs];
                    }
                    return YES;
                }];

                [image setTemplate:gray];

                CGImageRef cgImage = [image CGImageForProposedRect:NULL context:nil hints:nil];
                NSBitmapImageRep* bitmapRep = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];
                NSData* pngData = [bitmapRep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];

                if (pngData) {
                    *len = (int)[pngData length];
                    uint8_t* buffer = (uint8_t*)malloc(*len);
                    memcpy(buffer, [pngData bytes], *len);
                    return buffer;
                }

                *len = 0;
                return NULL;
            }

            // Input type full labels
            NSString* inputLabel = @"";
            if (vietnamese) {
                switch (inputType) {
                    case 0: inputLabel = @"Telex"; break;
                    case 1: inputLabel = @"VNI"; break;
                    case 2: inputLabel = @"S.Telex1"; break;
                    case 3: inputLabel = @"S.Telex2"; break;
                    default: inputLabel = @"?"; break;
                }
            }

            // Use font size 13, weight Medium for the type label
            NSFont* typeFont = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
            NSDictionary* typeSizeAttrs = @{ NSFontAttributeName: typeFont };
            NSSize typeTextSize = [inputLabel sizeWithAttributes:typeSizeAttrs];

            // Icon size: fixed width enough for indicator + label, height always 18
            CGFloat labelWidth = vietnamese ? ceil(typeTextSize.width) : 0;
            CGFloat totalWidth = 18;
            if (vietnamese && labelWidth > 0) {
                totalWidth = 1 + 16 + 4 + labelWidth + 2;
            }

            NSSize size = NSMakeSize(totalWidth, 18);
            NSImage* image = [NSImage imageWithSize:size flipped:NO drawingHandler:^BOOL(NSRect rect) {
                (void)rect;
                NSColor* color = gray ? [NSColor blackColor] : [NSColor colorWithSRGBRed:0.0/255.0 green:102.0/255.0 blue:171.0/255.0 alpha:1.0];
                if (isNotEnglish) {
                    color = [color colorWithAlphaComponent:0.4];
                }

                // Draw the language indicator box (16x16, same as standalone)
                NSRect indicatorRect = NSMakeRect(1, 1, 16, 16);
                NSBezierPath* indicatorFrame = [NSBezierPath bezierPathWithRoundedRect:indicatorRect xRadius:2 yRadius:2];
                [color setFill];
                [indicatorFrame fill];

                // Draw the language letter inside the indicator box
                NSString* langText = vietnamese ? @"V" : @"E";
                NSFont* langFont = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
                NSDictionary* langSizeAttrs = @{ NSFontAttributeName: langFont };
                NSSize langTextSize = [langText sizeWithAttributes:langSizeAttrs];
                CGFloat langX = NSMidX(indicatorRect) - langTextSize.width / 2.0;
                CGFloat langY = NSMidY(indicatorRect) - langFont.capHeight / 2.0 + langFont.descender;

                if (gray) {
                    [NSGraphicsContext saveGraphicsState];
                    [[NSGraphicsContext currentContext] setCompositingOperation:NSCompositingOperationDestinationOut];
                    NSDictionary* langAttrs = @{
                        NSFontAttributeName: langFont,
                        NSForegroundColorAttributeName: [NSColor blackColor]
                    };
                    [langText drawAtPoint:NSMakePoint(langX, langY) withAttributes:langAttrs];
                    [NSGraphicsContext restoreGraphicsState];
                } else {
                    NSColor* textColor = [NSColor whiteColor];
                    if (isNotEnglish) {
                        textColor = [textColor colorWithAlphaComponent:0.4];
                    }
                    NSDictionary* langAttrs = @{
                        NSFontAttributeName: langFont,
                        NSForegroundColorAttributeName: textColor
                    };
                    [langText drawAtPoint:NSMakePoint(langX, langY) withAttributes:langAttrs];
                }

                // Draw the input type label to the right with font 13 Medium, vertically centered
                if (vietnamese && [inputLabel length] > 0) {
                    NSColor* typeColor = color;

                    NSDictionary* typeAttrs = @{
                        NSFontAttributeName: typeFont,
                        NSForegroundColorAttributeName: typeColor
                    };
                    CGFloat typeX = NSMaxX(indicatorRect) + 4;
                    // Vertically center to match the visual height of the main icon
                    CGFloat typeY = NSMidY(indicatorRect) - typeFont.capHeight / 2.0 + typeFont.descender;

                    [inputLabel drawAtPoint:NSMakePoint(typeX, typeY) withAttributes:typeAttrs];
                }

                return YES;
            }];

            // Do NOT set template for wider icons - let macOS draw them directly
            [image setTemplate:NO];

            CGImageRef cgImage = [image CGImageForProposedRect:NULL context:nil hints:nil];
            NSBitmapImageRep* bitmapRep = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];
            NSData* pngData = [bitmapRep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];

            if (pngData) {
                *len = (int)[pngData length];
                uint8_t* buffer = (uint8_t*)malloc(*len);
                memcpy(buffer, [pngData bytes], *len);
                return buffer;
            }

            *len = 0;
            return NULL;
        }
    }

    long macos_clipboard_get_change_count() {
        return [[NSPasteboard generalPasteboard] changeCount];
    }

    bool macos_clipboard_is_sensitive() {
        @autoreleasepool {
            NSPasteboard *pb = [NSPasteboard generalPasteboard];
            NSArray *types = [pb types];
            for (NSString *type in types) {
                if ([type isEqualToString:@"org.nspasteboard.ConcealedType"] ||
                    [type isEqualToString:@"org.nspasteboard.TransientType"] ||
                    [type isEqualToString:@"com.agilebits.onepassword"] ||
                    [type isEqualToString:@"com.apple.is-sensitive"]) {
                    return true;
                }
            }
            return false;
        }
    }

    char* macos_clipboard_read_text() {
        @autoreleasepool {
            NSString *str = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
            if (!str) return NULL;
            const char *utf8 = [str UTF8String];
            return strdup(utf8);
        }
    }

    char* macos_clipboard_read_html() {
        @autoreleasepool {
            NSString *str = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeHTML];
            if (!str) return NULL;
            const char *utf8 = [str UTF8String];
            return strdup(utf8);
        }
    }

    char* macos_clipboard_read_file_urls() {
        @autoreleasepool {
            // Read file URLs as a newline separated string of paths
            NSArray *urls = [[NSPasteboard generalPasteboard] readObjectsForClasses:@[[NSURL class]] options:nil];
            if (!urls || [urls count] == 0) return NULL;
            
            NSMutableArray *paths = [NSMutableArray array];
            for (NSURL *url in urls) {
                if ([url isFileURL]) {
                    [paths addObject:[url path]];
                }
            }
            if ([paths count] == 0) return NULL;
            
            NSString *joined = [paths componentsJoinedByString:@"\n"];
            return strdup([joined UTF8String]);
        }
    }

    uint8_t* macos_clipboard_get_image_png(int* len) {
        @autoreleasepool {
            NSPasteboard *pb = [NSPasteboard generalPasteboard];
            
            // Check if there are file URLs first
            NSArray *urls = [pb readObjectsForClasses:@[[NSURL class]] options:nil];
            if (urls && [urls count] > 0) {
                NSURL *fileURL = urls[0];
                if ([fileURL isFileURL]) {
                    // Try QuickLook thumbnail
                    NSDictionary *options = @{ (id)kQLThumbnailOptionIconModeKey: @(NO) };
                    CGImageRef thumbnailCG = QLThumbnailImageCreate(kCFAllocatorDefault, (__bridge CFURLRef)fileURL, CGSizeMake(120, 120), (__bridge CFDictionaryRef)options);
                    if (thumbnailCG) {
                        NSBitmapImageRep* rep = [[NSBitmapImageRep alloc] initWithCGImage:thumbnailCG];
                        NSData* png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
                        CFRelease(thumbnailCG);
                        if (png) {
                            *len = (int)[png length];
                            uint8_t* buf = (uint8_t*)malloc(*len);
                            memcpy(buf, [png bytes], *len);
                            return buf;
                        }
                    }
                    
                    // Direct image read
                    NSString *path = [fileURL path];
                    NSString *ext = [[path pathExtension] lowercaseString];
                    NSArray *imgExts = @[@"png", @"jpg", @"jpeg", @"tiff", @"gif", @"heic", @"webp"];
                    if ([imgExts containsObject:ext]) {
                        NSData *data = [NSData dataWithContentsOfFile:path];
                        if (data && [data length] <= 12 * 1024 * 1024) {
                            NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:data];
                            if (rep) {
                                NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
                                if (png) {
                                    *len = (int)[png length];
                                    uint8_t* buf = (uint8_t*)malloc(*len);
                                    memcpy(buf, [png bytes], *len);
                                    return buf;
                                }
                            }
                        }
                    }
                    
                    // Fallback to system icon
                    NSImage *icon = [[NSWorkspace sharedWorkspace] iconForFile:path];
                    if (icon) {
                        CGImageRef iconCG = [icon CGImageForProposedRect:NULL context:nil hints:nil];
                        NSBitmapImageRep* rep = [[NSBitmapImageRep alloc] initWithCGImage:iconCG];
                        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
                        if (png) {
                            *len = (int)[png length];
                            uint8_t* buf = (uint8_t*)malloc(*len);
                            memcpy(buf, [png bytes], *len);
                            return buf;
                        }
                    }
                }
            }
            
            // Check direct image data in pasteboard
            NSArray *images = [pb readObjectsForClasses:@[[NSImage class]] options:nil];
            if ([images count] > 0) {
                NSImage *image = images[0];
                CGImageRef imageCG = [image CGImageForProposedRect:NULL context:nil hints:nil];
                if (imageCG) {
                    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:imageCG];
                    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
                    if (png) {
                        *len = (int)[png length];
                        uint8_t *buf = (uint8_t*)malloc(*len);
                        memcpy(buf, [png bytes], *len);
                        return buf;
                    }
                }
            }

            NSArray *types = [pb types];
            NSData *imgData = nil;
            BOOL isPNG = NO;
            if ([types containsObject:NSPasteboardTypePNG]) {
                imgData = [pb dataForType:NSPasteboardTypePNG];
                isPNG = YES;
            } else if ([types containsObject:NSPasteboardTypeTIFF]) {
                imgData = [pb dataForType:NSPasteboardTypeTIFF];
            }
            
            if (imgData && [imgData length] <= 12 * 1024 * 1024) {
                if (isPNG) {
                    *len = (int)[imgData length];
                    uint8_t* buf = (uint8_t*)malloc(*len);
                    memcpy(buf, [imgData bytes], *len);
                    return buf;
                } else {
                    NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:imgData];
                    if (rep) {
                        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
                        if (png) {
                            *len = (int)[png length];
                            uint8_t* buf = (uint8_t*)malloc(*len);
                            memcpy(buf, [png bytes], *len);
                            return buf;
                        }
                    }
                }
            }
            
            *len = 0;
            return NULL;
        }
    }

    void macos_clipboard_paste(int prev_pid, const char* text, const char* html, const char* image_file_path, const char* file_paths_joined) {
        @autoreleasepool {
            NSPasteboard *pb = [NSPasteboard generalPasteboard];
            [pb clearContents];
            
            NSMutableArray *pbItems = [NSMutableArray array];
            BOOL hasData = NO;
            
            NSRunningApplication* prevApp = [NSRunningApplication runningApplicationWithProcessIdentifier:prev_pid];
            BOOL isTargetFinder = prevApp ? [[prevApp bundleIdentifier] isEqualToString:@"com.apple.finder"] : NO;
            
            // Process file paths if any
            NSMutableArray *activeFilePaths = [NSMutableArray array];
            if (file_paths_joined && strlen(file_paths_joined) > 0) {
                NSString *joinedStr = [NSString stringWithUTF8String:file_paths_joined];
                NSArray *paths = [joinedStr componentsSeparatedByString:@"\n"];
                for (NSString *p in paths) {
                    if ([[NSFileManager defaultManager] fileExistsAtPath:p]) {
                        [activeFilePaths addObject:p];
                    }
                }
            }
            
            if ([activeFilePaths count] == 0 && isTargetFinder) {
                // If target is Finder and we copy an image, create a temp file to paste
                if (image_file_path && strlen(image_file_path) > 0) {
                    NSString *img_path = [NSString stringWithUTF8String:image_file_path];
                    if ([[NSFileManager defaultManager] fileExistsAtPath:img_path]) {
                        NSURL *tempDir = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
                        int timestamp = (int)[[NSDate date] timeIntervalSince1970];
                        NSURL *tempFileURL = [tempDir URLByAppendingPathComponent:[NSString stringWithFormat:@"Anh_Clipboard_%d.png", timestamp]];
                        NSData *data = [NSData dataWithContentsOfFile:img_path];
                        if (data && [data writeToURL:tempFileURL atomically:YES]) {
                            [activeFilePaths addObject:[tempFileURL path]];
                        }
                    }
                } else if (text && strlen(text) > 0) {
                    // If target is Finder and we copy text, create a temp txt/rtf file to paste
                    NSURL *tempDir = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
                    int timestamp = (int)[[NSDate date] timeIntervalSince1970];
                    
                    if (html && strlen(html) > 0) {
                        NSString *htmlStr = [NSString stringWithUTF8String:html];
                        NSData *htmlData = [htmlStr dataUsingEncoding:NSUTF8StringEncoding];
                        NSDictionary *options = @{
                            NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType,
                            NSCharacterEncodingDocumentAttribute: @(NSUTF8StringEncoding)
                        };
                        NSAttributedString *attrStr = [[NSAttributedString alloc] initWithData:htmlData options:options documentAttributes:nil error:nil];
                        if (attrStr) {
                            NSData *rtfData = [attrStr dataFromRange:NSMakeRange(0, [attrStr length]) documentAttributes:@{NSDocumentTypeDocumentAttribute: NSRTFTextDocumentType} error:nil];
                            if (rtfData) {
                                NSURL *tempFileURL = [tempDir URLByAppendingPathComponent:[NSString stringWithFormat:@"Van_ban_Clipboard_%d.rtf", timestamp]];
                                if ([rtfData writeToURL:tempFileURL atomically:YES]) {
                                    [activeFilePaths addObject:[tempFileURL path]];
                                }
                            }
                        }
                    }
                    
                    if ([activeFilePaths count] == 0) {
                        NSURL *tempFileURL = [tempDir URLByAppendingPathComponent:[NSString stringWithFormat:@"Van_ban_Clipboard_%d.txt", timestamp]];
                        NSString *textStr = [NSString stringWithUTF8String:text];
                        if ([textStr writeToURL:tempFileURL atomically:YES encoding:NSUTF8StringEncoding error:nil]) {
                            [activeFilePaths addObject:[tempFileURL path]];
                        }
                    }
                }
            }
            
            if ([activeFilePaths count] > 0) {
                for (NSString *path in activeFilePaths) {
                    NSPasteboardItem *fileItem = [[NSPasteboardItem alloc] init];
                    NSURL *fileURL = [NSURL fileURLWithPath:path];
                    [fileItem setString:[fileURL absoluteString] forType:NSPasteboardTypeFileURL];
                    [pbItems addObject:fileItem];
                }
                hasData = YES;
            }
            
            if (image_file_path && strlen(image_file_path) > 0 && [activeFilePaths count] == 0) {
                NSString *img_path = [NSString stringWithUTF8String:image_file_path];
                NSData *data = [NSData dataWithContentsOfFile:img_path];
                if (data) {
                    NSPasteboardItem *imageItem = [[NSPasteboardItem alloc] init];
                    [imageItem setData:data forType:NSPasteboardTypePNG];
                    NSImage *image = [[NSImage alloc] initWithData:data];
                    if (image) {
                        NSData *tiffData = [image TIFFRepresentation];
                        if (tiffData) {
                            [imageItem setData:tiffData forType:NSPasteboardTypeTIFF];
                        }
                    }
                    [pbItems addObject:imageItem];
                    hasData = YES;
                }
            } else if ([activeFilePaths count] == 0) {
                NSPasteboardItem *textItem = [[NSPasteboardItem alloc] init];
                if (text) {
                    [textItem setString:[NSString stringWithUTF8String:text] forType:NSPasteboardTypeString];
                }
                if (html) {
                    [textItem setString:[NSString stringWithUTF8String:html] forType:NSPasteboardTypeHTML];
                }
                [pbItems addObject:textItem];
                hasData = YES;
            }
            
            if (hasData) {
                [pb writeObjects:pbItems];
                if ([activeFilePaths count] > 0) {
                    [pb setPropertyList:activeFilePaths forType:@"NSFilenamesPboardType"];
                }
            }
            
            // Activate the previous application
            if (prevApp) {
                [prevApp activateWithOptions:NSApplicationActivateIgnoringOtherApps];
            }
            
            // Post Cmd + V keypresses after a small delay
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                CGEventSourceRef src = CGEventSourceCreate(kCGEventSourceStateCombinedSessionState);
                CGEventRef down = CGEventCreateKeyboardEvent(src, (CGKeyCode)9, true); // virtual keycode 9 is 'v'
                CGEventSetFlags(down, kCGEventFlagMaskCommand);
                CGEventRef up = CGEventCreateKeyboardEvent(src, (CGKeyCode)9, false);
                CGEventSetFlags(up, kCGEventFlagMaskCommand);
                CGEventPost(kCGHIDEventTap, down);
                CGEventPost(kCGHIDEventTap, up);
                CFRelease(down);
                CFRelease(up);
                CFRelease(src);
            });
        }
    }

    void macos_configure_clipboard_window(void* ns_window_ptr, bool pin_on_top) {
        @autoreleasepool {
            NSWindow* window = (__bridge NSWindow*)ns_window_ptr;
            if (!window) return;
            
            // Add NonactivatingPanel behavior so it is translucent/overlay spotlight style
            [window setStyleMask:[window styleMask] | NSWindowStyleMaskNonactivatingPanel];
            
            // Set floating level based on pin_on_top
            window.level = pin_on_top ? NSFloatingWindowLevel : NSNormalWindowLevel;
            
            // Apply Popover translucency material
            NSView* contentView = [window contentView];
            for (NSView* subview in [contentView subviews]) {
                if ([subview isKindOfClass:[NSVisualEffectView class]]) {
                    return;
                }
            }
            
            NSVisualEffectView* vibrant = [[NSVisualEffectView alloc] initWithFrame:[contentView bounds]];
            [vibrant setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
            [vibrant setMaterial:NSVisualEffectMaterialPopover];
            [vibrant setBlendingMode:NSVisualEffectBlendingModeBehindWindow];
            [vibrant setState:NSVisualEffectStateActive];
            [contentView addSubview:vibrant positioned:NSWindowBelow relativeTo:nil];
        }
    }

    void macos_configure_hud_window(void* ns_window_ptr) {
        @autoreleasepool {
            NSWindow* window = (__bridge NSWindow*)ns_window_ptr;
            if (!window) return;
            
            // Highest window level — floats above all apps including fullscreen
            // kCGMaximumWindowLevelKey is an enum *key*, not a level value.
            // Must call CGWindowLevelForKey() to obtain the actual numeric level.
            window.level = CGWindowLevelForKey(kCGMaximumWindowLevelKey);
            
            // Do not steal focus when shown
            [window setStyleMask:[window styleMask] | NSWindowStyleMaskNonactivatingPanel];
            [window setIgnoresMouseEvents:YES];
            
            // Transparent background (belt & suspenders alongside Tauri transparent=true)
            [window setBackgroundColor:[NSColor clearColor]];
            [window setOpaque:NO];
            
            // Visible on all Spaces and full-screen apps
            [window setCollectionBehavior:
                NSWindowCollectionBehaviorCanJoinAllSpaces |
                NSWindowCollectionBehaviorStationary |
                NSWindowCollectionBehaviorIgnoresCycle |
                NSWindowCollectionBehaviorFullScreenAuxiliary];
        }
    }

    char* macos_get_frontmost_app_name() {
        @autoreleasepool {
            NSRunningApplication* app = [[NSWorkspace sharedWorkspace] frontmostApplication];
            if (!app) return NULL;
            NSString* name = [app localizedName];
            if (!name) return NULL;
            return strdup([name UTF8String]);
        }
    }

    int macos_get_frontmost_app_pid() {
        @autoreleasepool {
            NSRunningApplication* app = [[NSWorkspace sharedWorkspace] frontmostApplication];
            if (!app) return 0;
            return (int)[app processIdentifier];
        }
    }

    void macos_set_clipboard_hotkey(int val) {
        clipboardHotKey = val;
    }

    void macos_set_panel_hotkey(int val) {
        panelHotKey = val;
    }

    void macos_set_clipboard_enabled(bool enabled) {
        clipboardHistoryEnabled = enabled;
    }

    bool macos_is_another_instance_running() {
        @autoreleasepool {
            NSArray<NSRunningApplication*>* apps = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.theodore.vnkey"];
            pid_t ourPid = [[NSProcessInfo processInfo] processIdentifier];
            for (NSRunningApplication* app in apps) {
                if (app.processIdentifier != ourPid) {
                    return true;
                }
            }
            return false;
        }
    }
    void macos_activate_other_instance() {
        @autoreleasepool {
            NSArray<NSRunningApplication*>* apps = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.theodore.vnkey"];
            pid_t ourPid = [[NSProcessInfo processInfo] processIdentifier];
            for (NSRunningApplication* app in apps) {
                if (app.processIdentifier != ourPid) {
                    [app activateWithOptions:NSApplicationActivateIgnoringOtherApps];
                    break;
                }
            }
        }
    }

    bool macos_is_current_input_source_english() {
        return _currentInputSourceIsEnglish;
    }

    void free_macos_status_icon(const uint8_t* bytes) {
        if (bytes) {
            free((void*)bytes);
        }
    }

    void macos_get_mouse_position(double *x, double *y) {
        @autoreleasepool {
            NSPoint loc = [NSEvent mouseLocation];
            NSScreen *primaryScreen = [[NSScreen screens] objectAtIndex:0];
            double screenHeight = [primaryScreen frame].size.height;
            *x = loc.x;
            *y = screenHeight - loc.y;
        }
    }

    // Get the on-screen bounding rect of the text insertion caret using
    // the macOS Accessibility API.
    // AX screen coordinates already use top-left origin (same as CG/Tauri),
    // so no conversion is needed.
    // *success is set to false when the focused element does not support
    // kAXBoundsForRangeParameterizedAttribute (e.g. Terminal, some Electron apps).
    // Must be called from the main thread.
    void get_caret_position(double *x, double *y, bool *success) {
        *success = false;
        *x = 0.0;
        *y = 0.0;
        @autoreleasepool {
            AXUIElementRef systemWide = AXUIElementCreateSystemWide();
            if (!systemWide) return;

            AXUIElementRef focused = NULL;
            AXError err = AXUIElementCopyAttributeValue(
                systemWide, kAXFocusedUIElementAttribute, (CFTypeRef *)&focused);
            CFRelease(systemWide);
            if (err != kAXErrorSuccess || !focused) return;

            CFTypeRef rangeVal = NULL;
            err = AXUIElementCopyAttributeValue(
                focused, kAXSelectedTextRangeAttribute, &rangeVal);
            if (err == kAXErrorSuccess && rangeVal) {
                CFTypeRef boundsVal = NULL;
                err = AXUIElementCopyParameterizedAttributeValue(
                    focused, kAXBoundsForRangeParameterizedAttribute, rangeVal, &boundsVal);
                CFRelease(rangeVal);
                if (err == kAXErrorSuccess && boundsVal) {
                    CGRect bounds = CGRectZero;
                    AXValueRef axVal = (AXValueRef)boundsVal;
                    Boolean ok = AXValueGetValue(axVal, (AXValueType)kAXValueCGRectType, &bounds);
                    if (ok && !CGRectIsEmpty(bounds)) {
                        // origin.x/y is the top-left of the character in screen coords.
                        *x = bounds.origin.x;
                        *y = bounds.origin.y;
                        *success = true;
                    }
                    CFRelease(boundsVal);
                }
            }
            CFRelease(focused);
        }
    }
}
