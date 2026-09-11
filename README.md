# Sketchybar Daemon

A daemon to dynamically query Menubar Items of the frontmost Mac App.
For example to get modular and stylized access to those Menubar Items. (I have done it in my Spaces)

The application queries for the first Menu level once it gets a command from sketchybar.
(Those commands can be changed in the code itself, it is just a string).
It serializes the app information in a struct, that way it doesn't need to query for the app again.
That way you can press on the items inside to execute them or get their own children for the next level.

For a useful implementation example look at my sketchybar dotfiles and the spaces script [here](https://github.com/Danon329/sketchybarConf/blob/main/plugins/items/spaces.lua)

### Example
![App Name](/examples/beginning.png)

![First Level](/examples/first_level.png)

![Second Level](/examples/second_level.png)

Like you can see, it is fairly bare bones. It will be an ongoing project but you are still welcome to use it.

## Requirements

- [Sketchybar](https://github.com/felixkratz/sketchybar)
- CMAKE (Min Version: 3.20)
- git (quite helpful I hear)

## Important to know

- The application queries all items through Mac Accessibility, that means Mac will ask you for accessibility permissions before use
- Pull request, critique and suggestions are always welcome

## How to setup

Clone the repo:
```
git clone https://github.com/Danon329/sketchybar-daemon.git
```

Build it:
```
cmake -B build && cmake --build build

```

Add the following commands to sketchybarrc for it to autostart with sketchybar and reload as well:
```
pkill -f sketchybar_daemon
/path/to/sketchybar/daemon &
```
or if you use lua:
```
sbar.exec("pkill -f sketchybar_daemon", function()
    sbar.exec("/path/to/sketchybar/daemon &")
end)
```
That kills and starts the daemon, cleaning all maybe existing instances.

Last but not least:
```
sketchybar --reload
```
