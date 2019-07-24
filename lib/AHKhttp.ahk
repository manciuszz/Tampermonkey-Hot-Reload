#include %A_ScriptDir%\lib\AHKsock.ahk

class Uri
{
    Decode(str) {
        Loop
            If RegExMatch(str, "i)(?<=%)[\da-f]{1,2}", hex)
                StringReplace, str, str, `%%hex%, % Chr("0x" . hex), All
            Else Break
        Return, str
    }

    Encode(str) {
        f = %A_FormatInteger%
        SetFormat, Integer, Hex
        If RegExMatch(str, "^\w+:/{0,2}", pr)
            StringTrimLeft, str, str, StrLen(pr)
        StringReplace, str, str, `%, `%25, All
        Loop
            If RegExMatch(str, "i)[^\w\.~%]", char)
                StringReplace, str, str, %char%, % "%" . Asc(char), All
            Else Break
        SetFormat, Integer, %f%
        Return, pr . str
    }
}

class HttpServer
{
    static servers := {}

    LoadMimes(file) {
		isPath := InStr(file, ":")
        if (isPath && !FileExist(file))
            return false

		if (isPath)
			FileRead, data, % file
		else
			data := file
		
        types := StrSplit(data, "`n")
        this.mimes := {}
        for i, data in types {
            info := StrSplit(data, " ")
            type := info.Remove(1)
            ; Seperates type of content and file types
            info := StrSplit(LTrim(SubStr(data, StrLen(type) + 1)), " ")

            for i, ext in info {
                this.mimes[ext] := type
            }
        }
        return true
    }

    GetMimeType(file) {
        default := "text/plain"
        if (!this.mimes)
            return default

        SplitPath, file,,, ext
        type := this.mimes[ext]
        if (!type)
            return default
        return type
    }

    ServeFile(ByRef response, file) {
        f := FileOpen(file, "r")
        length := f.RawRead(data, f.Length)
        f.Close()
		
		if (!IsObject(f))
			return response.headers["Content-Type"] := ""

        response.SetBody(data, length)
        response.headers["Content-Type"] := this.GetMimeType(file)
    }

    SetPaths(paths) {
        this.paths := paths
    }

    Handle(ByRef request) {
        response := new HttpResponse()
				
		restData := StrSplit(RegExReplace(request.path, "^(\/\w+\/)(.*)", "$1*|/$2"), "|")
		if (restData.MaxIndex() > 1)
			greedyPath := restData.1 
	
        if (!this.paths[request.path] && !this.paths[greedyPath]) {
            func := this.paths["404"]
            response.status := 404
            if (func)
                func.(request, response, this)
            return response
        } else if (this.paths[request.path]) {
			this.paths[request.path].(request, response, this)
		} else if (this.paths[greedyPath]) {
			request.queries.path := restData.2
			this.paths[greedyPath].(request, response, this)
        }
        return response
    }

    Serve(port) {
        this.port := port
        HttpServer.servers[port] := this

        AHKsock_Listen(port, "HttpHandler")
		AHKsock_ErrorHandler(ObjBindMethod(Debug, "ErrorHandler"))
    }
	
}

class Debug {
	static _windowName := "AHK-Http Print Debug"
	static _width := 300
	static _height := 900
	static _x := A_ScreenWidth - A_ScreenWidth / 3
	static _y := 0
	
	setWindowSize(newWidth := "", newHeight := "", newX := "", newY := "", newName := "") {
		if (newWidth)
			this._width := newWidth
		if (newHeight)
			this._height := newHeight
		if (newX)
			this._x := newX
		if (newY)
			this._y := newY
		if (newName)
			this._windowName := newName
		return this
	}

	print(msg := "", shouldClean := false) {
		static log := "", printedLineCount := 0
		if (shouldClean || printedLineCount > 45) {
			log := ""
			printedLineCount := 0
		}
		log .= msg . "`n"
		printedLineCount++
		
		SplashTextOn, % this._width, % this._height, % this._windowName, % log
		WinMove, % this._windowName, , % this._x, % this._y
		return { clean: ObjBindMethod(this, "print", msg, true) }
	}

	ErrorHandler(iError, iSocket) {
		error := "Error " iError " with error code = " ErrorLevel ((iSocket <> -1) ? " on socket " iSocket "." : ".") 
		this.print("[ErrorHandler] " . error)
	}
}

class PersistenceController {
	static _handlers := {}

	deleteHandler(socketId) {
		if (!this._handlers[socketId])
			return

		OnMessage(this._handlers[socketId].id, this._handlers[socketId].handler, 0)
		this._handlers.Delete(socketId)
	}

	setHandler(socketId := 0, identifierTag := "", params*) {	
		if (!params) 
			return Debug.print("[PersistenceController] -> setHandler FAIL")
						
		this._handlers[socketId] := { id: "0x9" . socketId, identifier: identifierTag, handler: ObjBindMethod(this, "_persistenceHandler", params*) } 
		OnMessage(this._handlers[socketId].id, this._handlers[socketId].handler, 1)
	}
	
	socketIsPersistent(socketId) {
		return !!this._handlers[socketId]
	}
	
	notifyHandlers() {
		for socketId, handler in this._handlers
			if (handler.identifier)
				this._notifyHandler(handler.id)
	}
	
	_notifyHandler(handlerId) {
		lastState := A_DetectHiddenWindows
		DetectHiddenWindows, On
		PostMessage, %handlerId%, 0, 0,, ahk_id %A_ScriptHwnd%
		DetectHiddenWindows, %lastState%
	}
	
	_persistenceHandler(socket, request, server, wParam, lParam, msg) {		
		response := server.Handle(request)
		if (response.status) {
			socket.SetData(response.Generate())
			if (socket.TrySend()) {
				socket.Close()
			}
		}
	}
}

HttpHandler(sEvent, iSocket = 0, sName = 0, sAddr = 0, sPort = 0, ByRef bData = 0, bDataLength = 0) {
	static lastSocket, sockets := {}

	; Debug.print((!sockets[iSocket] ? "N" : "") . " " . iSocket . " " . sEvent)
    if (!sockets[iSocket]) {
        sockets[iSocket] := new Socket(iSocket)
        AHKsock_SockOpt(iSocket, "SO_KEEPALIVE", true)
    }

	socket := sockets[iSocket]

    if (sEvent == "DISCONNECTED") {
		socket.request := ""
        sockets.Delete(iSocket)
		PersistenceController.deleteHandler(iSocket)
	} else if (sEvent == "SEND") { ; if (sEvent == "SEND" || sEvent == "SENDLAST") {
		if (!PersistenceController.socketIsPersistent(lastSocket) && socket.TrySend()) {
			socket.Close()
        }
		lastSocket := iSocket
    } else if (sEvent == "RECEIVED") {
        server := HttpServer.servers[sPort]

        text := StrGet(&bData, "UTF-8")

		; New request or old?
        if (socket.request) {
			; Get data and append it to the existing request body
			socket.request.bytesLeft -= StrLen(text)
			socket.request.body := socket.request.body . text
            request := socket.request
        } else {
            ; Parse new request
            request := new HttpRequest(text)

            length := request.headers["Content-Length"]
            request.bytesLeft := length + 0

            if (request.body) {
                request.bytesLeft -= StrLen(request.body)
            }
        }

        if (request.bytesLeft <= 0) {
            request.done := true
        } else {
            socket.request := request
        }
		
        if (request.done || request.IsMultipart()) {
            response := server.Handle(request)
            if (response.status) {
                socket.SetData(response.Generate())
            }
        }
		
		if (response.headers["Connection"] == "keep-alive") {
			PersistenceController.setHandler(iSocket, "NOTIFY", socket, request, server)
			return
		}
				
        if (socket.TrySend()) { 
            if (!request.IsMultipart() || request.done) {
                socket.Close()
            }
        } 	
    }
}

class HttpRequest
{
    __New(data = "") {
        if (data)
            this.Parse(data)
    }

    GetPathInfo(top) {
        results := []
        while (pos := InStr(top, " ")) {
            results.Insert(SubStr(top, 1, pos - 1))
            top := SubStr(top, pos + 1)
        }
        this.method := results[1]
        this.path := Uri.Decode(results[2])
        this.protocol := top
    }

    GetQuery() {
        pos := InStr(this.path, "?")
        query := StrSplit(SubStr(this.path, pos + 1), "&")
        if (pos)
            this.path := SubStr(this.path, 1, pos - 1)

        this.queries := {}
        for i, value in query {
            pos := InStr(value, "=")
            key := SubStr(value, 1, pos - 1)
            val := SubStr(value, pos + 1)
            this.queries[key] := val
        }
    }

    Parse(data) {
        this.raw := data
        data := StrSplit(data, "`n`r")
        headers := StrSplit(data[1], "`n")
        this.body := LTrim(data[2], "`n")

        this.GetPathInfo(headers.Remove(1))
        this.GetQuery()
        this.headers := {}

        for i, line in headers {
            pos := InStr(line, ":")
            key := SubStr(line, 1, pos - 1)
            val := Trim(SubStr(line, pos + 1), "`n`r ")
            this.headers[key] := val
        }
    }

    IsMultipart() {
        length := this.headers["Content-Length"]
        expect := this.headers["Expect"]

        if (expect = "100-continue" && length > 0)
            return true
        return false
    }
}

class HttpResponse
{
    __New() {
        this.headers := {}
        this.status := 0
        this.protocol := "HTTP/1.1"

        this.SetBodyText("")
    }

    Generate() {
        FormatTime, date,, ddd, d MMM yyyy HH:mm:ss
        this.headers["Date"] := date

        headers := this.protocol . " " . this.status . "`r`n"
        for key, value in this.headers {
            headers := headers . key . ": " . value . "`r`n"
        }
        headers := headers . "`r`n"
        length := this.headers["Content-Length"]

        buffer := new Buffer((StrLen(headers) * 2) + length)
        buffer.WriteStr(headers)

        buffer.Append(this.body)
        buffer.Done()

        return buffer
    }

    SetBody(ByRef body, length) {
        this.body := new Buffer(length)
        this.body.Write(&body, length)
        this.headers["Content-Length"] := length
    }

    SetBodyText(text) {
        this.body := Buffer.FromString(text)
        this.headers["Content-Length"] := this.body.length
    }

}

class Socket
{
    __New(socket) {
        this.socket := socket
    }

    Close(timeout = 5000) {
        AHKsock_Close(this.socket, timeout)
    }

    SetData(data) {
        this.data := data
    }

    TrySend() {
        if (!this.data || this.data == "")
            return false

        p := this.data.GetPointer()
        length := this.data.length

        this.dataSent := 0
        Loop {
            if ((i := AHKsock_Send(this.socket, p, length - this.dataSent)) < 0) {
				; Debug.print("Try Send" . " " . i)
                if (i == -2) { ;if (i == -2 || i == -5) {
                    return
                } else {
                    ; Failed to send
                    return
                }
            }

            if (i < length - this.dataSent) {
                this.dataSent += i
            } else {
                break
            }
        }
        this.dataSent := 0
        this.data := ""

        return true
    }
}

class Buffer
{
    __New(len) {
        this.SetCapacity("buffer", len)
        this.length := 0
    }

    FromString(str, encoding = "UTF-8") {
        length := Buffer.GetStrSize(str, encoding)
        buffer := new Buffer(length)
        buffer.WriteStr(str)
        return buffer
    }

    GetStrSize(str, encoding = "UTF-8") {
        encodingSize := ((encoding="utf-16" || encoding="cp1200") ? 2 : 1)
        ; length of string, minus null char
        return StrPut(str, encoding) * encodingSize - encodingSize
    }

    WriteStr(str, encoding = "UTF-8") {
        length := this.GetStrSize(str, encoding)
        VarSetCapacity(text, length)
        StrPut(str, &text, encoding)

        this.Write(&text, length)
        return length
    }

    ; data is a pointer to the data
    Write(data, length) {
        p := this.GetPointer()
        DllCall("RtlMoveMemory", "uint", p + this.length, "uint", data, "uint", length)
        this.length += length
    }

    Append(ByRef buffer) {
        destP := this.GetPointer()
        sourceP := buffer.GetPointer()

        DllCall("RtlMoveMemory", "uint", destP + this.length, "uint", sourceP, "uint", buffer.length)
        this.length += buffer.length
    }

    GetPointer() {
        return this.GetAddress("buffer")
    }

    Done() {
        this.SetCapacity("buffer", this.length)
    }
}
