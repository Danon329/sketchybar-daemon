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
    NSRunningApplication* nsApp = [[NSWorkspace sharedWorkspace] frontmostApplication];

    if (nsApp != nil) {
        app.name = [[nsApp localizedName] UTF8String];
        app.bundleId =
            ([nsApp bundleIdentifier] != nil) ? [[nsApp bundleIdentifier] UTF8String] : "Empty";
        app.pid = [nsApp processIdentifier];

        app.appRef = AXUIElementCreateApplication(app.pid);
        if (app.appRef == nullptr) {
            std::cerr << "App Ref has nullptr, check permissions for possible solution"
                      << std::endl;
            return 1;
        }
    }

    // TODO: Look at logical roadmap of again, here is an error
    CFTypeRef menuBarRef;
    AXError err = AXUIElementCopyAttributeValue(app.appRef, kAXMenuBarAttribute, &menuBarRef);
    if (err == kAXErrorSuccess) {
        AXUIElementRef menuBarElementRef = (AXUIElementRef)menuBarRef;
        MenuBarItem item;
        item.itemRef = menuBarElementRef;
        app.items.push_back(item);
    }

    return 0;
}
