# Tampermonkey Hot-Reload Server
This is a tool to accelerate your [Tampermonkey](https://www.tampermonkey.net) user scripts development.

# How it works
It simply checks for specific file modifications inside designated folders (like "/projects" folder by default for example). Once the slightest change has been detected, the server will send the changed file source code to the client (i.e browser) via long-polling technique, which in turn will 'overwrite' the old code with the new one.

# Requirements
[AutoHotkey](https://www.autohotkey.com/download/), if your planning to launch the hot-reload server via *.ahk* file.

[Tampermonkey](https://www.tampermonkey.net) with permission to allow scripts to access local files.

![Instructions](https://i.imgur.com/VifFXC4.png)

Since this Hot-Reload currently works by taking advantage of HTTP long-polling technique, that means it has to adhere to [Content Security Policy (CSP)](https://developer.mozilla.org/en-US/docs/Web/HTTP/CSP) - in short, the website your writing the user scripts for has to allow HTTP requests **(lucky for us, most of them do)**.

# How to use
1. Launch the hot-reload server - *(ReloadServer.ahk or ReloadServer.exe)*.
2. Import the hot-reload client file inside your "Tampermonkey" script (via @require directive for example).
3. Enjoy.

# Preview
![Tutorial](https://giant.gfycat.com/AcceptableOnlyHamster.gif)

# API
Note, that there is also the possibility to watch for file changes in custom folders. 

You can do it by using the following API methods:

```javascript
// Bind 'D:\Another Script Folder\GameBot' folder to look for "user.js" and ".ahk" file changes.
let watchDog1 = hotreload.bind("D:\\Another Script Folder\\GameBot", "user.js|.ahk");

// Stop looking for 'watchDog1' changes.
watchDog1.unbind(); 
```

# [Download .exe version of the script from GitHub releases](https://github.com/manciuszz/Tampermonkey-Hot-Reload/releases/download/v0.1/hotreload.zip)