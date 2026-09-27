#pragma once

#import <AppKit/AppKit.h>
#include <iostream>
#include <string>
#include <vector>

extern "C" {
#include "sketchybar.h"
}

struct MenuBarItem {
public:
	std::string title;
	AXUIElementRef itemRef = nullptr;
};

class App {
public:
	// Generic App info (from NSWorkspace)
	std::string name;
	std::string bundleId;
	pid_t pid;

	// From Sketchybar
	std::string currentSpaceIdx;

	// App pointer plus the currently held children
	AXUIElementRef appRef = nullptr;
	std::vector<MenuBarItem> items;

	// Item pointers for upmost level and current parent level
	AXUIElementRef menuBarRef = nullptr;
	AXUIElementRef currentParentRef = nullptr;

	App() = default;

	// GC functionality
	void clearItems();
	void release();
	~App();

	// getters
	std::vector<MenuBarItem> getMenuChildren();
	std::vector<MenuBarItem> getParentItems();
	bool elementHasChildren(AXUIElementRef element);

	// execute
	bool press(AXUIElementRef element);

	// functions interacting with sketchybar
	void createPopup(std::string spacePopupCommand);
	void setPopupInvisible() const;
	void setBackButtonVisible() const;
	void setBackButtonInvisible() const;
};
