#include <algorithm>
#include <cassert>
#include <cctype>
#include <chrono>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <map>
#include <set>
#include <string>
#include <vector>

#include "../Sources/src-tauri/engine/Engine.h"
#include "../Sources/src-tauri/engine/EnglishFSM.h"
#include "../Sources/src-tauri/engine/ProgrammingFSM.h"

int vLanguage = 1;
int vInputType = 0;
int vFreeMark = 0;
int vCodeTable = 0;
int vSwitchKeyStatus = 0;
int vCheckSpelling = 1;
int vUseModernOrthography = 1;
int vQuickTelex = 0;
int vRestoreIfWrongSpelling = 1;
int vUseEnglishDictionary = 0;
int vFixRecommendBrowser = 0;
int vUseMacro = 0;
int vUseMacroInEnglishMode = 0;
int vAutoCapsMacro = 0;
int vUseSmartSwitchKey = 0;
int vUpperCaseFirstChar = 0;
int vAllowConsonantZFWJ = 0;
int vQuickStartConsonant = 0;
int vQuickEndConsonant = 0;
int vRememberCode = 0;
int vOtherLanguage = 0;
int vTempOffVNKey = 0;
int vCheckProgrammingKeywords = 0;
int vFsmPriorityOrder[3] = {0, 1, 2};
int vTelexWAsU = 1;
int vTelexBracketAsO = 1;

namespace {

struct TelexChar {
  std::string body;
  char tone;
};

struct Result {
  size_t uniqueFailed = 0;
  size_t failedOccurrences = 0;
  size_t falseRestores = 0;
  std::vector<std::string> examples;
};

struct LatencySummary {
  long long medianNs = 0;
  long long p95Ns = 0;
  long long p99Ns = 0;
  long long maxNs = 0;
};

LatencySummary summarizeLatency(std::vector<long long> samples) {
  if (samples.empty())
    return {};
  std::sort(samples.begin(), samples.end());
  const auto atPercentile = [&samples](double percentile) {
    const size_t index = std::min(
        samples.size() - 1,
        static_cast<size_t>(percentile * static_cast<double>(samples.size() - 1)));
    return samples[index];
  };
  return {atPercentile(0.50), atPercentile(0.95), atPercentile(0.99),
          samples.back()};
}

std::vector<uint32_t> decodeUtf8(const std::string &text) {
  std::vector<uint32_t> result;
  for (size_t i = 0; i < text.size();) {
    const unsigned char c = text[i];
    if (c < 0x80) {
      result.push_back(c);
      ++i;
    } else if ((c & 0xE0) == 0xC0 && i + 1 < text.size()) {
      result.push_back(((c & 0x1F) << 6) | (text[i + 1] & 0x3F));
      i += 2;
    } else if ((c & 0xF0) == 0xE0 && i + 2 < text.size()) {
      result.push_back(((c & 0x0F) << 12) | ((text[i + 1] & 0x3F) << 6) |
                       (text[i + 2] & 0x3F));
      i += 3;
    } else {
      result.push_back(0xFFFD);
      ++i;
    }
  }
  return result;
}

std::string encodeUtf8(uint32_t cp) {
  std::string result;
  if (cp < 0x80) {
    result.push_back(static_cast<char>(cp));
  } else if (cp < 0x800) {
    result.push_back(static_cast<char>(0xC0 | (cp >> 6)));
    result.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
  } else {
    result.push_back(static_cast<char>(0xE0 | (cp >> 12)));
    result.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
    result.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
  }
  return result;
}

void addToneGroup(std::map<uint32_t, TelexChar> &table,
                  const std::string &characters, const std::string &body) {
  static const char tones[] = {0, 's', 'f', 'r', 'x', 'j'};
  const auto codepoints = decodeUtf8(characters);
  assert(codepoints.size() == 6);
  for (size_t i = 0; i < codepoints.size(); ++i) {
    table[codepoints[i]] = {body, tones[i]};
  }
}

const std::map<uint32_t, TelexChar> &telexTable() {
  static const std::map<uint32_t, TelexChar> table = [] {
    std::map<uint32_t, TelexChar> value;
    addToneGroup(value, "aáàảãạ", "a");
    addToneGroup(value, "ăắằẳẵặ", "aw");
    addToneGroup(value, "âấầẩẫậ", "aa");
    addToneGroup(value, "eéèẻẽẹ", "e");
    addToneGroup(value, "êếềểễệ", "ee");
    addToneGroup(value, "iíìỉĩị", "i");
    addToneGroup(value, "oóòỏõọ", "o");
    addToneGroup(value, "ôốồổỗộ", "oo");
    addToneGroup(value, "ơớờởỡợ", "ow");
    addToneGroup(value, "uúùủũụ", "u");
    addToneGroup(value, "ưứừửữự", "uw");
    addToneGroup(value, "yýỳỷỹỵ", "y");
    addToneGroup(value, "AÁÀẢÃẠ", "A");
    addToneGroup(value, "ĂẮẰẲẴẶ", "Aw");
    addToneGroup(value, "ÂẤẦẨẪẬ", "Aa");
    addToneGroup(value, "EÉÈẺẼẸ", "E");
    addToneGroup(value, "ÊẾỀỂỄỆ", "Ee");
    addToneGroup(value, "IÍÌỈĨỊ", "I");
    addToneGroup(value, "OÓÒỎÕỌ", "O");
    addToneGroup(value, "ÔỐỒỔỖỘ", "Oo");
    addToneGroup(value, "ƠỚỜỞỠỢ", "Ow");
    addToneGroup(value, "UÚÙỦŨỤ", "U");
    addToneGroup(value, "ƯỨỪỬỮỰ", "Uw");
    addToneGroup(value, "YÝỲỶỸỴ", "Y");
    value[0x0111] = {"dd", 0};
    value[0x0110] = {"Dd", 0};
    return value;
  }();
  return table;
}

bool isWordCharacter(uint32_t cp) {
  return std::isalnum(static_cast<unsigned char>(cp)) || cp == 0x0110 ||
         cp == 0x0111 || cp >= 0x00C0;
}

std::vector<std::string> words(const std::string &text) {
  std::vector<std::string> result;
  std::string current;
  for (uint32_t cp : decodeUtf8(text)) {
    if (isWordCharacter(cp)) {
      current += encodeUtf8(cp);
    } else if (!current.empty()) {
      result.push_back(current);
      current.clear();
    }
  }
  if (!current.empty())
    result.push_back(current);
  return result;
}

std::string toTelex(const std::string &word) {
  std::string body;
  char tone = 0;
  for (uint32_t cp : decodeUtf8(word)) {
    const auto found = telexTable().find(cp);
    if (found == telexTable().end()) {
      body += encodeUtf8(cp);
    } else {
      body += found->second.body;
      if (found->second.tone)
        tone = found->second.tone;
    }
  }
  if (tone)
    body.push_back(tone);
  return body;
}

uint32_t engineCodeToUnicode(Uint32 data) {
  if (data & PURE_CHARACTER_MASK)
    return data & 0xFFFF;
  if (data & CHAR_CODE_MASK)
    return data & 0xFFFF;
  return keyCodeToCharacter(data);
}

std::string simulateWord(const std::string &raw, bool restore,
                         bool useDictionary = false) {
  vRestoreIfWrongSpelling = restore ? 1 : 0;
  vUseEnglishDictionary = useDictionary ? 1 : 0;
  auto *state = static_cast<vKeyHookState *>(vKeyInit());
  std::vector<uint32_t> output;
  for (uint32_t cp : decodeUtf8(raw + " ")) {
    const auto key = _characterMap.find(cp);
    assert(key != _characterMap.end());
    const Uint32 keyData = key->second;
    vKeyHandleEvent(Keyboard, KeyDown, keyData & CHAR_MASK,
                    keyData & CAPS_MASK ? 1 : 0, false);
    if (state->code == vDoNothing) {
      output.push_back(cp);
      continue;
    }
    const size_t erase = std::min<size_t>(state->backspaceCount, output.size());
    output.resize(output.size() - erase);
    for (int i = state->newCharCount - 1; i >= 0; --i) {
      const uint32_t converted = engineCodeToUnicode(state->charData[i]);
      if (converted)
        output.push_back(converted);
    }
    if (state->code == vRestore || state->code == vRestoreAndStartNewSession) {
      output.push_back(cp);
    }
  }
  if (!output.empty() && output.back() == ' ')
    output.pop_back();
  std::string result;
  for (uint32_t cp : output)
    result += encodeUtf8(cp);
  return result;
}

std::string lowerAscii(std::string value) {
  for (char &character : value) {
    character =
        static_cast<char>(std::tolower(static_cast<unsigned char>(character)));
  }
  return value;
}

bool isAsciiWord(const std::string &value) {
  return std::all_of(value.begin(), value.end(), [](unsigned char character) {
    return std::isalpha(character) != 0;
  });
}

bool structuralEnglishHint(const std::string &raw) {
  if (!isAsciiWord(raw))
    return false;
  const std::string lower = lowerAscii(raw);
  if (lower.size() > 2 && lower.front() == 'w')
    return true;
  if (lower.find("ss") != std::string::npos ||
      lower.find("ff") != std::string::npos ||
      lower.find("rr") != std::string::npos ||
      lower.find("xx") != std::string::npos ||
      lower.find("jj") != std::string::npos) {
    return true;
  }
  bool sawLower = false;
  for (size_t i = 1; i < raw.size(); ++i) {
    sawLower = sawLower || std::islower(static_cast<unsigned char>(raw[i]));
    if (sawLower && std::isupper(static_cast<unsigned char>(raw[i])))
      return true;
  }
  return false;
}

std::string seedCorpus() {
  return "Sáng thứ Hai, nhóm phát triển họp nhanh để kiểm tra tiến độ dự án. "
         "Minh mở laptop, đọc email từ khách hàng và cập nhật deadline trên "
         "dashboard. "
         "Lan kiểm tra website, thử chức năng login, logout, search và upload "
         "file. "
         "Mọi người thống nhất rằng trải nghiệm gõ phải nhanh, đúng và ổn "
         "định, kể cả khi người dùng nhập tiếng Việt xen English. "
         "Trong buổi meeting, kỹ sư backend trình bày API mới, còn nhóm "
         "frontend kiểm tra button, modal, form, checkbox và dropdown. "
         "Một thành viên gửi link GitHub qua Slack, người khác mở Chrome để "
         "đọc documentation. "
         "Họ dùng JSON, HTTP, WebSocket và database nhưng vẫn ghi chú bằng "
         "tiếng Việt có đầy đủ dấu câu. "
         "Bản báo cáo cho biết khách hàng thường viết email, chat với support, "
         "đặt lịch online và sao chép nội dung từ Microsoft Word. "
         "Có người dùng macOS, Windows hoặc Linux; có người làm việc trong VS "
         "Code, Excel, Notion, Telegram và Google Docs. "
         "Bộ gõ không được làm sai các từ phổ biến như software, framework, "
         "password, network, browser hay download. "
         "Chiều nay, đội kiểm thử tạo một checklist gồm nhiều tình huống: gõ "
         "nhanh, gõ chậm, sửa bằng Backspace, viết HOA và đặt dấu sau phụ âm "
         "cuối. "
         "Các câu thử có những từ khó như Nguyễn, nghiêng, khuỷu, quẫy, "
         "chuyện, thưởng, khoảng, khuya, giường, tiếng, Việt, đường, quyền và "
         "trưởng. "
         "Người quản lý nhắc rằng benchmark chỉ phản ánh một phần chất lượng. "
         "Nếu độ trễ trung bình thấp nhưng thỉnh thoảng bị khựng, người dùng "
         "vẫn thấy khó chịu. "
         "Vì vậy báo cáo cần có median, P95, P99, số lần mất ký tự, số lần "
         "chèn sai và toàn bộ trường hợp output khác expected. "
         "Một lập trình viên nhập AI, API, CPU, GPU, WiFi, Bluetooth, iPhone, "
         "Android, Docker, Kubernetes, JavaScript, TypeScript, Python, Rust và "
         "Swift. "
         "Ở môi trường production, browser có thể render trang lớn trong khi "
         "antivirus quét file. "
         "Engine cần duy trì trạng thái chính xác, không nhân đôi ký tự và "
         "không nuốt Space, Enter hay Tab. "
         "Cuối ngày, cả nhóm review kết quả, tạo issue, thêm regression test "
         "và ghi rõ input, expected output, actual output trước khi sửa code. "
         "Những từ English bổ sung gồm software framework password network "
         "website search support workflow feedback dashboard deadline "
         "coffee free raw write wrong screen user test issue Docs Rust Swift "
         "WebSocket Windows Word download meeting Google Excel URL.";
}

std::vector<std::string> makeCorpus(size_t minimumWords) {
  const auto seed = words(seedCorpus());
  std::vector<std::string> corpus;
  corpus.reserve(minimumWords + seed.size());
  while (corpus.size() < minimumWords) {
    corpus.insert(corpus.end(), seed.begin(), seed.end());
  }
  corpus.resize(minimumWords);
  return corpus;
}

enum class Policy { EngineOnly, Structural, ProtectedLexicon };

bool shouldPreserveRaw(const std::string &raw, const std::string &actual,
                       Policy policy) {
  if (actual == raw)
    return false;
  if (policy == Policy::Structural)
    return structuralEnglishHint(raw);
  return false;
}

Result evaluate(const std::vector<std::string> &corpus, bool restore,
                Policy policy) {
  Result result;
  std::set<std::string> failedWords;
  for (const auto &expected : corpus) {
    const std::string raw = toTelex(expected);
    const bool useDictionary = policy == Policy::ProtectedLexicon;
    std::string actual = simulateWord(raw, restore, useDictionary);
    const bool preserveRaw = shouldPreserveRaw(raw, actual, policy);
    if (preserveRaw)
      actual = raw;
    if ((preserveRaw || useDictionary) && actual == raw && raw != expected) {
      ++result.falseRestores;
    }
    if (actual != expected) {
      ++result.failedOccurrences;
      if (failedWords.insert(expected).second && result.examples.size() < 12) {
        result.examples.push_back(expected + " <- " + raw + " -> " + actual);
      }
    }
  }
  result.uniqueFailed = failedWords.size();
  return result;
}

size_t countAmbiguousFalseRestores(Policy policy) {
  struct AmbiguousCase {
    const char *raw;
    const char *intendedVietnamese;
  };
  static const AmbiguousCase cases[] = {
      {"Docs", "Dóc"}, // English product name or Vietnamese name/syllable.
      {"raw", "ră"},   // English adjective or Telex w modifier.
      {"test", "tét"}  // English word or an early-position tone key.
  };

  size_t failures = 0;
  for (const auto &item : cases) {
    const bool useDictionary = policy == Policy::ProtectedLexicon;
    const std::string engineOutput =
        simulateWord(item.raw, useDictionary, useDictionary);
    std::string selected = engineOutput;
    if (shouldPreserveRaw(item.raw, engineOutput, policy))
      selected = item.raw;
    if (selected != item.intendedVietnamese) {
      ++failures;
      std::cout << "  ambiguity raw=" << item.raw
                << " vietnamese=" << item.intendedVietnamese
                << " selected=" << selected << '\n';
    }
  }
  return failures;
}

void printResult(const char *name, const Result &result) {
  std::cout << name << " unique_failed=" << result.uniqueFailed
            << " failed_occurrences=" << result.failedOccurrences
            << " false_restores=" << result.falseRestores << '\n';
  for (const auto &example : result.examples) {
    std::cout << "  " << example << '\n';
  }
}

void runLatencyBenchmark(const std::vector<std::string> &corpus) {
  std::vector<long long> lookupSamples;
  std::vector<long long> engineSamples;
  lookupSamples.reserve(corpus.size() * 10);
  engineSamples.reserve(corpus.size() * 10);

  size_t keyEvents = 0;
  size_t replacementEvents = 0;
  for (const auto &word : corpus) {
    auto *state = static_cast<vKeyHookState *>(vKeyInit());
    const std::string raw = toTelex(word) + " ";
    for (uint32_t cp : decodeUtf8(raw)) {
      const auto lookupStarted = std::chrono::steady_clock::now();
      const auto character = _characterMap.find(cp);
      const auto lookupFinished = std::chrono::steady_clock::now();
      if (character == _characterMap.end())
        continue;

      const Uint32 keyData = character->second;
      const auto engineStarted = std::chrono::steady_clock::now();
      vKeyHandleEvent(Keyboard, KeyDown, keyData & CHAR_MASK,
                      keyData & CAPS_MASK ? 1 : 0, false);
      const auto engineFinished = std::chrono::steady_clock::now();

      lookupSamples.push_back(
          std::chrono::duration_cast<std::chrono::nanoseconds>(
              lookupFinished - lookupStarted)
              .count());
      engineSamples.push_back(
          std::chrono::duration_cast<std::chrono::nanoseconds>(
              engineFinished - engineStarted)
              .count());
      ++keyEvents;
      if (state->code != vDoNothing)
        ++replacementEvents;
    }
  }

  const LatencySummary lookup = summarizeLatency(std::move(lookupSamples));
  const LatencySummary engine = summarizeLatency(std::move(engineSamples));
  std::cout << "latency_benchmark words=" << corpus.size()
            << " key_events=" << keyEvents
            << " replacement_events=" << replacementEvents << '\n';
  std::cout << "lookup_ns median=" << lookup.medianNs
            << " p95=" << lookup.p95Ns << " p99=" << lookup.p99Ns
            << " max=" << lookup.maxNs << '\n';
  std::cout << "engine_ns median=" << engine.medianNs
            << " p95=" << engine.p95Ns << " p99=" << engine.p99Ns
            << " max=" << engine.maxNs << '\n';
}

} // namespace

// ─────────────────────────────────────────────────────────────────────────────
// FSM Unit Tests
// ─────────────────────────────────────────────────────────────────────────────

struct FSMCase {
  const char *input;
  bool expected;  // true = should be accepted by FSM
};

int runEnglishFSMTests() {
  // Words that ARE valid English (FSM should return true)
  static const FSMCase shouldAccept[] = {
    // Common words
    {"hello", true}, {"world", true}, {"the", true}, {"screen", true},
    {"string", true}, {"write", true}, {"framework", true}, {"password", true},
    {"network", true}, {"software", true}, {"download", true}, {"browser", true},
    {"search", true}, {"login", true}, {"logout", true}, {"upload", true},
    {"coffee", true}, {"free", true}, {"wrong", true}, {"workflow", true},
    {"feedback", true}, {"dashboard", true}, {"deadline", true},
    // Letter clusters & phonotactics
    {"strength", true}, {"splash", true}, {"script", true}, {"spring", true},
    {"straight", true}, {"through", true}, {"throat", true},
    {"sphinx", true}, {"twist", true}, {"swift", true},
    // Tech words
    {"docker", true}, {"react", true}, {"python", true}, {"chrome", true},
    {"github", true}, {"server", true}, {"client", true}, {"backend", true},
    {"frontend", true}, {"database", true}, {"cluster", true},
  };

  // Sequences that are NOT valid English (FSM should return false)
  // These are sequences that Telex might produce that are not English
  static const FSMCase shouldReject[] = {
    // Invalid onsets/codas
    {"xkcd", false},    // multiple consecutive invalid consonants
    {"bgtf", false},    // random consonant cluster
    {"mxyzptlk", false},// no vowel run
    // Too many consecutive vowels
    {"aeiou", false},
    // Non-alpha chars inside
    {"ab3cd", false},
  };

  int passed = 0, failed = 0;
  for (const auto& c : shouldAccept) {
    bool result = vnkey::isValidEnglishWord(c.input);
    if (result == c.expected) {
      ++passed;
    } else {
      ++failed;
      std::cout << "  [FAIL] EnglishFSM accept  '" << c.input
                << "' expected=true got=false\n";
    }
  }
  for (const auto& c : shouldReject) {
    bool result = vnkey::isValidEnglishWord(c.input);
    if (result == c.expected) {
      ++passed;
    } else {
      ++failed;
      std::cout << "  [FAIL] EnglishFSM reject  '" << c.input
                << "' expected=false got=true\n";
    }
  }
  std::cout << "EnglishFSM  passed=" << passed << " failed=" << failed << "\n";
  return failed;
}

int runProgrammingFSMTests() {
  // Keywords and patterns that SHOULD be accepted
  static const FSMCase shouldAccept[] = {
    // Built-in keywords
    {"if", true}, {"else", true}, {"return", true}, {"const", true},
    {"function", true}, {"class", true}, {"interface", true}, {"struct", true},
    {"void", true}, {"int", true}, {"bool", true}, {"string", true},
    {"true", true}, {"false", true}, {"null", true}, {"undefined", true},
    {"async", true}, {"await", true}, {"import", true}, {"export", true},
    {"namespace", true}, {"package", true}, {"extends", true},
    {"try", true}, {"catch", true}, {"finally", true}, {"throw", true},
    // camelCase / PascalCase -> identifier clue
    {"getApp", true}, {"useState", true}, {"MyClass", true},
    {"buildSystem", true}, {"AppBuilder", true}, {"onKeyDown", true},
    // SCREAMING_SNAKE or ALL_CAPS acronym
    {"API", true}, {"URL", true}, {"JSON", true}, {"HTTP", true},
    {"SQL", true}, {"CPU", true}, {"GPU", true}, {"UUID", true},
    // snake_case
    {"my_var", true}, {"get_value", true}, {"MAX_SIZE", true},
    // letter-digit transition
    {"utf8", true}, {"sha256", true}, {"base64", true}, {"h264", true},
    // $ prefix (PHP-style)
    {"$this", true}, {"$scope", true},
    // Tech names (in built-in set)
    {"docker", true}, {"react", true}, {"svelte", true},
    {"mongodb", true}, {"redis", true}, {"nginx", true},
  };

  // Patterns that should NOT be accepted (plain lowercase words that could be Vietnamese)
  static const FSMCase shouldReject[] = {
    {"xin", false}, {"chao", false}, {"ban", false}, {"toi", false},
    {"abc", false}, {"xyz", false},   // short ambiguous
    {"hello", false},  // 'hello' is NOT in keyword set and no identifier clues
    {"world", false},
    {"test", false},   // no clues -> rejected by ProgrammingFSM
  };

  int passed = 0, failed = 0;
  for (const auto& c : shouldAccept) {
    bool result = vnkey::isValidProgrammingKeyword(c.input);
    if (result == c.expected) {
      ++passed;
    } else {
      ++failed;
      std::cout << "  [FAIL] ProgrammingFSM accept  '" << c.input
                << "' expected=true got=false\n";
    }
  }
  for (const auto& c : shouldReject) {
    bool result = vnkey::isValidProgrammingKeyword(c.input);
    if (result == c.expected) {
      ++passed;
    } else {
      ++failed;
      std::cout << "  [FAIL] ProgrammingFSM reject  '" << c.input
                << "' expected=false got=true\n";
    }
  }
  std::cout << "ProgrammingFSM  passed=" << passed << " failed=" << failed << "\n";
  return failed;
}

int main(int argc, char *argv[]) {
  if (argc > 1 && std::string(argv[1]) == "--interactive") {
    std::cout << "=== VNKey English Word Diagnostic Tool ===\n";
    
    // Try to load custom English dictionary if it exists
    const char* home = std::getenv("HOME");
    if (home != nullptr) {
      std::string path = std::string(home) + "/Library/Application Support/com.theodore.vnkey/english.txt";
      std::ifstream file(path);
      if (file.is_open()) {
        std::string content((std::istreambuf_iterator<char>(file)),
                             std::istreambuf_iterator<char>());
        extern void setCustomEnglishWords(const std::string& content);
        setCustomEnglishWords(content);
        std::cout << "Loaded custom English word list from: " << path << "\n\n";
      }
    }

    std::cout << "Enter a word or a sentence to diagnose Telex behavior (type 'exit' to quit):\n\n";
    std::string line;
    while (true) {
      std::cout << "> ";
      if (!std::getline(std::cin, line) || line == "exit") {
        break;
      }
      if (line.empty()) continue;

      const auto wordList = words(line);
      std::cout << "\nDiagnostic for: \"" << line << "\"\n";
      std::cout << "--------------------------------------------------\n";
      for (const auto &w : wordList) {
        const std::string raw = toTelex(w);
        const std::string baseline = simulateWord(raw, false, false);
        const std::string restore = simulateWord(raw, true, false);
        std::string structural = simulateWord(raw, true, false);
        const bool isStruct = structuralEnglishHint(raw);
        if (isStruct) {
          structural = raw;
        }
        const std::string lexicon = simulateWord(raw, true, true);
        const bool isProtected = isProtectedEnglishWord(w);

        std::cout << "Word: \"" << w << "\"\n";
        std::cout << "  - Telex Input:      \"" << raw << "\"\n";
        std::cout << "  - Baseline Output:  \"" << baseline << "\" (Without restore)\n";
        std::cout << "  - Auto-Restore:     \"" << restore << "\" (No dictionary)\n";
        std::cout << "  - Structural Rules: \"" << structural << "\" (" << (isStruct ? "Matched" : "No Match") << ")\n";
        std::cout << "  - Protected Dict:   \"" << lexicon << "\" (" << (isProtected ? "Protected" : "Not Protected") << ")\n\n";
      }
    }
    return 0;
  }

  // ── Run FSM unit tests first ────────────────────────────────────────────
  if (argc > 1 && std::string(argv[1]) == "--fsm") {
    std::cout << "=== FSM Unit Tests ===\n";
    int failures = 0;
    failures += runEnglishFSMTests();
    failures += runProgrammingFSMTests();
    std::cout << (failures == 0 ? "ALL FSM TESTS PASSED\n" : "SOME FSM TESTS FAILED\n");
    return failures > 0 ? 1 : 0;
  }

  const auto corpus = makeCorpus(10000);
  if (argc > 1 && std::string(argv[1]) == "--benchmark") {
    runLatencyBenchmark(corpus);
    return 0;
  }
  const auto started = std::chrono::steady_clock::now();

  // ── FSM unit tests ────────────────────────────────────────────────────────
  std::cout << "=== FSM Unit Tests ===\n";
  const int fsmFailures = runEnglishFSMTests() + runProgrammingFSMTests();
  std::cout << (fsmFailures == 0 ? "ALL FSM TESTS PASSED\n" : "SOME FSM TESTS FAILED\n") << "\n";

  // ── Corpus accuracy tests ─────────────────────────────────────────────────
  const Result baseline = evaluate(corpus, false, Policy::EngineOnly);
  const Result restore = evaluate(corpus, true, Policy::EngineOnly);
  const Result structural = evaluate(corpus, true, Policy::Structural);
  const Result lexicon = evaluate(corpus, true, Policy::ProtectedLexicon);

  const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                           std::chrono::steady_clock::now() - started)
                           .count();

  std::cout << "corpus_words=" << corpus.size() << " unique_words="
            << std::set<std::string>(corpus.begin(), corpus.end()).size()
            << " elapsed_ms=" << elapsed << '\n';
  printResult("baseline", baseline);
  printResult("restore", restore);
  printResult("structural", structural);
  printResult("protected_lexicon", lexicon);
  const size_t structuralAmbiguities =
      countAmbiguousFalseRestores(Policy::Structural);
  const size_t lexiconAmbiguities =
      countAmbiguousFalseRestores(Policy::ProtectedLexicon);
  std::cout << "structural_ambiguous_false_restores=" << structuralAmbiguities
            << '\n';
  std::cout << "lexicon_ambiguous_false_restores=" << lexiconAmbiguities
            << '\n';

  // ── Latency benchmark ─────────────────────────────────────────────────────
  std::cout << "\n=== Latency Benchmark ===\n";
  runLatencyBenchmark(corpus);

  if (fsmFailures > 0 ||
      corpus.size() != 10000 ||
      restore.failedOccurrences > baseline.failedOccurrences ||
      structural.falseRestores > 0 || lexicon.falseRestores > 0 ||
      lexicon.failedOccurrences > structural.failedOccurrences ||
      lexiconAmbiguities != 0) {
    return 1;
  }
  return 0;
}
