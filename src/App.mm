#include "App.h"

// GC functionality
void App::clearItems() {
    for (int i = 0; i < items.size(); i++) {
        items[i].title = "";
        if (items[i].itemRef != nullptr) {
            CFRelease(items[i].itemRef);
        }
    }
}

void App::release() {
    this->clearItems();
    if (this->appRef) {
        CFRelease(this->appRef);
        this->appRef = nullptr;
    }

    if (this->currentParentRef && this->currentParentRef != this->menuBarRef) {
        CFRelease(this->currentParentRef);
        this->currentParentRef = nullptr;
    }

    if (this->menuBarRef) {
        CFRelease(this->menuBarRef);
        this->menuBarRef = nullptr;
    }

    this->name.clear();
    this->bundleId.clear();
    this->pid = -1;

    this->currentSpaceIdx.clear();

    this->setBackButtonInvisible();
    this->setPopupInvisible();
}

App::~App() {
    this->release();
}

// Getters
std::vector<MenuBarItem> App::getMenuChildren() {
    if (this->currentParentRef == nullptr) {
        std::cerr << "Error: Parentref unpopulated (getMenuChildren)" << std::endl;
    }

    std::vector<MenuBarItem> items;
    CFTypeRef childrenRef = nullptr;
    CFArrayRef childrenElements = nullptr;

    if (AXUIElementCopyAttributeValue(this->currentParentRef, kAXChildrenAttribute, &childrenRef) == kAXErrorSuccess) {
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

            if (item.title.size() > 0) {
                CFRetain(itemRef);
                item.itemRef = itemRef;

                items.push_back(item);
            }
        }
        CFRelease(childrenElements);
    }
    return items;
}

std::vector<MenuBarItem> App::getParentItems() {
    std::vector<MenuBarItem> items;
    bool isParentItem = false;

    CFTypeRef newParentRef = nullptr;
    CFTypeRef checkAttributeRef = nullptr;
    AXUIElementRef holdValue = this->currentParentRef;
    while (!isParentItem) {
        if (AXUIElementCopyAttributeValue(holdValue, kAXParentAttribute, &newParentRef) == kAXErrorSuccess) {
            if (holdValue != currentParentRef) {
                CFRelease(holdValue);
            }

            holdValue = (AXUIElementRef)newParentRef;

            if (AXUIElementCopyAttributeValue(holdValue, kAXRoleAttribute, &checkAttributeRef) == kAXErrorSuccess) {
                CFStringRef type = (CFStringRef)checkAttributeRef;
                if (CFStringCompare(type, kAXMenuRole, 0) == kCFCompareEqualTo ||
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

    items = getMenuChildren();

    return items;
}

bool App::elementHasChildren(AXUIElementRef element) {
    bool hasChildren = false;
    CFTypeRef childrenElements = nullptr;
    if (AXUIElementCopyAttributeValue(element, kAXChildrenAttribute, &childrenElements) == kAXErrorSuccess) {
        CFArrayRef children = (CFArrayRef)childrenElements;
        // Array might not be null but still pressable
        if (CFArrayGetCount(children) > 0) {
            hasChildren = true;
        }
    }
    CFRelease(childrenElements);

    return hasChildren;
}

// Press is press
bool App::press(AXUIElementRef element) {
    if (!element) return false;

    if (elementHasChildren(element)) return false;

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

void App::createPopup(std::string spacePopupCommand) {
    std::string command;
    std::string targetSpace = "space." + currentSpaceIdx;

    command += "--set popup.slot.back position=popup." + targetSpace + " ";

    // TODO: What if more then 20 --> create button next (and change back functionality for that)
    for (int i = 1; i <= 20; i++) {
        int vectorIdx = i - 1;
        std::string slotName = "popup.slot." + std::to_string(i);

        if (vectorIdx < items.size()) {
            if (elementHasChildren(items[vectorIdx].itemRef)) {
                command += "--set " + slotName +
                           " position=popup." + targetSpace +
                           " icon=\"" + items[vectorIdx].title + "\"" +
                           " label=\">\"" +
                           " drawing=on ";
            } else {
                command += "--set " + slotName +
                           " position=popup." + targetSpace +
                           " icon=\"" + items[vectorIdx].title + "\"" +
                           " label=\"\"" +
                           " drawing=on ";
            }
        } else {
            command += "--set " + slotName + " drawing=off ";
        }
    }

    command += "--set " + targetSpace + " popup.drawing=" + spacePopupCommand;

    sketchybar(command.data());
}

void App::setPopupInvisible() const {
    std::string command = "--set space." + currentSpaceIdx + " popup.drawing=off";
    sketchybar(command.data());
}

void App::setBackButtonVisible() const {
    std::string command = "--set popup.slot.back drawing=on";
    sketchybar(command.data());
}

void App::setBackButtonInvisible() const {
    std::string command = "--set popup.slot.back drawing=off";
    sketchybar(command.data());
}
