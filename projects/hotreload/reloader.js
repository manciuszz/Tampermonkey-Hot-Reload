var hotreload = (function() {
	let hotreload = {
		name: "[Hot-Reload]",
		enableOverride: true,
		hotReloadServer: 'http://localhost:9999',
		get subscriptionEndpoint() { return this.hotReloadServer + '/events'; },
		get updateEndpoint() { return this.hotReloadServer + '/update'; },
		get importEndpoint() { return this.hotReloadServer + '/import'; },
	};

	let environmentOverrides = (function(enableOverride) {
		if (!enableOverride) return;

		(function(originalSetInterval, originalClearInterval) {
			let bindToWindowContext = function(windowCtx, oSetInterval, oClearInterval, setIntervalFnName = "setInterval", clearIntervalFnName = "clearInterval") {
				let intervals = [];
				windowCtx[setIntervalFnName] = function(handler, timeout, ...arguments) {
					let newInterval = oSetInterval(handler, timeout, ...arguments);
					intervals.push(newInterval);
					return newInterval;
				};

				windowCtx[clearIntervalFnName] = function(interval) {
					oClearInterval(interval);
					intervals.splice(intervals.indexOf(interval), 1)
				};
				
				window.clearAllIntervals = (function() {
					let originalClearAllIntervals = window.clearAllIntervals;
					
					let clearIntervals = function() {
						intervals.forEach(windowCtx[clearIntervalFnName]);
					};
					
					if (typeof originalClearAllIntervals === "function") {
						let clearIntervalsCopy = clearIntervals;
						clearIntervals = function() {
							originalClearAllIntervals();
							clearIntervalsCopy();
						};
					}
					
					return clearIntervals;
				})();
			};
			
			bindToWindowContext(window, originalSetInterval, originalClearInterval);
			
			if (typeof unsafeWindow !== "undefined") // Support for unsafeWindow from Tampermonkey
				bindToWindowContext(unsafeWindow, unsafeWindow.setInterval, unsafeWindow.clearInterval);
				
			if (typeof window.wwSetInterval !== "undefined") // Support for Web-Timers library -> https://github.com/ThePedestrian/Web-Timers
				bindToWindowContext(window, window.wwSetInterval, window.wwClearInterval, "wwSetInterval", "wwClearInterval");
			
		})(window.setInterval, window.clearInterval);
	})(hotreload.enableOverride);

	let codeExecutionEnvironment = function(codeToExecute) {
		try {
			console.log(`${hotreload.name} RELOADING...`);
			window.clearAllIntervals();
			eval(codeToExecute);
		} catch (err) {
			console.log(`${hotreload.name}->codeExecutionEnvironment->ERROR\n`, err);
		}
	};

	let subscribeViaEvents = function() {
		let ctx = {
			name: "Hot-Reload Server",
			status: false
		};
		let evtSource = new EventSource(hotreload.subscriptionEndpoint);
		evtSource.addEventListener("reload", function(e) {
			let jsonData = JSON.parse(e.data);
			if (jsonData.script)
				codeExecutionEnvironment(jsonData.script);
		}, false);
		evtSource.onopen = function(evt) {
			ctx.status = true;
		};
		evtSource.onerror = function(evt) {
			if (!ctx.status) {
				console.log(`Failed to communicate with the ${ctx.name}.`);
			}
		};
	};
	
	// Alternative using 'fetch' API.
	let subscribeViaFetch = function() {
		fetch(hotreload.subscriptionEndpoint, {
			method: "GET",
		}).then(res => res.text())
			.then(res => {
				let jsonData = JSON.parse(res.substr(res.indexOf("{")));
				if (jsonData.script)
					codeExecutionEnvironment(jsonData.script);
				subscribeViaFetch();
			})
			.catch(err => console.log(`${hotreload.name}->subscribeViaFetch->ERROR\n`, err));
	};
	
	let bindFolder = function(scriptPath, filter = "", fileToReload = "") {		
		let postRequest = function(shouldUnbind = false) {
			fetch(hotreload.updateEndpoint, {
				method: "POST",
				body: JSON.stringify({ "path": scriptPath, "extFilter": filter, "unbind": shouldUnbind, "reloadFile": fileToReload })
			}).then(e => e.text())
				.then(response => {
					if (response == "OK")
						console.log(`${hotreload.name}->postRequest\n`, `Path ${scriptPath} is ${shouldUnbind ? "no longer " : ""}being monitored.`);
				})
				.catch(err => console.log(`${hotreload.name}->postRequest->ERROR\n`, err));
		};
		
		postRequest();
		return {
			unbind: function() { 
				postRequest(true);
				this.unbind = (() => {});
			}
		}
	};
	
	let importFiles = function(fileList, callbackFn) {
		if (typeof callbackFn !== "function")
			return console.log(`${hotreload.name}->importFiles->ERROR\n`, "callbackFn is missing...");
		
		return fetch(hotreload.importEndpoint, {
				method: "POST",
				body: JSON.stringify({ "fileList": fileList })
			}).then(e => e.json())
				.then(importedCode => {
					return callbackFn(importedCode);
				})
				.catch(err => console.log(`${hotreload.name}->importFiles->ERROR\n`, err));
	};
	
	if ("EventSource" in window)
		subscribeViaEvents();
	else if ("fetch" in window)
		subscribeViaFetch();
	
	return {
		bind: bindFolder,
		import: importFiles
	};
})();

if (typeof unsafeWindow !== "undefined")
	unsafeWindow.hotreload = hotreload;