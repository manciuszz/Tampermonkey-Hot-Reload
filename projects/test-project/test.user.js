(function() {
	
	class Example {
		constructor() {
			console.log("Goblins from mars!");
			let countdown = 10;
			let id = setInterval(function() {
				console.log("Still running!");
				if (countdown === 0)
					clearInterval(id);
				countdown--;
			}, 1000);
		}
	}
	
	new Example();
})();
