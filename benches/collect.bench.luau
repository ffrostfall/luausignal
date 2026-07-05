--!optimize 2
--!native
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local signal = require(ReplicatedStorage.signal)

return {
	Functions = {
		["bit manip: construct collectors"] = function(Profiler: any)
			local sig = signal()

			Profiler.Begin("construct")
			for i = 1, 31 do
				sig:collect()
			end
			Profiler.End()
		end,

		["bit manip: iterate 50 events"] = function(Profiler: any)
			local sig = signal()

			local iter = sig:collect()

			for i = 1, 50 do
				sig:fire(true)
			end

			Profiler.Begin("iterate")
			for value in iter do
			end
			Profiler.End()
		end,

		["bit manip: iterate 100 events"] = function(Profiler: any)
			local sig = signal()

			local iter = sig:collect()

			for i = 1, 100 do
				sig:fire(true)
			end

			Profiler.Begin("iterate")
			for value in iter do
			end
			Profiler.End()
		end,

		["bit manip: iterate 500 events"] = function(Profiler: any)
			local sig = signal()

			local iter = sig:collect()

			for i = 1, 500 do
				sig:fire(true)
			end

			Profiler.Begin("iterate")
			for value in iter do
			end
			Profiler.End()
		end,

		["bit manip: fire perf w/o collect"] = function(Profiler: any)
			local sig = signal()

			for i = 1, 500 do
				sig:fire(true)
			end
		end,

		["bit manip: fire perf w/ collect"] = function(Profiler: any)
			local sig = signal()

			sig:collect()

			for i = 1, 500 do
				sig:fire(true)
			end
		end,
	},
}
