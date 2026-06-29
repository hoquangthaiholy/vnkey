//
//  SmartSwitchKey.cpp
//  VNKey
//
//  Created by Tuyen on 8/13/19.
//  Copyright © 2019 Tuyen Mai. All rights reserved.
//

#include "SmartSwitchKey.h"
#include <unordered_map>
#include <memory.h>

//main data, i use `unordered_map` because it has O(1)
static unordered_map<string, Int8> _smartSwitchKeyData;
static string _cacheKey = ""; //use cache for faster
static Int8 _cacheData = 0; //use cache for faster

void initSmartSwitchKey(const Byte* pData, const int& size) {
    _smartSwitchKeyData.clear();
    _cacheKey.clear();
    _cacheData = 0;
    if (pData == NULL || size < 2) return;
    Uint16 count = 0;
    Uint32 cursor = 0;
    memcpy(&count, pData + cursor, 2);
    cursor += 2;
    Uint8 bundleIdSize;
    Uint8 value;
    for (int i = 0; i < count; i++) {
        if (cursor >= (Uint32)size) {
            break;
        }
        bundleIdSize = pData[cursor++];
        if (cursor + bundleIdSize + 1 > (Uint32)size) {
            break;
        }
        string bundleId((char*)pData + cursor, bundleIdSize);
        cursor += bundleIdSize;
        value = pData[cursor++];
        _smartSwitchKeyData[bundleId] = value;
    }
}

void getSmartSwitchKeySaveData(vector<Byte>& outData) {
    outData.clear();
    Uint16 count = (Uint16)_smartSwitchKeyData.size();
    size_t estimatedSize = 2;
    for (const auto& item : _smartSwitchKeyData) {
        estimatedSize += item.first.size() + 2;
    }
    outData.reserve(estimatedSize);
    outData.push_back((Byte)count);
    outData.push_back((Byte)(count>>8));
    
    for (auto it = _smartSwitchKeyData.begin(); it != _smartSwitchKeyData.end(); ++it) {
        outData.push_back((Byte)it->first.length());
        for (size_t j = 0; j < it->first.length(); j++) {
            outData.push_back(it->first[j]);
        }
        outData.push_back(it->second);
    }
}

int getAppInputMethodStatus(const string& bundleId, const int& currentInputMethod) {
    if (_cacheKey.compare(bundleId) == 0) {
        return _cacheData;
    }
    const auto savedStatus = _smartSwitchKeyData.find(bundleId);
    if (savedStatus != _smartSwitchKeyData.end()) {
        _cacheKey = bundleId;
        _cacheData = savedStatus->second;
        return _cacheData;
    }
    _cacheKey = bundleId;
    _cacheData = currentInputMethod;
    _smartSwitchKeyData[bundleId] = _cacheData;
    return -1;
}

void setAppInputMethodStatus(const string& bundleId, const int& language) {
    _smartSwitchKeyData[bundleId] = language;
    _cacheKey = bundleId;
    _cacheData = language;
}
