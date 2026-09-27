#import <ApplicationServices/ApplicationServices.h>
#import <CoreFoundation/CoreFoundation.h>
#include <sys/stat.h>

#include "App.h"

void fifoCallback(CFFileDescriptorRef descRef, CFOptionFlags callbackTypes, void* info) {
    App* app = static_cast<App*>(info);
    int fd = CFFileDescriptorGetNativeDescriptor(descRef);

    char buffer[128] = {0};
    ssize_t bytesRead = read(fd, buffer, sizeof(buffer) - 1);

    if (bytesRead <= 0) {
        std::cerr << "bytesRead smaller 0" << std::endl;
        CFFileDescriptorEnableCallBacks(descRef, kCFFileDescriptorReadCallBack);
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
                        CFFileDescriptorEnableCallBacks(descRef, kCFFileDescriptorReadCallBack);
                        return;
                    }
                } else {
                    app->release();
                    CFFileDescriptorEnableCallBacks(descRef, kCFFileDescriptorReadCallBack);
                    return;
                }

                CFTypeRef menuBar;
                if (AXUIElementCopyAttributeValue(app->appRef, kAXMenuBarAttribute, &menuBar) == kAXErrorSuccess) {
                    app->menuBarRef = (AXUIElementRef)menuBar;
                    app->currentParentRef = app->menuBarRef;
                }

                app->items = app->getMenuChildren();
                app->createPopup("toggle");
            }
        } else if (event.rfind("SLOT", 0) == 0) {
            std::string slot = event.substr(5);
            if (slot == "BACK") {
                // TODO: Check why we always return to first level
                if (app->currentParentRef == app->menuBarRef) {
                    std::cerr << "Back Button was not invisible" << std::endl;
                }
                app->clearItems();
                app->items = app->getParentItems();

                if (CFEqual(app->currentParentRef, app->menuBarRef)) {
                    app->setBackButtonInvisible();
                }

                app->createPopup("on");
                CFFileDescriptorEnableCallBacks(descRef, kCFFileDescriptorReadCallBack);
                return;
            }

            int vectorIdx{0};
            try {
                vectorIdx = std::stoi(slot) - 1;
            } catch (const std::invalid_argument& e) {
                std::cerr << "Invalid string parsed from slot, it is not a number" << std::endl;
                CFFileDescriptorEnableCallBacks(descRef, kCFFileDescriptorReadCallBack);
                return;
            } catch (const std::out_of_range& e) {
                std::cerr << "Number out of bounds for current slot" << std::endl;
                CFFileDescriptorEnableCallBacks(descRef, kCFFileDescriptorReadCallBack);
                return;
            }

            if (vectorIdx < 0 || vectorIdx >= app->items.size()) {
                std::cerr << "[STATE ERROR] SketchyBar requested slot " << slot
                          << " (" << vectorIdx << "), but items.size() is only "
                          << app->items.size() << std::endl;
                CFFileDescriptorEnableCallBacks(descRef, kCFFileDescriptorReadCallBack);
                return;
            }

            if (app->press(app->items[vectorIdx].itemRef)) {
                app->setPopupInvisible();
            } else {
                if (app->currentParentRef != app->menuBarRef) {
                    CFRelease(app->currentParentRef);
                }
                app->currentParentRef = app->items[vectorIdx].itemRef;
                CFRetain(app->currentParentRef);
                std::vector<MenuBarItem> nextChildren = app->getMenuChildren();

                app->clearItems();
                app->items = nextChildren;
                app->setBackButtonVisible();
                app->createPopup("on");
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
