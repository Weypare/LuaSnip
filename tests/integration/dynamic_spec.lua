local helpers = require("test.functional.helpers")(after_each)
local exec_lua, feed = helpers.exec_lua, helpers.feed
local ls_helpers = require("helpers")
local Screen = require("test.functional.ui.screen")

describe("DynamicNode", function()
	local screen

	before_each(function()
		helpers.clear()
		ls_helpers.session_setup_luasnip()

		screen = Screen.new(50, 3)
		screen:attach()
		screen:set_default_attr_ids({
			[0] = { bold = true, foreground = Screen.colors.Blue },
			[1] = { bold = true, foreground = Screen.colors.Brown },
			[2] = { bold = true },
			[3] = { background = Screen.colors.LightGray },
		})
	end)

	after_each(function()
		screen:detach()
	end)

	it("The snippet is generated.", function()
		local snip = [[
			s("trig", {
				d(1, function(args, snip)
					return sn(nil, {t"yep"})
				end, {})
			})
		]]
		assert.are.same(exec_lua("return "..snip..":get_static_text()"), {"yep"})
		exec_lua("ls.snip_expand("..snip..")")

		screen:expect({
			grid = [[
			yep^                                               |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]],
		})
	end)

	it("The snippet is jumped into and indented.", function()
		local snip = [[
			s("trig", {
				d(1, function(args, snip)
					return sn(nil, { t"yep ", i(1, { "line1", "line2" }) })
				end, {})
			})
		]]
		assert.are.same(exec_lua("return "..snip..":get_static_text()"), {"yep line1", "line2"})
		feed("i<Tab>")
		exec_lua("ls.snip_expand("..snip..")")

		-- selected and indented.
		screen:expect{grid=[[
			        yep ^l{3:ine1}                                 |
			{3:        line2}                                     |
			{2:-- SELECT --}                                      |]]}
	end)

	it("The dynamicNode is updated if dependent changes.", function()
		local snip = [[
			s("trig", {
				i(1, "preset"),
				d(2, function(args, snip)
					return sn(nil, { i(1, args[1]) })
				end, 1)
			})
		]]
		assert.are.same(
			exec_lua("return " .. snip .. ":get_static_text()"),
			{ "presetpreset" }
		)

		exec_lua("ls.snip_expand("..snip..")")
		screen:expect{grid=[[
			^p{3:reset}preset                                      |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]]}

		-- shouldn't be updated yet.
		feed("nomorepreset")
		screen:expect{grid=[[
			nomorepreset^preset                                |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]]}

		exec_lua("ls.active_update_dependents()")
		screen:expect{grid=[[
			nomorepreset^nomorepreset                          |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]]}

		-- check if it updates after jumping.
		feed("reset")
		exec_lua("ls.jump(1)")
		screen:expect{grid=[[
			nomorepresetreset^n{3:omorepresetreset}                |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]]}
	end)

	it("Multiple argnodes update the dynamicNode correctly as well.", function()
		local snip = [[
			s("trig", {
				i(1, "a"),
				i(2, "b"),
				d(3, function(args, snip)
					return sn(nil, { i(1, args[1][1]..args[2][1]) })
				end, {1, 2})
			})
		]]
		assert.are.same(
			exec_lua("return " .. snip .. ":get_static_text()"),
			{ "abab" }
		)

		exec_lua("ls.snip_expand("..snip..")")
		-- one char of selection is just the cursor, so no ${3:...}.
		screen:expect{grid=[[
			^abab                                              |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]]}

		feed("c")
		exec_lua("ls.jump(1)")
		screen:expect{grid=[[
			c^bcb                                              |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]]}

		feed("d")
		exec_lua("ls.active_update_dependents()")
		screen:expect{grid=[[
			cd^cd                                              |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]]}
	end)

	-- test this case here because dynamicNode is responsible for setting up everything
	-- for the restoreNode.
	it("restoreNode works in dynamicNode.", function()
		local snip = [[
			s("trig", {
				i(1, "a"),
				d(2, function(args, snip)
					return sn(nil, { t(args[1]), r(1, "restore_key", i(1, "sample_text")) })
				end, 1)
			})
		]]
		assert.are.same(
			exec_lua("return " .. snip .. ":get_static_text()"),
			{ "aasample_text" }
		)
		exec_lua("ls.snip_expand("..snip..")")
		screen:expect{grid=[[
			^aasample_text                                     |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]]}

		-- change text of insertNode inside restoreNode.
		exec_lua("ls.jump(1)")
		feed("bbb")
		screen:expect{grid=[[
			aabbb^                                             |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]]}

		-- update the dynamicNode (by changing text of the first insertNode), the
		-- textNode should change while the insertNode-changes are preserved.
		exec_lua("ls.jump(-1)")
		feed("c")
		exec_lua("ls.active_update_dependents()")
		screen:expect{grid=[[
			c^cbbb                                             |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]]}
	end)

	it("dynamicNode works in dynamicNode.", function()
		local snip = [[
			s("trig", {
				i(1, "a"),
				d(2, function(args, snip)
					return sn(nil, { i(1, args[1]), d(2, function(args, snip) return sn(nil, { t(args[1]) }) end, 1) })
				end, {1})
			})
		]]
		assert.are.same(
			exec_lua("return " .. snip .. ":get_static_text()"),
			{ "aaa" }
		)
		exec_lua("ls.snip_expand("..snip..")")
		screen:expect{grid=[[
			^aaa                                               |
			{0:~                                                 }|
			{2:-- SELECT --}                                      |]]}
		
		-- update inner dynamicNode.
		exec_lua("ls.jump(1)")
		feed("b")
		exec_lua("ls.active_update_dependents()")
		screen:expect{grid=[[
			ab^b                                               |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]]}


		-- update outer dynamicNode.
		exec_lua("ls.jump(-1)")
		feed("c")
		exec_lua("ls.active_update_dependents()")
		screen:expect{grid=[[
			c^cc                                               |
			{0:~                                                 }|
			{2:-- INSERT --}                                      |]]}
	end)
end)
