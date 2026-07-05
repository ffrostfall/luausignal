local task = require("@lute/task")
task.spawn(function()
	require("@tests/signal.spec")()
end)
