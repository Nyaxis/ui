#ifndef RUNNER_UTILS_H_
#define RUNNER_UTILS_H_

#include <string>
#include <vector>

void CreateAndAttachConsole();

// returns an empty string on failure
std::string Utf8FromUtf16(const wchar_t* utf16_string);

// returns an empty vector on failure
std::vector<std::string> GetCommandLineArguments();

#endif  // RUNNER_UTILS_H_
