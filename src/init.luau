--!optimize 2
--!native
local task = task or require("@lute/task")

const tspawn = task.spawn
const NIL_TABLE = {}
const COLLECTOR_MINIMUM_CLEAN_SIZE = 16

local free_thread: thread? = nil

local function deleted_signal_err()
	error("Cannot operate on a deleted signal", 2)
end

const error_metatable = {
	__index = function()
		return deleted_signal_err
	end
}

const function yield_loop()
	while true do
		const sig: InternalIdentity<any>, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10 =
			coroutine.yield()

		const ref = free_thread
		free_thread = nil

		while sig._head ~= 0 do
			sig._head -= 1
			sig[sig._head + 1](arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10)
		end

		free_thread = ref
	end
end

const signal = {}
signal.__index = signal
type InternalIdentity<T...> = setmetatable<{
	_head: number,
	[number]: (T...) -> (),

	-- TODO: try this as a dynamic size ring buffer so that everything can be constant time
	read _collect_queue: { { unknown } },
	_collect_top: number,
	_collect_top_peaked: number,
	_dirty: boolean,

	read _collector_visited: { number },
	_collector_count: number,
}, typeof(signal)>

--[=[
	@class signal

	The main class for this package. It is actually just an array with a metatable! Constructed with:
	```lua
	local signal = require(...)

	signal()
	```
]=]
const function constructor<T...>(): InternalIdentity<T...>
	return setmetatable({
		_head = 0,

		_collect_queue = {} :: { {unknown} },
		_collect_top = 0,
		_collect_top_peaked = 0,
		_dirty = false,

		_collector_visited = {} :: { number },
		_collector_count = 0,
	}, signal)
end

--[=[
	@method connect
	@within signal

	Connects a function to the signal. This will be called whenever the signal is fired.
	Connections can be "disconnected" (they won't be called when the signal is fired) by calling the function that they return.
	```lua
	local sig = signal()

	-- You can connect a function like this
	sig:connect(function(text)
		print(text)
	end)

	-- You can also directly connect the function like this.
	sig:connect(print)

	-- Will print twice, because two connections.
	sig:fire("Hello, world!")
	```

	You shouldn't connect the same function twice. This is because the function is used as a reference to disconnect when disconnecting later.
	While it *might* work for simple or specialized cases, you may find that it doesn't work as expected in some cases.

	Connections will be ran in order of connection.

	It's also worth noting that disconnecting is not an optimal operation, as it will shift the array. If you have a lot of connections to a single signal, you should avoid frequent disconnections.

	@param callback (T) -> ()
	@return () -> ()
]=]
function signal.connect<T...>(self: InternalIdentity<T...>, callback: (T...) -> ())
	table.insert(self, callback)

	local function disconnecter()
		local index = table.find(self, callback)

		if index then
			table.remove(self, index)
		end
	end

	return disconnecter
end

--[=[
	@method fire
	@within signal

	Firing a signal will run all connections in order, while using thread reusage.
	[You can find more on this optimization here](https://devforum.roblox.com/t/thread-reuse-how-it-works-why-it-works/1999166).

	You should note these things about thread reusage:
	- You cannot rely on the thread being different, or the same consistently.
	- The above means that certain "no-yield" implementations might not work correctly in connections.
	- If you have a lot of connections, you should avoid yielding in said connections. Yielding forces a new thread to be spawned, which isn't optimal, but it's still okay.

	@param data ...
	@return void
]=]
function signal.fire<T...>(self: InternalIdentity<T...>, ...)
	self._head = #self
	while self._head ~= 0 do
		if not free_thread then
			free_thread = tspawn(yield_loop)
		end

		(tspawn :: any)(free_thread, self, ...)
	end

	const collector_count = self._collector_count
	if collector_count == 0 then
		return
	end
	const collect_queue = self._collect_queue

	local top = self._collect_top + 1
	collect_queue[top] = { ... }
	self._collect_top = top

	-- for a downshift to be considered, the size should be greater than the highest recorded post-cleanup size,
	if not self._dirty or top <= self._collect_top_peaked then
		return
	end
	self._dirty = false

	const collector_visited = self._collector_visited
	const downshift = math.min(table.unpack(collector_visited))

	if downshift > COLLECTOR_MINIMUM_CLEAN_SIZE then
		for key, value in collector_visited do
			collector_visited[key] = value - downshift
		end
		table.move(collect_queue, downshift + 1, top + downshift, 1, collect_queue)
		top -= downshift
		self._collect_top = top
	end

	if top > self._collect_top_peaked then
		self._collect_top_peaked = top
	end
end

--[=[
	@method once
	@within signal

	Connects to a signal, and disconnects after the first time it is fired.
	You can still disconnect the connection before it is fired.

	@param callback (T) -> ()
	@return () -> ()
]=]
function signal.once<T...>(self: InternalIdentity<T...>, callback: (T...) -> ())
	local disconnect
	disconnect = self:connect(function(...)
		assert(disconnect ~= nil, "Luau")
		disconnect()

		callback(...)
	end)
end

--[=[
	@method wait
	@within signal

	Yields the current thread until the signal is fired, and returns the arguments passed.
	Will raise an error if the thread is resumed before the signal is fired.

	@return T
]=]
function signal.wait<T...>(self: InternalIdentity<T...>): T...
	local running = coroutine.running()

	self:once(function(...)
		assert(
			coroutine.status(running) == "suspended",
			":wait() called, then another thread resumed the waiting thread. Please dont do that :("
		)

		tspawn(running, ...)
	end)

	return coroutine.yield()
end

function signal.collect<T...>(self: InternalIdentity<T...>)
	const collector_id = self._collector_count + 1
	self._collector_count = collector_id

	const collector_visited = self._collector_visited
	collector_visited[collector_id] = self._collect_top

	const collect_queue = self._collect_queue

	const function signal_collector_iter(): ...unknown
		const next_visit = collector_visited[collector_id] + 1
		const args = collect_queue[next_visit]
		if not args then
			return
		end
		collector_visited[collector_id] = next_visit
		self._dirty = true
		return table.unpack(args)
	end

	return signal_collector_iter
end

--[=[
	@method disconnectAll
	@within signal

	Disconnects all connections to the signal. This is very efficient.
	This will not empty any collector queues or disable collectors.
]=]
function signal.disconnect_all<T...>(self: InternalIdentity<T...>)
	table.move(NIL_TABLE, 1, #self, 1, self)
end

--[=[
	@method delete
	@within signal

	Disconnects all connections to the signal, clears all collector queues, and renders the signal object unusable.
	While this technically isn't required or needed for memory concerns, you might want to use this when you're working with others.

	This will prevent and raise an error upon any attempts to use the signal, which is useful for debugging & catching leaks.
]=]
function signal.delete<T...>(self: InternalIdentity<T...>): ()
	self:disconnect_all()

	table.clear(self._collect_queue)
	self._collect_top = 0

	setmetatable(self, error_metatable)
end

export type Identity<T...> = {
	fire: (self: Identity<T...>, T...) -> (),
	connect: (self: Identity<T...>, callback: (T...) -> ()) -> () -> (),
	once: (self: Identity<T...>, callback: (T...) -> ()) -> () -> (),
	wait: (self: Identity<T...>) -> T...,
	disconnect_all: (self: Identity<T...>) -> (),
	delete: (self: Identity<T...>) -> (),
	collect: (self: Identity<T...>) -> () -> T...,
}

return constructor :: <T...>() -> Identity<T...>
