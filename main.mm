#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <CoreFoundation/CoreFoundation.h>
#include <netdb.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>
#include <algorithm>
#include <cerrno>
#include <ios>
#include <iostream>
#include <stdexcept>
#include <string>
#include <system_error>
#include <vector>

extern "C" {
#include "sketchybar.h"
}

struct MenuBarItem {
    std::string title;
    AXUIElementRef itemRef{nullptr};
};

struct App {
    std::string name;
    std::string bundleId;
    pid_t pid;
    std::string currentSpaceIdx;

    AXUIElementRef appRef{nullptr};
    std::vector<MenuBarItem> items;

    AXUIElementRef menuBarRef{nullptr};
    AXUIElementRef currentParentRef{nullptr};

    void createPopup() {
        std::string command;
        std::string targetSpace = "space." + currentSpaceIdx;

        command += "--set popup.slot.back position=popup." + targetSpace + " ";

        for (int i = 1; i <= 20; i++) {
            int vectorIdx = i - 1;
            std::string slotName = "popup.slot." + std::to_string(i);

            if (vectorIdx < items.size()) {
                command += "--set " + slotName + " position=popup." + targetSpace + " label=\"" + items[vectorIdx].title + "\" drawing=on ";
            } else {
                command += "--set " + slotName + " drawing=off ";
            }
        }

        command += "--set " + targetSpace + " popup.drawing=on";

        sketchybar(command.data());
        std::cout << "sent command to sketchybar: " << command << std::endl;
    }

    void setPopupInvisible() const {
        std::string command = "--set space." + currentSpaceIdx + " popup.drawing=off";
        sketchybar(command.data());
    }

    void setBackButtonVisible() {
        std::string command = "--set popup.slot.back drawing=on";
        sketchybar(command.data());
    }

    void setBackButtonInvisible() {
        std::string command = "--set popup.slot.back drawing=off";
        sketchybar(command.data());
    }

    void clearItems() {
        for (int i = 0; i < items.size(); i++) {
            items[i].title = "";
            if (items[i].itemRef != nullptr) {
                CFRelease(items[i].itemRef);
            }
        }
    }

    void release() {
        clearItems();
        if (appRef) {
            CFRelease(appRef);
            appRef = nullptr;
        }

        if (currentParentRef && currentParentRef != menuBarRef) {
            CFRelease(currentParentRef);
            currentParentRef = nullptr;
        }

        if (menuBarRef) {
            CFRelease(menuBarRef);
            menuBarRef = nullptr;
        }

        name.clear();
        bundleId.clear();
        pid = -1;
        currentSpaceIdx = "";

        setBackButtonInvisible();
        setPopupInvisible();
    }

    ~App() {
        release();
    }
};

std::vector<MenuBarItem> getMenuChildren(AXUIElementRef parent) {
    std::vector<MenuBarItem> items;
    CFTypeRef childrenRef = nullptr;
    CFArrayRef childrenElements = nullptr;

    if (AXUIElementCopyAttributeValue(parent, kAXChildrenAttribute, &childrenRef) == kAXErrorSuccess) {
        if (CFGetTypeID(childrenRef) == CFArrayGetTypeID()) {
            childrenElements = (CFArrayRef)childrenRef;
        } else {
            CFRelease(childrenRef);
            std::cerr << "Didn't get an array on second level check for children" << std::endl;
            return {};
        }

        CFTypeRef roleRef = nullptr;
        if (CFArrayGetCount(childrenElements) <= 0) {
            CFRelease(childrenElements);
            std::cerr << "ChildrenArray array of 0 or less on query level 1" << std::endl;
            return {};
        }

        if (AXUIElementCopyAttributeValue((AXUIElementRef)CFArrayGetValueAtIndex(childrenElements, 0), kAXRoleAttribute, &roleRef) == kAXErrorSuccess) {
            CFStringRef childType = (CFStringRef)roleRef;

            if (CFStringCompare(childType, kAXMenuRole, 0) == kCFCompareEqualTo) {
                if (AXUIElementCopyAttributeValue((AXUIElementRef)CFArrayGetValueAtIndex(childrenElements, 0), kAXChildrenAttribute, &childrenRef) == kAXErrorSuccess) {
                    if (CFGetTypeID(childrenRef) == CFArrayGetTypeID()) {
                        CFRelease(childrenElements);
                        childrenElements = (CFArrayRef)childrenRef;
                    } else {
                        CFRelease(childType);
                        CFRelease(childrenRef);
                        CFRelease(childrenElements);
                        std::cerr << "Didn't get an array on second level query for children" << std::endl;
                        return {};
                    }
                } else {
                    CFRelease(childType);
                    CFRelease(childrenElements);
                    std::cerr << "Query 2 failed somehow" << std::endl;
                    return {};
                }
            }
            CFRelease(childType);
        }

        for (CFIndex i = 0; i < CFArrayGetCount(childrenElements); i++) {
            MenuBarItem item;
            AXUIElementRef itemRef = (AXUIElementRef)CFArrayGetValueAtIndex(childrenElements, i);
            CFTypeRef titleRef;

            if (AXUIElementCopyAttributeValue(itemRef, kAXTitleAttribute, &titleRef) == kAXErrorSuccess) {
                CFStringRef stringTitleRef = (CFStringRef)titleRef;
                CFIndex length = CFStringGetLength(stringTitleRef);
                CFIndex maxSize = CFStringGetMaximumSizeForEncoding(length, kCFStringEncodingUTF8) + 1;
                char* titleBuffer = new char[maxSize];

                if (CFStringGetCString(stringTitleRef, titleBuffer, maxSize, kCFStringEncodingUTF8)) {
                    item.title = titleBuffer;
                } else {
                    item.title = "nothing";
                }

                delete[] titleBuffer;
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

std::vector<MenuBarItem> getParentItems(AXUIElementRef& currentParentRef) {
    std::vector<MenuBarItem> items;
    bool isParentItem = false;

    CFTypeRef newParentRef = nullptr;
    CFTypeRef checkAttributeRef = nullptr;
    AXUIElementRef holdValue = currentParentRef;
    while (!isParentItem) {
        if (AXUIElementCopyAttributeValue(holdValue, kAXParentAttribute, &newParentRef) == kAXErrorSuccess) {
            if (holdValue != currentParentRef) {
                CFRelease(holdValue);
            }

            holdValue = (AXUIElementRef)newParentRef;

            if (AXUIElementCopyAttributeValue(holdValue, kAXRoleAttribute, &checkAttributeRef) == kAXErrorSuccess) {
                CFStringRef type = (CFStringRef)checkAttributeRef;
                if (CFStringCompare(type, kAXMenuItemRole, 0) == kCFCompareEqualTo ||
                    CFStringCompare(type, kAXMenuBarRole, 0) == kCFCompareEqualTo) {
                    CFRelease(type);
                    isParentItem = true;
                    break;
                }
                CFRelease(type);

            } else {
                CFRelease(holdValue);
                std::cerr << "Couldn't check parent type" << std::endl;
                return {};
            }
        } else {
            if (holdValue != currentParentRef) {
                CFRelease(holdValue);
            }
            std::cerr << "Couldn't get parent attribute" << std::endl;
            return {};
        }
    }

    if (currentParentRef) CFRelease(currentParentRef);

    currentParentRef = (AXUIElementRef)newParentRef;

    items = getMenuChildren(currentParentRef);

    return items;
}

bool press(AXUIElementRef element) {
    if (!element) return false;

    CFTypeRef childrenCheck;
    if (AXUIElementCopyAttributeValue(element, kAXChildrenAttribute, &childrenCheck) == kAXErrorSuccess) {
        CFArrayRef children = (CFArrayRef)childrenCheck;
        if (CFArrayGetCount(children) > 0) {
            CFRelease(children);
            return false;
        }

        CFRelease(children);
    }

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

void fifoCallback(CFFileDescriptorRef descRef, CFOptionFlags callbackTypes, void* info) {
    App* app = static_cast<App*>(info);
    int fd = CFFileDescriptorGetNativeDescriptor(descRef);

    char buffer[128] = {0};
    ssize_t bytesRead = read(fd, buffer, sizeof(buffer) - 1);

    if (bytesRead <= 0) {
        std::cerr << "bytesRead smaller 0" << std::endl;
        return;
    }

    buffer[bytesRead] = '\0';
    std::string event(buffer);

    event.erase(event.find_last_not_of(" \n\r\t") + 1);

    if (bytesRead > 0) {
        if (event.rfind("SPACE", 0) == 0) {
            app->release();
            NSRunningApplication* nsApp = [[NSWorkspace sharedWorkspace] frontmostApplication];

            if (nsApp != nullptr) {
                app->name = [[nsApp localizedName] UTF8String];
                app->bundleId = ([nsApp bundleIdentifier] != nil) ? [[nsApp bundleIdentifier] UTF8String] : "Empty";
                app->pid = [nsApp processIdentifier];

                std::string numString = event.substr(6);
                app->currentSpaceIdx = numString;

                if (app->pid > 0) {
                    app->appRef = AXUIElementCreateApplication(app->pid);
                    if (app->appRef == nullptr) {
                        std::cerr << "App Ref has nullptr, check permissions for possible solution" << std::endl;
                    }
                } else {
                    app->release();
                    return;
                }

                CFTypeRef menuBar;
                if (AXUIElementCopyAttributeValue(app->appRef, kAXMenuBarAttribute, &menuBar) == kAXErrorSuccess) {
                    app->menuBarRef = (AXUIElementRef)menuBar;
                    app->currentParentRef = app->menuBarRef;
                }

                app->items = getMenuChildren(app->currentParentRef);
                app->createPopup();
            }
        } else if (event.rfind("SLOT", 0) == 0) {
            std::string slot = event.substr(5);
            if (slot == "BACK") {
                // TODO: Check why we always return to first level
                if (app->currentParentRef == app->menuBarRef) {
                    std::cerr << "Back Button was not invisible" << std::endl;
                }
                app->clearItems();
                app->items = getParentItems(app->currentParentRef);

                if (CFEqual(app->currentParentRef, app->menuBarRef)) {
                    app->setBackButtonInvisible();
                }

                app->createPopup();
                return;
            }

            int vectorIdx{0};
            try {
                vectorIdx = std::stoi(slot) - 1;
            } catch (const std::invalid_argument& e) {
                std::cerr << "Invalid string parsed from slot, it is not a number" << std::endl;
                return;
            } catch (const std::out_of_range& e) {
                std::cerr << "Number out of bounds for current slot" << std::endl;
                return;
            }

            if (vectorIdx < 0 || vectorIdx >= app->items.size()) {
                std::cerr << "[STATE ERROR] SketchyBar requested slot " << slot
                          << " (" << vectorIdx << "), but items.size() is only "
                          << app->items.size() << std::endl;
                return;  // Log error and prevent crash
            }

            if (press(app->items[vectorIdx].itemRef)) {
                app->setPopupInvisible();
            } else {
                if (app->currentParentRef != app->menuBarRef) {
                    CFRelease(app->currentParentRef);
                }
                app->currentParentRef = app->items[vectorIdx].itemRef;
                CFRetain(app->currentParentRef);
                std::vector<MenuBarItem> nextChildren = getMenuChildren(app->currentParentRef);

                app->clearItems();
                app->items = nextChildren;
                app->setBackButtonVisible();
                app->createPopup();
            }
        }
    }

    CFFileDescriptorEnableCallBacks(descRef, kCFFileDescriptorReadCallBack);
}

int main(int argc, char** argv) {
    const char* pipePath = "/tmp/sketchybar_daemon.fifo";

    if (mkfifo(pipePath, 0666) == -1) {
        if (errno != EEXIST) {
            std::cerr << "Failed to create FIFO pipe" << std::endl;
        }
    }

    int dummyFd = open(pipePath, O_RDWR | O_NONBLOCK);
    if (dummyFd < 0) {
        std::cerr << "Failed to create dummy fd for writing" << std::endl;
        return -1;
    }

    int fd = open(pipePath, O_RDONLY);
    if (fd < 0) {
        std::cerr << "Failed to open FIFO for reading" << std::endl;
        return -1;
    }

    App app;

    CFFileDescriptorContext context = {0, &app, NULL, NULL, NULL};
    CFFileDescriptorRef fdRef = CFFileDescriptorCreate(kCFAllocatorDefault, fd, true, fifoCallback, &context);

    CFRunLoopSourceRef source = CFFileDescriptorCreateRunLoopSource(kCFAllocatorDefault, fdRef, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);

    CFFileDescriptorEnableCallBacks(fdRef, kCFFileDescriptorReadCallBack);

    CFRunLoopRun();

    return 0;
}
