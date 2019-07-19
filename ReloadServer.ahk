#NoEnv
#Persistent
#KeyHistory 0
#SingleInstance, force
SetBatchLines, -1

#include <AHKhttp>
#include <MimeTypes>
#include <JSON>
#include <WatchFolder>

server := new HttpServer()
server.LoadMimes(getMimeTypes())
server.SetPaths(Router.getPaths())
server.Serve(9999)
; Run % "http://localhost:" . server.port

class Router {
	static _ := Router := new Router()
	
	__Init() {
		this._initViews()
	}
	
	getPaths() {
		return this.paths
	}
	
	_initViews() {
	    this.paths := {}
		for methodName, value in this.Views {
			if (methodName != "__Class") {
				pathName := StrReplace(methodName, "__", "",, 1)
				pathName := StrReplace(pathName, "_", "/",, 1)
				pathName := StrReplace(pathName, "#", "/*")
				this.paths[pathName] := ObjBindMethod(this.Views, methodName)
			}				
		}
	}

	class Views {
		__404(ByRef req, ByRef res) {
			res.SetBodyText("404 - Page not found!")
			res.status := 200
		}
		
		 _asset#(ByRef req, ByRef res) {
			 res.SetBodyText(req.queries.path)
			 res.status := 200
		 }
		
		_update(ByRef req, ByRef res) {
			payload := JSON.Load(req.body)
			
			if (payload.unbind) {
				WatchHelper.unbindWatcher(payload.path)
			} else if (payload.extFilter) {
				WatchHelper.bindWatcher(payload.path, payload.extFilter)
			} else if (payload.path) {
				WatchHelper.bindWatcher(payload.path)
			} else {
				return this.__404(req, res)
			}
			
			res.headers["Access-Control-Allow-Origin"] := "*"
			res.SetBodyText("OK")
			res.status := 200
		}
		
		_events(ByRef req, ByRef res) {
			res.headers["Connection"] := "keep-alive"

			changedScriptPath := DataStream.getRaw()
			if (!changedScriptPath)
				return

			res.headers["Access-Control-Allow-Origin"] := "*"
			res.headers["Content-Type"] := "text/event-stream"
			res.headers["Cache-Control"] := "no-cache"

			res.SetBodyText(DataStream.clear().retry(1).event("reload").setJSON(JSON.Dump(Utilities.FileRead(changedScriptPath, false))).build())
			res.status := 200
			DataStream.clear()
		}
	}
}

class DataStream {
	static _ := DataStream = new DataStream()
	
	__New() {
      	this.clearLog()
		this.clear()
	}
	
	clear() {			
		this.data := ""
		this.rawData := ""
		return this
	}
	
	clearLog() {
		this.dataLog := ""
		return this
	}

	get() {
		return this.data
	}
	
	getRaw() {
		return this.rawData
	}
	
	getLog() {
		return this.dataLog
	}
	
	setLog(newData) {
		this.dataLog .= "<p>" . newData . "</p>"
	}
	
	storeData(newData) {
		this.rawData := newData
		this.setLog(newData)
		return this
	}
	
	set(newData, shouldStore := true) {		
		if (shouldStore)
			this.storeData(newData)
		this.data .= this.streamCommand("data", newData)
		return this
	}
	
	setJSON(newData) {
		this.data .= this.streamCommand("data", "{ ""script"": " . newData . " }")
		return this
	}
	
	retry(timeMS := 1) {
		this.data .= this.streamCommand("retry", timeMS)
		return this
	}
	
	event(id) {
		this.data .= this.streamCommand("event", id)
		return this
	}
	
	includes(str) {
		return InStr(this.data, str)
	}
	
	streamCommand(key, value) {
		return key . ": " . value . "`n"
	}
	
	build() {
		this.data .= "`n"
		return this.get()
	}
}

class Utilities {
	FileRead(path, checkRelative := true) {
		FileRead, output, % (checkRelative ? this.RelativePath(path) : path)
		return output
	}

	RelativePath(path) {
		return A_ScriptDir . path
	}
	
	Cache(key, value, shouldCache := false, forceOverwrite := false) { ; Enables RAM type caching strategy.
		static @cache := {}
		
		if (IsObject(value) && (!shouldCache || !@cache[key]))
			value := value.Call()
				
		if (!shouldCache)
			return value
		
		if (!@cache[key] || forceOverwrite)
			@cache[key] := value

		return @cache[key]
	}
	
	Join(Array, Sep) {
		for k, v in Array
			out .= Sep . v
		return SubStr(Out, 1+StrLen(Sep))
	}
	
	FilePathToDirectory(path) {
		pathToArray := StrSplit(path, "\")
		filePath := pathToArray.Pop()
		if (InStr(filePath, "."))
			return this.Join(pathToArray, "\")
		return path
	}
}

class WatchHelper {
	static _ := WatchHelper := new WatchHelper()
	__New() {
		this.delimiter := "|"
		this.watchFlag := 0x3 ; Watch for file modifications.
		this.checkSubtree := true
		this.filters := {}
		this.bindWatcher(A_ScriptDir . "\projects")
	}
	
	bindWatcher(path, extFilter := "user.js") {
		this.setExtension(path, extFilter)
		WatchFolder(path, this._detectProjectChanges.name, this.checkSubtree, this.watchFlag)
	}
	
	unbindWatcher(path) {
		WatchFolder(path, "**DEL")
	}
	
	getExtensions(path := "") {
		if (!path)
			return this.filters
		return this.filters[path]
	}
	
	getExtensionCount(path := "") {
		return NumGet(&(this.getExtensions(path)) + 4 * A_PtrSize)
	}
	
	setExtension(path, extFilter) {
		this.filters[path] := {}
			
		if (extFilter) {
			extFilters := StrSplit(extFilter, this.delimiter)
			for i, filter in extFilters
				this.filters[path][filter] := filter
		}
	}

	_pathCleaner(path) {
	    path := StrReplace(path, "___jb_tmp___", "",, 1) ; Intellij IDEA postfix cleanup..
	    path := StrReplace(path, "___jb_old___", "",, 1) ; Intellij IDEA postfix cleanup..
	    return path
	}
	
	_detectProjectChanges(Folder, Changes) {
		static callCount = 0
		if (callCount := (Mod(++callCount, 2) >= 1))
			return
			
		if (!this.base)
			this.base := WatchHelper

		if (this.getExtensionCount(Folder)) {
			for idx, change in Changes {
				FullPath := change.Name
				SplitPath, FullPath, FileName
				for k, ext in this.getExtensions(Folder) {
					if (InStr(FileName, ext)) {
						DataStream.set(this._pathCleaner(FullPath))
						PersistenceController.notifyHandlers()
						return
					}	
				}				
			}
		}		
	}
}

; Hotkeys
#If WinActive("ahk_exe notepad++.exe")
^R::Reload
#If WinActive("ahk_exe idea64.exe")
+^R::Reload