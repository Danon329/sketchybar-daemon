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

    void clearItems() {
        for (int i = 0; i < items.size(); i++) {
            CFRelease(items[i].itemRef);
        }
    }

    ~App() {
        CFRelease(appRef);
        clearItems();
    }
};

int main() {
    App app;
    NSRunningApplication* nsApp =
        [[NSWorkspace sharedWorkspace] frontmostApplication];

    if (nsApp != nil) {
        app.name = [[nsApp localizedName] UTF8String];
        app.bundleId = ([nsApp bundleIdentifier] != nil)
                           ? [[nsApp bundleIdentifier] UTF8String]
                           : "Empty";
        app.pid = [nsApp processIdentifier];

        app.appRef = AXUIElementCreateApplication(app.pid);
        if (app.appRef == nullptr) {
            std::cerr << "App Ref has nullptr, check permissions for possible solution" << std::endl;
            return 1;
        }
    }

    CFTypeRef menuBarRef;
    CFTypeRef childrenRef;

    AXUIElementRef menuBarElementRef;
    CFArrayRef childrenElements;

    if (AXUIElementCopyAttributeValue(app.appRef, kAXMenuBarAttribute, &menuBarRef) == kAXErrorSuccess) {
        menuBarElementRef = (AXUIElementRef)menuBarRef;

        if (AXUIElementCopyAttributeValue(menuBarElementRef, kAXChildrenAttribute, &childrenRef) == kAXErrorSuccess) {
            childrenElements = (CFArrayRef)childrenRef;

            for (int i = 0; i < CFArrayGetCount(childrenElements); i++) {
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
                }
                CFRetain(itemRef);
                item.itemRef = itemRef;

                app.items.push_back(item);
            }
            CFRelease(childrenElements);
        }
        CFRelease(menuBarElementRef);
    }

    for (int i = 0; i < app.items.size(); i++) {
        std::cout << app.items[i].title << std::endl;
    }

    return 0;
}
