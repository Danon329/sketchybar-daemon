#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#include <iostream>
#include <stdexcept>
#include <string>
#include <system_error>
#include <vector>

struct MenuBarItem {
    std::string title;
    AXUIElementRef itemRef{nullptr};
};

struct App {
    std::string name;
    std::string bundleId;
    pid_t pid;

    AXUIElementRef appRef{nullptr};
    std::vector<MenuBarItem> items;

    AXUIElementRef menuBarRef{nullptr};

    void clearItems() {
        for (int i = 0; i < items.size(); i++) {
            if (items[i].itemRef != nullptr) {
                CFRelease(items[i].itemRef);
            }
        }
    }

    ~App() {
        CFRelease(appRef);
        CFRelease(menuBarRef);
        clearItems();
    }
};

std::vector<MenuBarItem> getMenuChildren(AXUIElementRef parent);
bool press(AXUIElementRef element);

int main() {
    App app;
    NSRunningApplication* nsApp = [[NSWorkspace sharedWorkspace] frontmostApplication];

    if (nsApp != nil) {
        app.name = [[nsApp localizedName] UTF8String];
        app.bundleId = ([nsApp bundleIdentifier] != nil) ? [[nsApp bundleIdentifier] UTF8String] : "Empty";
        app.pid = [nsApp processIdentifier];

        app.appRef = AXUIElementCreateApplication(app.pid);
        if (app.appRef == nullptr) {
            std::cerr << "App Ref has nullptr, check permissions for possible solution" << std::endl;
            return 1;
        }

        CFTypeRef menuBar;
        if (AXUIElementCopyAttributeValue(app.appRef, kAXMenuBarAttribute, &menuBar) == kAXErrorSuccess) {
            app.menuBarRef = (AXUIElementRef)menuBar;
        }
    }

    app.clearItems();
    app.items = getMenuChildren(app.menuBarRef);

    for (int i = 0; i < app.items.size(); i++) {
        std::cout << app.items[i].title << std::endl;
    }

    return 0;
}

std::vector<MenuBarItem> getMenuChildren(AXUIElementRef parent) {
    std::vector<MenuBarItem> items;
    CFTypeRef childrenRef = nullptr;
    CFArrayRef childrenElements = nullptr;

    if (AXUIElementCopyAttributeValue(parent, kAXChildrenAttribute, &childrenRef) == kAXErrorSuccess) {
        childrenElements = (CFArrayRef)childrenRef;

        for (CFIndex i = 0; i < CFArrayGetCount(childrenElements); i++) {
            MenuBarItem item;
            AXUIElementRef itemRef = (AXUIElementRef)CFArrayGetValueAtIndex(childrenElements, i);
            CFTypeRef titleRef;

            if (AXUIElementCopyAttributeValue(itemRef, kAXTitleAttribute, &titleRef) == kAXErrorSuccess) {
                CFStringRef stringTitleRef = (CFStringRef)titleRef;
                char titleBuffer[256] = {0};

                if (CFStringGetCString(stringTitleRef, titleBuffer, sizeof(titleBuffer), kCFStringEncodingUTF8)) {
                    item.title = titleBuffer;
                } else {
                    item.title = "nothing";
                }

                CFRelease(stringTitleRef);
            } else {
                item.title = "Error, couldn't get a title at all";
            }

            CFRetain(itemRef);
            item.itemRef = itemRef;

            items.push_back(item);
        }
        CFRelease(childrenElements);
    }
    return items;
}

bool press(AXUIElementRef element) {
    if (!element) return false;

    CFArrayRef possibleActions;
    if (AXUIElementCopyActionNames(element, &possibleActions) == kAXErrorSuccess) {
        CFIndex count = CFArrayGetCount(possibleActions);
        bool canPress = false;

        for (CFIndex i = 0; i < count; i++) {
            CFStringRef action = (CFStringRef)CFArrayGetValueAtIndex(possibleActions, i);
            if (CFStringCompare(action, kAXPressAction, 0) == kCFCompareEqualTo) {
                canPress = true;
                break;
            }
        }
        CFRelease(possibleActions);

        if (canPress) {
            AXError err = AXUIElementPerformAction(element, kAXPressAction);
            return (err == kAXErrorSuccess);
        }
    }

    return false;
}
