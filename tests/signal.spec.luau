local signal = require("@src")
local TEST, CASE, CHECK, FINISH = require("@vendor/testkit").test()
local task = require("@lute/task")

local function spec()
TEST("signal", function()
	CASE("creating doesn't error, and returns a signal")
	do
		CHECK(signal())
	end

	CASE("cannot call methods on deleted signal")
	do
		local sig = signal()

		sig:fire()

		sig:delete()

		local success = pcall(function()
			sig:fire()
		end)

		CHECK(success == false)
	end
end)

TEST("connections", function()
	CASE("connecting adds connection")
	do
		local sig = signal()
		local f = function() end

		sig:connect(f)

		CHECK((sig :: any)[1])
	end

	CASE("disconnecting removes connection")
	do
		local sig = signal()
		local f = function() end

		local connection = sig:connect(f)

		CHECK((sig :: any)[1])

		connection()

		CHECK(not (sig :: any)[1])
	end

	CASE("disconnect all removes all connections")
	do
		local sig = signal() :: signal.Identity<>

		local called = 0
		sig:connect(function()
			called += 1
		end)

		sig:connect(function()
			called += 1
		end)

		sig:disconnect_all()

		sig:fire()

		CHECK(0 == called)
	end
end)

TEST("firing", function()
	CASE("firing resumes wait")
	do
		local sig = signal() :: signal.Identity<>

		local thread = task.spawn(function()
			sig:wait()
		end)

		CHECK(coroutine.status(thread) == "suspended")

		sig:fire()

		CHECK(coroutine.status(thread) == "dead")
	end

	CASE("firing calls connected functions")
	do
		local sig = signal() :: signal.Identity<>

		local called = false
		sig:connect(function()
			called = true
		end)

		sig:fire()

		CHECK(called)
	end

	CASE("firing passes arguments")
	do
		local sig = signal() :: signal.Identity<number>

		local called = false
		sig:connect(function(a)
			called = a == 1
		end)

		sig:fire(1)

		CHECK(called)
	end

	CASE("firing doesn't error with no connections")
	do
		local sig = signal() :: signal.Identity<>

		sig:fire()

		CHECK(true)
	end

	CASE("ordering is preserved")
	do
		local sig = signal()

		local order = {}

		sig:connect(function()
			table.insert(order, 1)
		end)

		sig:connect(function()
			table.insert(order, 2)
		end)

		sig:fire()

		CHECK(order[1] == 2 and order[2] == 1)
	end

	CASE("multiple arguments")
	do
		local sig = signal()

		local values = { true, false, 5, 1, 0 }
		local passed_values = {}

		sig:connect(function(...)
			passed_values = { ... }
		end)

		sig:fire(table.unpack(values))

		local equal = true
		for i, v in values do
			if passed_values[i] ~= v then
				equal = false
				break
			end
		end

		CHECK(equal)
	end
end)

TEST("once", function()
	CASE("once only calls once")
	do
		local sig = signal() :: signal.Identity<>

		local called = 0
		sig:once(function()
			called += 1
		end)

		sig:fire()
		sig:fire()

		CHECK(1 == called)
	end

	CASE("once passes arguments")
	do
		local sig = signal() :: signal.Identity<number>

		local called = false
		sig:once(function(a)
			called = a == 1
		end)

		sig:fire(1)

		CHECK(called)
	end

	CASE("once fires multiple times")
	do
		local sig = signal()

		local order = {}

		sig:once(function()
			table.insert(order, 1)
		end)

		sig:once(function()
			table.insert(order, 2)
		end)

		sig:fire()

		CHECK(order[1] == 2 and order[2] == 1)
	end
end)

TEST("edge cases", function()
	CASE("edge case w multiple threads")
	do
		local sig = signal()

		local thread1 = task.spawn(function()
			sig:wait()
		end)

		local thread2 = task.spawn(function()
			sig:wait()
		end)

		CHECK(coroutine.status(thread1) == "suspended")
		CHECK(coroutine.status(thread2) == "suspended")

		sig:fire()

		CHECK(coroutine.status(thread1) == "dead")
		CHECK(coroutine.status(thread2) == "dead")
	end

	CASE("ordering is preserved with disconnect")
	do
		local sig = signal()

		local order = {}

		local connection1 = sig:connect(function()
			table.insert(order, 1)
		end)

		sig:connect(function()
			table.insert(order, 2)
		end)

		connection1()

		sig:fire()

		CHECK(order[1] == 2)
	end
end)

TEST("yielding/error cases", function()
	CASE("error case")
	do
		local sig = signal()

		local count = 0

		sig:connect(function()
			count += 1
		end)

		sig:connect(function()
			count += 1
			error("error")
			return
		end)
		sig:connect(function()
			count += 1
		end)

		sig:fire()

		CHECK(count == 3)
	end

	CASE("yield case")
	do
		local sig = signal()

		local count = 0

		sig:connect(function()
			count += 1
		end)

		sig:connect(function()
			count += 1
			coroutine.yield()
		end)

		sig:connect(function()
			count += 1
		end)

		sig:fire()

		CHECK(count == 3)
	end

	CASE("yield resumption case")
	do
		local sig = signal()

		local count = 0

		sig:connect(function()
			count += 1
		end)

		sig:once(function()
			count += 1
			task.wait(0.1)
		end)

		sig:connect(function()
			count += 1
		end)

		sig:fire()

		CHECK(count == 3)
	end
end)

TEST("collect", function()
	CASE("basic collection")
	do
		local sig = signal<<(boolean)>>()

		local iter = sig:collect()

		sig:fire(true)

		local set_value = false
		for value in iter do
			set_value = value
		end
		CHECK(set_value == true)
	end
	
	CASE("FILO semantics")
	do
		local sig = signal<<(number)>>()

		local iter = sig:collect()

		sig:fire(1)
		sig:fire(2)
		sig:fire(3)

		local i = 3
		
		for value in iter do
			CHECK(value == i)
			i -= 1
		end
		
		CHECK(i == 0)
	end
	
	CASE("constructing a few collectors works")
	do
		local sig = signal<<(number)>>()

		local iter1 = sig:collect()
		local iter2 = sig:collect()
		
		sig:fire(1)
		sig:fire(2)
		sig:fire(3)

		local i = 3
		
		for value in iter1 do
			i -= 1
		end
		
		CHECK(i == 0)

		i = 3
		
		for value in iter2 do
			i -= 1
		end
		CHECK(i == 0 )
	end
	
	CASE("cleanup works")
	do
		local sig = signal<<(number)>>()

		local iter1 = sig:collect()
		local iter2 = sig:collect()
		
		sig:fire(1)
		sig:fire(2)
		sig:fire(3)

		for value in iter1 do
		end
		
		for value in iter2 do
		end
		
		print(sig._collect_queue, sig._collect_queue[1])
		CHECK(#sig._collect_queue == 0)
	end
	
	CASE("iteration w no events works")
	do
		local sig = signal<<(string)>>()
		
		local iter1 = sig:collect()
		
		for _ in iter1 do
		end
		
		CHECK(true)
	end
	
	CASE("iterator with randomized yielding retains ordering guarantees")
	do
		local sig = signal<<(number)>>()
		
		local iter = sig:collect()
		
		local seen = {}
		
		for i = 1, 50 do
			sig:fire(i)
		end
		
		local threads = {}
		
		for i = 1, 16 do
			threads[i] = task.spawn(function()
				for num in iter do
					if math.random(1, 2) == 1 then
						task.wait()
					end
				
					seen[num] = true
				end
			end)
		end
		
		while true do
			task.wait()
			
			local dead_thread_count = 0
			
			for i = 1, 16 do
				if coroutine.status(threads[i]) == "dead" then
					dead_thread_count += 1
				end
			end
			
			if dead_thread_count == 16 then
				break
			end
		end
		
		for i = 1, 50 do
			CHECK(seen[i])
		end
	end
end)

return FINISH()
end

return spec
