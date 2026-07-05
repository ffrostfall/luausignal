--!optimize 2
--!native
local task = task or require("@lute/task")

local tspawn = task.spawn
local NIL_TABLE = {}

local free_thread: thread? = nil

local function bitmask(idx: number)
	return 2 ^ idx
end

local function set_bit(int: number, mask: number): number
	return bit32.bor(int, mask)
end

local function get_bit(int: number, mask: number): boolean
	return bit32.band(int, mask) ~= 0
end

local function all_bits_set(bit_stack: number, mask: number): boolean
	return bit32.band(bit_stack, mask) == mask
end

local function deleted_signal_err()
	error("Cannot use a deleted signal", 2)
end

local error_tbl = {
	fire = deleted_signal_err,
	connect = deleted_signal_err,
	once = deleted_signal_err,
	wait = deleted_signal_err,
	disconnect_all = deleted_signal_err,
}

local function yield_loop()
	while true do
		local sig: InternalIdentity<any>, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10 =
			coroutine.yield()

		local ref = free_thread
		free_thread = nil

		while sig._head ~= 0 do
			sig._head -= 1
			sig[sig._head + 1](arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10)
		end

		free_thread = ref
	end
end

local signal = {}
signal.__index = signal
type InternalIdentity<T...> = setmetatable<{
	_head: number,
	_collect_queue: { { [number]: unknown, seen_by: number } },
	_collector_count: number,
	_collector_mask: number,
	[number]: (T...) -> (),
}, typeof(signal)>

--[=[
	@class signal
	
	The main class for this package. It is actually just an array with a metatable! Constructed with:
	```lua
	local signal = require(...)
	
	signal()
	```
]=]
local function constructor<T...>(): InternalIdentity<T...>
	return setmetatable({
		_head = 0,
		_collect_queue = {} :: any,
		_collector_count = 0,
		_collector_mask = 0,
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
	if self._collector_count >= 1 then
		table.insert(self._collect_queue, { ..., seen_by = 0 })
	end

	self._head = #self
	while self._head ~= 0 do
		if not free_thread then
			free_thread = tspawn(yield_loop)
		end

		(tspawn :: any)(free_thread, self, ...)
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

function signal.collect<T...>(self: InternalIdentity<T...>): () -> T...
	self._collector_count += 1
	local mask = bitmask(self._collector_count - 1)
	self._collector_mask = bit32.lshift(1, self._collector_count - 1)

	local function iter(): ...unknown
		local collect_queue = self._collect_queue

		for i = #collect_queue, 1, -1 do
			local item = collect_queue[i]
			if get_bit(item.seen_by, mask) then
				continue
			end

			local next_seen_by = set_bit(item.seen_by, mask)

			if all_bits_set(next_seen_by, self._collector_mask) then
				table.remove(collect_queue, i)
				return table.unpack(item)
			end

			item.seen_by = next_seen_by
			return table.unpack(item)
		end

		return
	end

	return iter :: any
end

--[=[
	@method disconnectAll
	@within signal
	
	Disconnects all connections to the signal. This is an efficient operation, utilizing `table.clear`.
]=]
function signal.disconnect_all<T...>(self: InternalIdentity<T...>)
	table.move(NIL_TABLE, 1, #self, 1, self)
end

--[=[
	@method delete
	@within signal
	
	Disconnects all connections to the signal, and renders the signal unusable.
	While this technically isn't required or needed for memory concerns, you might want to use this when you're working with others.
	
	This will prevent and raise an error upon any attempts to use the signal, which is useful for debugging & catching leaks.
]=]
function signal.delete<T...>(self: InternalIdentity<T...>): ()
	self:disconnect_all()

	setmetatable(self, error_tbl)
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
