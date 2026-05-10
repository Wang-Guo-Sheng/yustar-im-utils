#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#if defined(_WIN32)
#include <windows.h>
#define EXPORT __declspec(dllexport)
#else
#define EXPORT
#endif

// 填充修饰键释放
static int add_modifier_up(INPUT *inputs, int n) {
    WORD mods[] = {VK_CONTROL, VK_SHIFT, VK_MENU, VK_LWIN, VK_RWIN};
    for (int j = 0; j < 5; j++) {
        inputs[n].type = INPUT_KEYBOARD;
        inputs[n].ki.wVk = mods[j];
        inputs[n].ki.dwFlags = KEYEVENTF_KEYUP;
        inputs[n].ki.wScan = 0;
        inputs[n].ki.time = 0;
        inputs[n].ki.dwExtraInfo = 0;
        n++;
    }
    return n;
}

// 填充 BackSpace
static int add_backspaces(INPUT *inputs, int n, int count) {
    for (int i = 0; i < count; i++) {
        inputs[n].type = INPUT_KEYBOARD;
        inputs[n].ki.wVk = VK_BACK;
        inputs[n].ki.dwFlags = 0;
        inputs[n].ki.wScan = 0;
        inputs[n].ki.time = 0;
        inputs[n].ki.dwExtraInfo = 0;
        n++;
        
        inputs[n].type = INPUT_KEYBOARD;
        inputs[n].ki.wVk = VK_BACK;
        inputs[n].ki.dwFlags = KEYEVENTF_KEYUP;
        inputs[n].ki.wScan = 0;
        inputs[n].ki.time = 0;
        inputs[n].ki.dwExtraInfo = 0;
        n++;
    }
    return n;
}

// 填充 Unicode 文本
static int add_text(INPUT *inputs, int n, const wchar_t *wtext) {
    for (int i = 0; wtext[i] != L'\0'; i++) {
        inputs[n].type = INPUT_KEYBOARD;
        inputs[n].ki.wVk = 0;
        inputs[n].ki.wScan = wtext[i];
        inputs[n].ki.dwFlags = KEYEVENTF_UNICODE;
        inputs[n].ki.time = 0;
        inputs[n].ki.dwExtraInfo = 0;
        n++;
        
        inputs[n].type = INPUT_KEYBOARD;
        inputs[n].ki.wVk = 0;
        inputs[n].ki.wScan = wtext[i];
        inputs[n].ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP;
        inputs[n].ki.time = 0;
        inputs[n].ki.dwExtraInfo = 0;
        n++;
    }
    return n;
}

// Lua: replace(deleteCount, text)
static int l_replace(lua_State *L) {
    int deleteCount = luaL_checkinteger(L, 1);
    const char *text = luaL_checkstring(L, 2);
    
#if defined(_WIN32)
    if (deleteCount <= 0 && (!text || text[0] == '\0')) {
        return 0;
    }
    
    // UTF-8 to UTF-16
    int wlen = MultiByteToWideChar(CP_UTF8, 0, text, -1, NULL, 0);
    wchar_t *wtext = NULL;
    int textEvents = 0;
    
    if (wlen > 0) {
        wtext = (wchar_t*)malloc(wlen * sizeof(wchar_t));
        MultiByteToWideChar(CP_UTF8, 0, text, -1, wtext, wlen);
        textEvents = (wlen - 1) * 2;
    }
    
    // 5 modifier_up + deleteCount*2 backspaces + textEvents
    int totalEvents = 5 + (deleteCount * 2) + textEvents;
    INPUT *inputs = (INPUT*)calloc(totalEvents, sizeof(INPUT));
    
    int n = 0;
    n = add_modifier_up(inputs, n);
    n = add_backspaces(inputs, n, deleteCount);
    if (wtext) {
        n = add_text(inputs, n, wtext);
    }
    
    SendInput(n, inputs, sizeof(INPUT));
    
    free(wtext);
    free(inputs);
#endif
    
    return 0;
}

static const struct luaL_Reg mylib[] = {
    {"replace", l_replace},
    {NULL, NULL}
};

EXPORT int luaopen_replaceCommit(lua_State *L) {
    luaL_newlib(L, mylib);
    return 1;
}