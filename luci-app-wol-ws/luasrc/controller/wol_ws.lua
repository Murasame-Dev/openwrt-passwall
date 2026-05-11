module("luci.controller.wol_ws", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/wol_ws") then
		return
	end
	
	entry({"admin", "services", "wol_ws"}, cbi("wol_ws/main"), _("WOL WS & HTTP"), 60).dependent = true
end